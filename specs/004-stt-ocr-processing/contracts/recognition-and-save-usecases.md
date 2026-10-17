# Contract: Recognition and save usecases (`lib/features/capture/domain/usecases/`) — RF02 changes

RF01's `SaveTextEntryUseCase` is untouched (Texto has no recognition step, FR-012). This document covers the
two usecases this unit adds/replaces; data-model.md has their full bodies.

## `RecognizePhotoUseCase` (NEW)

```dart
class RecognizePhotoUseCase {
  const RecognizePhotoUseCase({
    required PhotoRecognitionRepository recognitionRepository,
    required ConnectivityChecker connectivityChecker,
  });

  Future<Either<PhotoRecognitionAttemptFailure, OcrResult>> call(String imageFilePath);
}

sealed class PhotoRecognitionAttemptFailure {}
class PhotoRecognitionOffline extends PhotoRecognitionAttemptFailure {}
class PhotoRecognitionCallFailed extends PhotoRecognitionAttemptFailure {
  const PhotoRecognitionCallFailed(this.failure);
  final Failure failure;
}
```

- **Preconditions**: none — callable any number of times against the same `imageFilePath` (used by both the
  initial automatic call on image selection and every "Tentar novamente").
- **Behavior**: checks `ConnectivityChecker.hasConnection()` first; `false` short-circuits to
  `Left(PhotoRecognitionOffline())` without calling `PhotoRecognitionRepository.recognize()` at all (same
  "don't even attempt a call that cannot succeed" principle RF01's research.md R5 established, now scoped to
  this one call instead of the old combined flow). Otherwise delegates to
  `PhotoRecognitionRepository.recognize(imageFilePath)` unchanged and wraps its `Left`/`Right` in
  `PhotoRecognitionCallFailed`/`Right` respectively.
- **Does not** call `CreateEntryUseCase` or touch `EntriesRepository` in any way — purely the recognition
  half, by design (this is exactly what used to be fused with entry creation in RF01's `SavePhotoEntryUseCase`
  and is now split apart).
- **Who calls it**: `InsertionModalBloc`, on `PhotoSourceSelected` (first attempt) and `RetryRequested` (every
  subsequent attempt against the same held path) — contracts/insertion-modal-bloc.md.

## `ConfirmEntrySaveUseCase` (NEW, replaces `SaveAudioEntryUseCase` + `SavePhotoEntryUseCase`)

```dart
class ConfirmEntrySaveUseCase {
  const ConfirmEntrySaveUseCase({
    required CreateEntryUseCase createEntryUseCase,
    required ConnectivityChecker connectivityChecker,
  });

  Future<Either<ConfirmEntrySaveFailure, Entry>> call(String content, EntrySource source);
}

sealed class ConfirmEntrySaveFailure {}
class ConfirmEntrySaveOffline extends ConfirmEntrySaveFailure {}
class ConfirmEntrySaveCreationFailed extends ConfirmEntrySaveFailure {
  const ConfirmEntrySaveCreationFailed(this.failure);
  final Failure failure;
}
```

- **Preconditions**: `content` is expected non-empty/non-whitespace — enforced by the bloc before calling this
  (the "Salvar"/"Salvar só a foto" trigger is itself gated on that, FR-009), not re-validated here (this
  usecase trusts its caller, the same contract `CreateEntryUseCase` itself already has).
- **Behavior**: checks `ConnectivityChecker.hasConnection()` first; `false` short-circuits to
  `Left(ConfirmEntrySaveOffline())` without calling `CreateEntryUseCase` (FR-010/the Edge Cases' "both still
  require connectivity" wording). Otherwise delegates to `CreateEntryUseCase(content, source)` and wraps its
  result.
- **Who calls it**: `InsertionModalBloc`, on `AudioSaveConfirmed`, `PhotoSaveConfirmed`, and
  `PhotoSaveWithoutTextRequested` — the one shared seam for every entry this unit creates, parameterized only
  by `content` and `source` (research.md R7's consolidation rationale).
- **Deleted**: `lib/features/capture/domain/usecases/save_audio_entry_usecase.dart` and
  `save_photo_entry_usecase.dart` (and their `SaveAudioFailure`/`SavePhotoFailure` sealed types), along with
  their test files — fully superseded, no remaining caller.

## `AudioTranscriptionRepository` / `PhotoRecognitionRepository` (unchanged interfaces, new call sites)

Both interfaces (`specs/003-multimodal-capture/contracts/*.md`) keep their exact signatures —
`transcribe(String) -> Either<RecognitionFailure, String>` and
`recognize(String) -> Either<Failure, OcrResult>`. This unit changes only *who* calls them and *when*:
`AudioTranscriptionRepository.transcribe()` is now called directly by `InsertionModalBloc` (no usecase — R1
removes the one orchestration step, the connectivity check, that used to justify a wrapper);
`PhotoRecognitionRepository.recognize()` is now called only from inside `RecognizePhotoUseCase`, never
directly by the bloc.

## RNF07 coverage this unit's tests must provide

| Unit | Scenarios |
|---|---|
| `RecognizePhotoUseCase` | offline short-circuit (no repository call); repository `Right`; repository `Left(OcrNoTextFailure)`; repository `Left(<other Failure>)` — against a mock `PhotoRecognitionRepository` + fake `ConnectivityChecker`. |
| `ConfirmEntrySaveUseCase` | offline short-circuit (no `CreateEntryUseCase` call); `CreateEntryUseCase` `Right`; `CreateEntryUseCase` `Left` — against a mock `CreateEntryUseCase` + fake `ConnectivityChecker`. |
| `InsertionModalBloc` (bloc_test) | Áudio: stop → Processing → Transcribed (success) / Failure (empty/error); edited text carried into the create-entry call; Salvar double-tap ignored while Saving; stale-result guard (switch tabs mid-Processing, confirm the late result is dropped); retry re-uses the same path. Foto: the same shape, plus the offline-before-OCR path and "Salvar só a foto" creating an entry with the fixed placeholder and *no* further `recognize()` call. |
