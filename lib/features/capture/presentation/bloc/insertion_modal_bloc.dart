import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:cerne/features/capture/domain/usecases/save_audio_entry_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/save_photo_entry_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/save_text_entry_usecase.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _offlineMessage = 'Sem conexão. Conecte-se à internet para salvar.';
const _noSpeechMessage = 'Não foi possível identificar fala no áudio.';
const _genericAudioMessage = 'Não foi possível processar o áudio.';
const _noTextMessage = 'Não foi possível identificar texto na imagem.';

/// One screen-scoped bloc for the whole Insertion Modal
/// (contracts/insertion-modal-bloc.md) — created fresh by `BlocProvider`
/// every time `showModalBottomSheet` opens the modal, which is what makes
/// FR-002's "reset every tab... each time the modal is freshly opened" true
/// without an explicit reset event.
class InsertionModalBloc
    extends Bloc<InsertionModalEvent, InsertionModalState> {
  InsertionModalBloc({
    required this._saveTextEntryUseCase,
    required this._audioCaptureRepository,
    required this._saveAudioEntryUseCase,
    required this._photoCaptureRepository,
    required this._savePhotoEntryUseCase,
  }) : super(const InsertionModalTexto()) {
    on<TabSelected>(_onTabSelected);
    on<TextDraftChanged>(_onTextDraftChanged);
    on<SaveTextSubmitted>(_onSaveTextSubmitted);
    on<AudioStartRequested>(_onAudioStartRequested);
    on<AudioTimerTicked>(_onAudioTimerTicked);
    on<AudioStopRequested>(_onAudioStopRequested);
    on<PhotoSourceSelected>(_onPhotoSourceSelected);
    on<RetryRequested>(_onRetryRequested);
    on<ModalClosed>(_onModalClosed);
  }

  final SaveTextEntryUseCase _saveTextEntryUseCase;
  final AudioCaptureRepository _audioCaptureRepository;
  final SaveAudioEntryUseCase _saveAudioEntryUseCase;
  final PhotoCaptureRepository _photoCaptureRepository;
  final SavePhotoEntryUseCase _savePhotoEntryUseCase;

  final _closeController = StreamController<void>.broadcast();

  /// A one-shot side effect, not a state (FR-011, contracts/
  /// insertion-modal-bloc.md) — `InsertionModalPage` listens to this to pop
  /// the sheet. There is nothing to render for "success", so it never
  /// becomes a dedicated `InsertionModalState` case.
  Stream<void> get closeRequests => _closeController.stream;

  String _textDraft = '';
  String? _pendingAudioPath;
  String? _pendingImagePath;
  Timer? _audioTicker;

  /// Guards against discarding the same recording twice when both the
  /// explicit `ModalClosed` handler and `close()`'s disposal-time fallback
  /// (T073, for the swipe-down/tap-outside dismissal that bypasses
  /// `ModalClosed`) would otherwise race on the same still-recording state.
  bool _recordingDiscarded = false;

  Future<void> _onTabSelected(
    TabSelected event,
    Emitter<InsertionModalState> emit,
  ) async {
    if (state is InsertionModalAudioRecording) {
      // Switching away mid-recording discards it (Edge Cases) — nothing
      // from an abandoned capture may survive (FR-008).
      _audioCaptureRepository.discard();
      _recordingDiscarded = true;
      _stopAudioTicker();
      _pendingAudioPath = null;
    }

    switch (event.tab) {
      case CaptureTab.texto:
        emit(InsertionModalTexto(text: _textDraft));
      case CaptureTab.audio:
        emit(const InsertionModalAudioIdle());
      case CaptureTab.foto:
        emit(const InsertionModalFotoCaptura());
    }
  }

  Future<void> _onAudioStartRequested(
    AudioStartRequested event,
    Emitter<InsertionModalState> emit,
  ) async {
    if (state is! InsertionModalAudioIdle) return;

    final hasPermission = await _audioCaptureRepository.hasPermission();
    if (!hasPermission) {
      emit(const InsertionModalAudioPermissionDenied());
      return;
    }
    await _audioCaptureRepository.start();
    _recordingDiscarded = false;
    emit(const InsertionModalAudioRecording(elapsed: Duration.zero));
    _startAudioTicker();
  }

  void _startAudioTicker() {
    _audioTicker?.cancel();
    _audioTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const AudioTimerTicked()),
    );
  }

  void _stopAudioTicker() {
    _audioTicker?.cancel();
    _audioTicker = null;
  }

  void _onTextDraftChanged(
    TextDraftChanged event,
    Emitter<InsertionModalState> emit,
  ) {
    _textDraft = event.text;
    emit(InsertionModalTexto(text: event.text));
  }

  void _onAudioTimerTicked(
    AudioTimerTicked event,
    Emitter<InsertionModalState> emit,
  ) {
    final current = state;
    if (current is InsertionModalAudioRecording) {
      emit(
        InsertionModalAudioRecording(
          elapsed: current.elapsed + const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _onSaveTextSubmitted(
    SaveTextSubmitted event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    final text = switch (current) {
      InsertionModalTexto(text: final t) => t,
      InsertionModalTextoFailure(text: final t) => t,
      _ => null,
    };
    if (text == null || text.trim().isEmpty) return;

    emit(InsertionModalTextoSaving(text));
    final result = await _saveTextEntryUseCase(text);
    result.match(
      (failure) => emit(
        InsertionModalTextoFailure(text: text, message: failure.message),
      ),
      (entry) => _completeSave(),
    );
  }

  Future<void> _onAudioStopRequested(
    AudioStopRequested event,
    Emitter<InsertionModalState> emit,
  ) async {
    if (state is! InsertionModalAudioRecording) return;

    _stopAudioTicker();
    final path = await _audioCaptureRepository.stop();
    _pendingAudioPath = path;
    emit(const InsertionModalAudioSaving());
    await _saveAudio(path, emit);
  }

  Future<void> _saveAudio(
    String audioFilePath,
    Emitter<InsertionModalState> emit,
  ) async {
    final result = await _saveAudioEntryUseCase(audioFilePath);
    result.match(
      (failure) =>
          emit(InsertionModalAudioFailure(_audioFailureMessage(failure))),
      (entry) {
        _pendingAudioPath = null;
        _completeSave();
      },
    );
  }

  String _audioFailureMessage(SaveAudioFailure failure) => switch (failure) {
    SaveAudioOffline() => _offlineMessage,
    SaveAudioRecognitionFailed(:final recognitionFailure) =>
      switch (recognitionFailure) {
        EmptyRecognitionResult() => _noSpeechMessage,
        TranscriptionError() => _genericAudioMessage,
      },
    SaveAudioEntryCreationFailed(failure: final f) => f.message,
  };

  Future<void> _onPhotoSourceSelected(
    PhotoSourceSelected event,
    Emitter<InsertionModalState> emit,
  ) async {
    if (state is InsertionModalFotoSaving) return;

    String? path;
    try {
      path = await _photoCaptureRepository.pickImage(event.source);
    } catch (_) {
      emit(const InsertionModalFotoPermissionDenied());
      return;
    }

    if (path == null) {
      emit(const InsertionModalFotoCaptura());
      return;
    }

    _pendingImagePath = path;
    emit(const InsertionModalFotoSaving());
    await _savePhoto(path, emit);
  }

  Future<void> _savePhoto(
    String imageFilePath,
    Emitter<InsertionModalState> emit,
  ) async {
    final result = await _savePhotoEntryUseCase(imageFilePath);
    result.match(
      (failure) =>
          emit(InsertionModalFotoFailure(_photoFailureMessage(failure))),
      (entry) {
        _pendingImagePath = null;
        _completeSave();
      },
    );
  }

  String _photoFailureMessage(SavePhotoFailure failure) => switch (failure) {
    SavePhotoOffline() => _offlineMessage,
    SavePhotoRecognitionFailed(failure: final f) =>
      f is OcrNoTextFailure ? _noTextMessage : f.message,
    SavePhotoEntryCreationFailed(failure: final f) => f.message,
  };

  Future<void> _onRetryRequested(
    RetryRequested event,
    Emitter<InsertionModalState> emit,
  ) async {
    final audioPath = _pendingAudioPath;
    final imagePath = _pendingImagePath;
    if (state is InsertionModalAudioFailure && audioPath != null) {
      emit(const InsertionModalAudioSaving());
      await _saveAudio(audioPath, emit);
    } else if (state is InsertionModalFotoFailure && imagePath != null) {
      emit(const InsertionModalFotoSaving());
      await _savePhoto(imagePath, emit);
    }
  }

  void _onModalClosed(ModalClosed event, Emitter<InsertionModalState> emit) {
    if (state is InsertionModalAudioRecording) {
      _audioCaptureRepository.discard();
      _recordingDiscarded = true;
      _stopAudioTicker();
    }
    _pendingAudioPath = null;
    _pendingImagePath = null;
  }

  void _completeSave() {
    if (!_closeController.isClosed) {
      _closeController.add(null);
    }
  }

  @override
  Future<void> close() {
    if (state is InsertionModalAudioRecording && !_recordingDiscarded) {
      // `showModalBottomSheet`'s default swipe-down/tap-outside dismissal
      // bypasses `ModalClosed` entirely, so this is the only place that
      // reliably catches a still-recording mic at disposal time (FR-008).
      _audioCaptureRepository.discard();
      _recordingDiscarded = true;
      _pendingAudioPath = null;
    }
    _stopAudioTicker();
    unawaited(_closeController.close());
    return super.close();
  }
}
