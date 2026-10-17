import 'package:equatable/equatable.dart';

/// Covers every branch `InsertionModalPage`'s single screen must represent
/// (data-model.md State transitions) — one `InsertionModalBloc` instance
/// per modal open (contracts/insertion-modal-bloc.md).
sealed class InsertionModalState extends Equatable {
  const InsertionModalState();

  @override
  List<Object?> get props => [];
}

/// Initial state (FR-002's default tab) and every revisit of the Texto tab.
class InsertionModalTexto extends InsertionModalState {
  const InsertionModalTexto({this.text = ''});

  final String text;

  @override
  List<Object?> get props => [text];
}

class InsertionModalTextoSaving extends InsertionModalState {
  const InsertionModalTextoSaving(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

class InsertionModalTextoFailure extends InsertionModalState {
  const InsertionModalTextoFailure({required this.text, required this.message});

  final String text;
  final String message;

  @override
  List<Object?> get props => [text, message];
}

/// Default state on entering the "Áudio" tab — a round start control and
/// the "Toque para gravar" caption; recording begins only once the user
/// taps it (FR-004).
class InsertionModalAudioIdle extends InsertionModalState {
  const InsertionModalAudioIdle();
}

class InsertionModalAudioPermissionDenied extends InsertionModalState {
  const InsertionModalAudioPermissionDenied();
}

class InsertionModalAudioRecording extends InsertionModalState {
  const InsertionModalAudioRecording({required this.elapsed});

  final Duration elapsed;

  @override
  List<Object?> get props => [elapsed];
}

/// "Áudio — Processando" (FR-001) — on-device transcription in flight, no
/// entry exists yet.
class InsertionModalAudioProcessing extends InsertionModalState {
  const InsertionModalAudioProcessing({required this.duration});

  final Duration duration;

  @override
  List<Object?> get props => [duration];
}

/// "Áudio — Transcrito" (FR-002) — the editable review state; no entry
/// exists until "Salvar" is tapped from here.
class InsertionModalAudioTranscribed extends InsertionModalState {
  const InsertionModalAudioTranscribed({
    required this.text,
    required this.duration,
  });

  final String text;
  final Duration duration;

  @override
  List<Object?> get props => [text, duration];
}

/// `entries-create` in flight, for either a normal "Salvar" from Transcrito
/// or a retry from AudioSaveFailure (FR-010).
class InsertionModalAudioSaving extends InsertionModalState {
  const InsertionModalAudioSaving({required this.text, required this.duration});

  final String text;
  final Duration duration;

  @override
  List<Object?> get props => [text, duration];
}

/// A save-call failure after a successful transcription (research.md R5) —
/// keeps the reviewed/edited text on screen; retrying is simply tapping
/// "Salvar" again, no re-transcription.
class InsertionModalAudioSaveFailure extends InsertionModalState {
  const InsertionModalAudioSaveFailure({
    required this.text,
    required this.duration,
    required this.message,
  });

  final String text;
  final Duration duration;
  final String message;

  @override
  List<Object?> get props => [text, duration, message];
}

/// "Áudio — Erro" — transcription itself failed; no entry exists and no
/// reviewed text was ever produced.
class InsertionModalAudioFailure extends InsertionModalState {
  const InsertionModalAudioFailure({required this.duration, required this.message});

  final Duration duration;
  final String message;

  @override
  List<Object?> get props => [duration, message];
}

class InsertionModalFotoCaptura extends InsertionModalState {
  const InsertionModalFotoCaptura();
}

class InsertionModalFotoPermissionDenied extends InsertionModalState {
  const InsertionModalFotoPermissionDenied();
}

/// "Foto — Processando OCR" (FR-005) — recognition in flight, no entry
/// exists yet.
class InsertionModalFotoProcessing extends InsertionModalState {
  const InsertionModalFotoProcessing({required this.imagePath});

  final String imagePath;

  @override
  List<Object?> get props => [imagePath];
}

/// "Foto — Reconhecido" (FR-006) — the editable review state (thumbnail +
/// text); no entry exists until "Salvar" is tapped from here.
class InsertionModalFotoReconhecido extends InsertionModalState {
  const InsertionModalFotoReconhecido({
    required this.imagePath,
    required this.text,
  });

  final String imagePath;
  final String text;

  @override
  List<Object?> get props => [imagePath, text];
}

/// `entries-create` in flight — a normal "Salvar" from Reconhecido, a retry
/// from FotoSaveFailure, or "Salvar só a foto" from FotoFailure (FR-008/
/// FR-010).
class InsertionModalFotoSaving extends InsertionModalState {
  const InsertionModalFotoSaving({required this.imagePath, required this.text});

  final String imagePath;
  final String text;

  @override
  List<Object?> get props => [imagePath, text];
}

/// A save-call failure after a successful recognition (research.md R5) —
/// keeps the reviewed/edited text and thumbnail on screen; retrying is
/// simply tapping "Salvar" again, no re-OCR.
class InsertionModalFotoSaveFailure extends InsertionModalState {
  const InsertionModalFotoSaveFailure({
    required this.imagePath,
    required this.text,
    required this.message,
  });

  final String imagePath;
  final String text;
  final String message;

  @override
  List<Object?> get props => [imagePath, text, message];
}

/// "Foto — Erro" — OCR itself failed; offers "Tentar novamente" and
/// "Salvar só a foto".
class InsertionModalFotoFailure extends InsertionModalState {
  const InsertionModalFotoFailure({required this.imagePath, required this.message});

  final String imagePath;
  final String message;

  @override
  List<Object?> get props => [imagePath, message];
}
