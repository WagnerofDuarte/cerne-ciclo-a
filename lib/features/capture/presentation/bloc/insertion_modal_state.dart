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

class InsertionModalAudioSaving extends InsertionModalState {
  const InsertionModalAudioSaving();
}

class InsertionModalAudioFailure extends InsertionModalState {
  const InsertionModalAudioFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class InsertionModalFotoCaptura extends InsertionModalState {
  const InsertionModalFotoCaptura();
}

class InsertionModalFotoPermissionDenied extends InsertionModalState {
  const InsertionModalFotoPermissionDenied();
}

class InsertionModalFotoSaving extends InsertionModalState {
  const InsertionModalFotoSaving();
}

class InsertionModalFotoFailure extends InsertionModalState {
  const InsertionModalFotoFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
