import 'dart:async';

import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/audio_transcription_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:cerne/features/capture/domain/usecases/confirm_entry_save_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/recognize_photo_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/save_text_entry_usecase.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _offlineMessage = 'Sem conexão. Conecte-se à internet para salvar.';
const _noSpeechMessage = 'Não foi possível identificar fala no áudio.';
const _genericAudioMessage = 'Não foi possível transcrever';
const _noTextMessage = 'Não foi possível reconhecer o texto — tente outra foto.';

/// The fixed placeholder sent as `content` for "Salvar só a foto"
/// (research.md R3) — a single `const` at this, its one call site.
const _photoNoTextPlaceholder = 'Foto registrada sem texto reconhecido.';

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
    required this._audioTranscriptionRepository,
    required this._confirmEntrySaveUseCase,
    required this._photoCaptureRepository,
    required this._recognizePhotoUseCase,
  }) : super(const InsertionModalTexto()) {
    on<TabSelected>(_onTabSelected);
    on<TextDraftChanged>(_onTextDraftChanged);
    on<SaveTextSubmitted>(_onSaveTextSubmitted);
    on<AudioStartRequested>(_onAudioStartRequested);
    on<AudioTimerTicked>(_onAudioTimerTicked);
    on<AudioStopRequested>(_onAudioStopRequested);
    on<AudioReviewTextChanged>(_onAudioReviewTextChanged);
    on<AudioSaveConfirmed>(_onAudioSaveConfirmed);
    on<PhotoSourceSelected>(_onPhotoSourceSelected);
    on<PhotoReviewTextChanged>(_onPhotoReviewTextChanged);
    on<PhotoSaveConfirmed>(_onPhotoSaveConfirmed);
    on<PhotoSaveWithoutTextRequested>(_onPhotoSaveWithoutTextRequested);
    on<RetryRequested>(_onRetryRequested);
    on<ModalClosed>(_onModalClosed);
  }

  final SaveTextEntryUseCase _saveTextEntryUseCase;
  final AudioCaptureRepository _audioCaptureRepository;
  final AudioTranscriptionRepository _audioTranscriptionRepository;
  final ConfirmEntrySaveUseCase _confirmEntrySaveUseCase;
  final PhotoCaptureRepository _photoCaptureRepository;
  final RecognizePhotoUseCase _recognizePhotoUseCase;

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
  /// (for the swipe-down/tap-outside dismissal that bypasses `ModalClosed`)
  /// would otherwise race on the same still-recording state.
  bool _recordingDiscarded = false;

  bool _isAudioAbandonable(InsertionModalState state) =>
      state is InsertionModalAudioProcessing ||
      state is InsertionModalAudioTranscribed ||
      state is InsertionModalAudioSaving ||
      state is InsertionModalAudioSaveFailure ||
      state is InsertionModalAudioFailure;

  bool _isFotoAbandonable(InsertionModalState state) =>
      state is InsertionModalFotoProcessing ||
      state is InsertionModalFotoReconhecido ||
      state is InsertionModalFotoSaving ||
      state is InsertionModalFotoSaveFailure ||
      state is InsertionModalFotoFailure;

  Future<void> _onTabSelected(
    TabSelected event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    if (current is InsertionModalAudioRecording) {
      // Switching away mid-recording discards it (Edge Cases) — nothing
      // from an abandoned capture may survive (FR-011).
      _audioCaptureRepository.discard();
      _recordingDiscarded = true;
      _stopAudioTicker();
      _pendingAudioPath = null;
    } else if (_isAudioAbandonable(current)) {
      // Leaving any in-flight/reviewed/failed Áudio sub-state abandons the
      // held audio and any unsaved review edits (FR-011, data-model.md's
      // transition table).
      _pendingAudioPath = null;
    }

    if (_isFotoAbandonable(current)) {
      _pendingImagePath = null;
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
    final current = state;
    if (current is! InsertionModalAudioRecording) return;

    _stopAudioTicker();
    final duration = current.elapsed;
    final path = await _audioCaptureRepository.stop();
    _pendingAudioPath = path;
    // No connectivity gate (FR-001, research.md R1) — on-device
    // transcription must begin unconditionally on stop.
    emit(InsertionModalAudioProcessing(duration: duration));
    await _transcribeAudio(path, duration, emit);
  }

  Future<void> _transcribeAudio(
    String audioFilePath,
    Duration duration,
    Emitter<InsertionModalState> emit,
  ) async {
    final result = await _audioTranscriptionRepository.transcribe(
      audioFilePath,
    );

    // The user may have switched tabs/closed the modal while transcription
    // was running — discard a stale result outright (research.md R6,
    // FR-011/User Story 5).
    if (state is! InsertionModalAudioProcessing ||
        _pendingAudioPath != audioFilePath) {
      return;
    }

    result.match(
      (failure) => emit(
        InsertionModalAudioFailure(
          duration: duration,
          message: _recognitionFailureMessage(failure),
        ),
      ),
      (text) =>
          emit(InsertionModalAudioTranscribed(text: text, duration: duration)),
    );
  }

  String _recognitionFailureMessage(RecognitionFailure failure) =>
      switch (failure) {
        EmptyRecognitionResult() => _noSpeechMessage,
        TranscriptionError() => _genericAudioMessage,
      };

  void _onAudioReviewTextChanged(
    AudioReviewTextChanged event,
    Emitter<InsertionModalState> emit,
  ) {
    final current = state;
    if (current is InsertionModalAudioTranscribed) {
      emit(
        InsertionModalAudioTranscribed(
          text: event.text,
          duration: current.duration,
        ),
      );
    } else if (current is InsertionModalAudioSaveFailure) {
      emit(
        InsertionModalAudioSaveFailure(
          text: event.text,
          duration: current.duration,
          message: current.message,
        ),
      );
    }
  }

  Future<void> _onAudioSaveConfirmed(
    AudioSaveConfirmed event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    final (text, duration) = switch (current) {
      InsertionModalAudioTranscribed(text: final t, duration: final d) => (
        t,
        d,
      ),
      InsertionModalAudioSaveFailure(text: final t, duration: final d) => (
        t,
        d,
      ),
      _ => (null, null),
    };
    if (text == null || duration == null || text.trim().isEmpty) return;

    emit(InsertionModalAudioSaving(text: text, duration: duration));
    final result = await _confirmEntrySaveUseCase(text, EntrySource.audio);
    result.match(
      (failure) => emit(
        InsertionModalAudioSaveFailure(
          text: text,
          duration: duration,
          message: _confirmSaveFailureMessage(failure),
        ),
      ),
      (entry) {
        _pendingAudioPath = null;
        _completeSave();
      },
    );
  }

  Future<void> _onPhotoSourceSelected(
    PhotoSourceSelected event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    if (current is InsertionModalFotoProcessing ||
        current is InsertionModalFotoSaving) {
      return;
    }

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
    emit(InsertionModalFotoProcessing(imagePath: path));
    await _recognizePhoto(path, emit);
  }

  Future<void> _recognizePhoto(
    String imageFilePath,
    Emitter<InsertionModalState> emit,
  ) async {
    final result = await _recognizePhotoUseCase(imageFilePath);

    // Same stale-result guard as audio (research.md R6).
    if (state is! InsertionModalFotoProcessing ||
        _pendingImagePath != imageFilePath) {
      return;
    }

    result.match(
      (failure) => emit(
        InsertionModalFotoFailure(
          imagePath: imageFilePath,
          message: _photoRecognitionFailureMessage(failure),
        ),
      ),
      // confidence read but never branched on (Clarification 3).
      (ocrResult) => emit(
        InsertionModalFotoReconhecido(
          imagePath: imageFilePath,
          text: ocrResult.text,
        ),
      ),
    );
  }

  // Every failed OCR call — not just "no text found" — shows the same
  // "Foto — Erro" copy (FR-007: "If the OCR call fails (including a
  // no-usable-text result)..."), never the raw backend `message`.
  String _photoRecognitionFailureMessage(
    PhotoRecognitionAttemptFailure failure,
  ) => switch (failure) {
    PhotoRecognitionOffline() => _offlineMessage,
    PhotoRecognitionCallFailed() => _noTextMessage,
  };

  void _onPhotoReviewTextChanged(
    PhotoReviewTextChanged event,
    Emitter<InsertionModalState> emit,
  ) {
    final current = state;
    if (current is InsertionModalFotoReconhecido) {
      emit(
        InsertionModalFotoReconhecido(
          imagePath: current.imagePath,
          text: event.text,
        ),
      );
    } else if (current is InsertionModalFotoSaveFailure) {
      emit(
        InsertionModalFotoSaveFailure(
          imagePath: current.imagePath,
          text: event.text,
          message: current.message,
        ),
      );
    }
  }

  Future<void> _onPhotoSaveConfirmed(
    PhotoSaveConfirmed event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    final (imagePath, text) = switch (current) {
      InsertionModalFotoReconhecido(imagePath: final p, text: final t) => (
        p,
        t,
      ),
      InsertionModalFotoSaveFailure(imagePath: final p, text: final t) => (
        p,
        t,
      ),
      _ => (null, null),
    };
    if (imagePath == null || text == null || text.trim().isEmpty) return;

    await _confirmPhotoSave(imagePath, text, emit);
  }

  Future<void> _onPhotoSaveWithoutTextRequested(
    PhotoSaveWithoutTextRequested event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    if (current is! InsertionModalFotoFailure) return;

    // No further OCR call for this capture (FR-008) — saves immediately
    // with the fixed placeholder.
    await _confirmPhotoSave(current.imagePath, _photoNoTextPlaceholder, emit);
  }

  Future<void> _confirmPhotoSave(
    String imagePath,
    String text,
    Emitter<InsertionModalState> emit,
  ) async {
    emit(InsertionModalFotoSaving(imagePath: imagePath, text: text));
    final result = await _confirmEntrySaveUseCase(text, EntrySource.photo);
    result.match(
      (failure) => emit(
        InsertionModalFotoSaveFailure(
          imagePath: imagePath,
          text: text,
          message: _confirmSaveFailureMessage(failure),
        ),
      ),
      (entry) {
        _pendingImagePath = null;
        _completeSave();
      },
    );
  }

  String _confirmSaveFailureMessage(ConfirmEntrySaveFailure failure) =>
      switch (failure) {
        ConfirmEntrySaveOffline() => _offlineMessage,
        ConfirmEntrySaveCreationFailed(failure: final f) => f.message,
      };

  Future<void> _onRetryRequested(
    RetryRequested event,
    Emitter<InsertionModalState> emit,
  ) async {
    final current = state;
    final audioPath = _pendingAudioPath;
    final imagePath = _pendingImagePath;
    if (current is InsertionModalAudioFailure && audioPath != null) {
      final duration = current.duration;
      emit(InsertionModalAudioProcessing(duration: duration));
      await _transcribeAudio(audioPath, duration, emit);
    } else if (current is InsertionModalFotoFailure && imagePath != null) {
      emit(InsertionModalFotoProcessing(imagePath: imagePath));
      await _recognizePhoto(imagePath, emit);
    }
  }

  void _onModalClosed(ModalClosed event, Emitter<InsertionModalState> emit) {
    if (state is InsertionModalAudioRecording) {
      _audioCaptureRepository.discard();
      _recordingDiscarded = true;
      _stopAudioTicker();
    }
    // Unconditionally clears every held capture, regardless of which
    // Áudio/Foto sub-state is active when the modal closes (FR-011).
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
      // reliably catches a still-recording mic at disposal time (FR-011).
      _audioCaptureRepository.discard();
      _recordingDiscarded = true;
      _pendingAudioPath = null;
    }
    _stopAudioTicker();
    unawaited(_closeController.close());
    return super.close();
  }
}
