# Contract: `InsertionModalBloc` (`lib/features/capture/presentation/bloc/`) — RF02 changes

Same one-bloc-per-modal-open shape RF01 established (`specs/003-multimodal-capture/contracts/
insertion-modal-bloc.md`), still created fresh by `BlocProvider` on every `showModalBottomSheet` call. This
document describes only what changes for the Áudio and Foto tabs; the Texto tab's contract (`InsertionModalTexto`/
`...Saving`/`...Failure`, `TextDraftChanged`, `SaveTextSubmitted`) is unchanged and not repeated here.

```dart
sealed class InsertionModalState extends Equatable {}

// Áudio
class InsertionModalAudioIdle extends InsertionModalState {}                                          // unchanged
class InsertionModalAudioPermissionDenied extends InsertionModalState {}                               // unchanged
class InsertionModalAudioRecording extends InsertionModalState { final Duration elapsed; }             // unchanged
class InsertionModalAudioProcessing extends InsertionModalState { final Duration duration; }
class InsertionModalAudioTranscribed extends InsertionModalState { final String text; final Duration duration; }
class InsertionModalAudioSaving extends InsertionModalState { final String text; final Duration duration; }
class InsertionModalAudioSaveFailure extends InsertionModalState { final String text; final Duration duration; final String message; }
class InsertionModalAudioFailure extends InsertionModalState { final Duration duration; final String message; }

// Foto
class InsertionModalFotoCaptura extends InsertionModalState {}                                         // unchanged
class InsertionModalFotoPermissionDenied extends InsertionModalState {}                                 // unchanged
class InsertionModalFotoProcessing extends InsertionModalState { final String imagePath; }
class InsertionModalFotoReconhecido extends InsertionModalState { final String imagePath; final String text; }
class InsertionModalFotoSaving extends InsertionModalState { final String imagePath; final String text; }
class InsertionModalFotoSaveFailure extends InsertionModalState { final String imagePath; final String text; final String message; }
class InsertionModalFotoFailure extends InsertionModalState { final String imagePath; final String message; }

sealed class InsertionModalEvent {}
class AudioReviewTextChanged extends InsertionModalEvent { final String text; }
class AudioSaveConfirmed extends InsertionModalEvent {}
class PhotoReviewTextChanged extends InsertionModalEvent { final String text; }
class PhotoSaveConfirmed extends InsertionModalEvent {}
class PhotoSaveWithoutTextRequested extends InsertionModalEvent {}
// TabSelected, TextDraftChanged, SaveTextSubmitted, AudioTimerTicked, AudioStartRequested,
// AudioStopRequested, PhotoSourceSelected, RetryRequested, ModalClosed — all reused unchanged in shape.
```

## Handler changes

- **`AudioStopRequested`** (ignored unless `state is InsertionModalAudioRecording`): stops the ticker, calls
  `AudioCaptureRepository.stop()` for the path (stored in `_pendingAudioPath`), captures the final `elapsed`
  as `duration`, and emits `InsertionModalAudioProcessing(duration)` — **no connectivity check** (research.md
  R1). It then awaits `AudioTranscriptionRepository.transcribe(path)` directly (no usecase wrapper — the
  repository call has no orchestration left to add). Before applying the result, it checks `state is
  InsertionModalAudioProcessing && _pendingAudioPath == path`; if that no longer holds (the user switched
  tabs/closed the modal meanwhile), the result is discarded (research.md R6). Otherwise:
  `Left(EmptyRecognitionResult())`/`Left(TranscriptionError())` map to `InsertionModalAudioFailure(duration,
  message)` (data-model.md's message table, unchanged from RF01's `_audioFailureMessage` minus its
  entry-creation branch); `Right(text)` sets `_audioReviewText = text` and emits
  `InsertionModalAudioTranscribed(text, duration)` — **no entry created**.
- **`AudioReviewTextChanged(text)`** (from `InsertionModalAudioTranscribed` or
  `InsertionModalAudioSaveFailure`): sets `_audioReviewText = text` and re-emits the same state subtype with
  the updated text, same `duration`/other fields held.
- **`AudioSaveConfirmed`** (ignored unless `state is InsertionModalAudioTranscribed ||
  state is InsertionModalAudioSaveFailure`, and `_audioReviewText` is non-empty/non-whitespace — mirrors the
  Texto tab's own "Salvar" guard): emits `InsertionModalAudioSaving(_audioReviewText, duration)`, awaits
  `ConfirmEntrySaveUseCase(_audioReviewText, EntrySource.audio)`. `Right(entry)` clears `_pendingAudioPath`
  and triggers the existing one-shot `closeRequests` side effect (unchanged from RF01 — the page pops the
  sheet). `Left(ConfirmEntrySaveOffline())`/`Left(ConfirmEntrySaveCreationFailed(f))` map to
  `InsertionModalAudioSaveFailure(_audioReviewText, duration, message)` — the audio file and reviewed text
  both stay held; a repeat `AudioSaveConfirmed` is the retry (research.md R5).
- **`PhotoSourceSelected(source)`** (ignored if a save/recognition is already in flight for this tab): calls
  `PhotoCaptureRepository.pickImage(source)`; `null` (cancelled) stays `InsertionModalFotoCaptura()`; a path
  is stored in `_pendingImagePath`, emits `InsertionModalFotoProcessing(path)`, then awaits
  `RecognizePhotoUseCase(path)` (this one *does* go through a usecase — it still has the connectivity gate to
  perform, research.md R1 vs. audio). Same stale-result guard as audio (`state is InsertionModalFotoProcessing
  && _pendingImagePath == path`) before applying the result. `Left(PhotoRecognitionOffline())` maps to
  `InsertionModalFotoFailure(path, offlineMessage)`; `Left(PhotoRecognitionCallFailed(f))` maps to
  `InsertionModalFotoFailure(path, message)` using the same `f is OcrNoTextFailure ? noTextMessage :
  f.message` branch RF01's `_photoFailureMessage` already used. `Right(ocrResult)` sets `_photoReviewText =
  ocrResult.text` and emits `InsertionModalFotoReconhecido(path, ocrResult.text)` — confidence read but never
  branched on (Clarification 3).
- **`PhotoReviewTextChanged(text)`**: same shape as the audio equivalent, for `InsertionModalFotoReconhecido`/
  `InsertionModalFotoSaveFailure`.
- **`PhotoSaveConfirmed`** (ignored unless `state is InsertionModalFotoReconhecido ||
  state is InsertionModalFotoSaveFailure`, text non-empty): same shape as `AudioSaveConfirmed`, with
  `EntrySource.photo` and `InsertionModalFotoSaving`/`InsertionModalFotoSaveFailure` in place of the audio
  states.
- **`PhotoSaveWithoutTextRequested`** (ignored unless `state is InsertionModalFotoFailure`): emits
  `InsertionModalFotoSaving(path, _photoNoTextPlaceholder)` directly — **no further OCR call** (FR-008) —
  then awaits `ConfirmEntrySaveUseCase(_photoNoTextPlaceholder, EntrySource.photo)` with the same
  success/failure mapping as `PhotoSaveConfirmed`.
- **`RetryRequested`**: from `InsertionModalAudioFailure` (with `_pendingAudioPath != null`), re-enters the
  `AudioStopRequested` handler's transcription branch (emits `InsertionModalAudioProcessing(duration)` first)
  against the same path — no new recording. From `InsertionModalFotoFailure` (with `_pendingImagePath !=
  null`), re-enters the `PhotoSourceSelected` handler's recognition branch (emits
  `InsertionModalFotoProcessing(path)` first) against the same path — no new picker call. A repeat
  `RetryRequested` while already `*Processing` is a no-op (the guard above already excludes it, since
  `*Processing` isn't `*Failure`).
- **`TabSelected(<anything>)`** while any Áudio sub-state beyond `Idle`/`Recording` (i.e., `Processing`,
  `Transcribed`, `Saving`, `SaveFailure`, `Failure`): clears `_pendingAudioPath`/`_audioReviewText` before
  emitting the target tab's state — any in-flight or completed-but-unreviewed recognition is abandoned
  (FR-011). Same for Foto's equivalent sub-states and `_pendingImagePath`/`_photoReviewText`. The existing
  mid-`Recording` discard (`AudioCaptureRepository.discard()`) is unchanged.
- **`ModalClosed`**: extends RF01's existing "discard an in-progress recording" behavior to also clear
  `_pendingAudioPath`/`_audioReviewText`/`_pendingImagePath`/`_photoReviewText` unconditionally — nothing
  from an abandoned recognition/review survives disposal (FR-011), matching the `close()` override's own
  existing fallback path for the swipe-down/tap-outside dismissal case.

## Who depends on this

`AudioTabView` renders `InsertionModalAudioProcessing` (spinner in place of the stop control + `Opacity(0.35)`
around the existing `AudioWaveform` + "Transcrevendo..." + `duration`), `InsertionModalAudioTranscribed` (an
editable `TextFormField` seeded from `text`, `duration` in `DesignTokens.textMonoCaption`, "Salvar" enabled
iff the field is non-empty/non-whitespace), `InsertionModalAudioSaveFailure` (the same editable field plus an
inline `colorError` message, "Salvar" still enabled), and `InsertionModalAudioFailure` (the new
`RecognitionErrorView`, one action). `FotoTabView` renders the equivalent four Foto states, each additionally
showing an `Image.file(File(imagePath))` thumbnail at `DesignTokens.sizePhotoThumbnail`, and
`InsertionModalFotoFailure`'s `RecognitionErrorView` with its second action, "Salvar só a foto"
(`PhotoSaveWithoutTextRequested`). `InsertionModalPage`'s `_tabOf` switch is extended with the new state
cases, same exhaustive-pattern-match convention as RF01.
