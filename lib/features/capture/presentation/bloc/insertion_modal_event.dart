import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:equatable/equatable.dart';

enum CaptureTab { texto, audio, foto }

sealed class InsertionModalEvent extends Equatable {
  const InsertionModalEvent();

  @override
  List<Object?> get props => [];
}

class TabSelected extends InsertionModalEvent {
  const TabSelected(this.tab);

  final CaptureTab tab;

  @override
  List<Object?> get props => [tab];
}

class TextDraftChanged extends InsertionModalEvent {
  const TextDraftChanged(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

class SaveTextSubmitted extends InsertionModalEvent {
  const SaveTextSubmitted();
}

/// Internal, drives `elapsed` only — dispatched by a local 1-second ticker,
/// no network, no recognition.
class AudioTimerTicked extends InsertionModalEvent {
  const AudioTimerTicked();
}

class AudioStartRequested extends InsertionModalEvent {
  const AudioStartRequested();
}

class AudioStopRequested extends InsertionModalEvent {
  const AudioStopRequested();
}

class AudioReviewTextChanged extends InsertionModalEvent {
  const AudioReviewTextChanged(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

class AudioSaveConfirmed extends InsertionModalEvent {
  const AudioSaveConfirmed();
}

class PhotoSourceSelected extends InsertionModalEvent {
  const PhotoSourceSelected(this.source);

  final PhotoSource source;

  @override
  List<Object?> get props => [source];
}

class PhotoReviewTextChanged extends InsertionModalEvent {
  const PhotoReviewTextChanged(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

class PhotoSaveConfirmed extends InsertionModalEvent {
  const PhotoSaveConfirmed();
}

class PhotoSaveWithoutTextRequested extends InsertionModalEvent {
  const PhotoSaveWithoutTextRequested();
}

class RetryRequested extends InsertionModalEvent {
  const RetryRequested();
}

class ModalClosed extends InsertionModalEvent {
  const ModalClosed();
}
