# Contract: Save orchestration (`lib/features/capture/domain/usecases/`) + `ConnectivityChecker`

The three usecases that tie `entries/` (contracts/entries-repository.md) together with `capture/`'s
own audio/photo repositories (contracts/audio-capture-repository.md,
contracts/photo-capture-repository.md) and the new offline gate (research.md R5). Each is the one
thing `InsertionModalBloc` calls per modality's Save trigger (research.md R6) — the bloc itself
never calls `CreateEntryUseCase`, `AudioTranscriptionRepository`, or `PhotoRecognitionRepository`
directly.

```dart
// lib/core/network/connectivity_checker.dart (core, not capture-specific — research.md R5)
class ConnectivityChecker {
  Future<bool> hasConnection() async =>
      (await Connectivity().checkConnectivity()) != ConnectivityResult.none;
}

// lib/features/capture/domain/usecases/save_text_entry_usecase.dart
class SaveTextEntryUseCase {
  Future<Either<Failure, Entry>> call(String text) async {
    if (!await _connectivity.hasConnection()) {
      return Left(NetworkOfflineFailure(message: _offlineMessage, requestId: ''));
    }
    return _createEntry(text, EntrySource.manual);
  }
}

// lib/features/capture/domain/usecases/save_audio_entry_usecase.dart
class SaveAudioEntryUseCase {
  Future<Either<SaveAudioFailure, Entry>> call(String audioFilePath) async {
    if (!await _connectivity.hasConnection()) {
      return Left(SaveAudioFailure.offline);                      // checked BEFORE transcribing — research.md R5
    }
    final transcribed = await _transcriptionRepository.transcribe(audioFilePath);
    return transcribed.match(
      (recognitionFailure) => Left(SaveAudioFailure.recognition),
      (text) async => (await _createEntry(text, EntrySource.audio))
          .match(
            (failure) => Left(SaveAudioFailure.entryCreation(failure)),
            (entry) => Right(entry),
          ),
    );
  }
}

// lib/features/capture/domain/usecases/save_photo_entry_usecase.dart — same shape as audio,
// substituting PhotoRecognitionRepository.recognize(imageFilePath) for the transcription call,
// and its own SavePhotoFailure (offline | recognition | entryCreation(Failure)).
```

- **Why `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` don't just return `Either<Failure, Entry>`
  like the text path**: their failure side needs to distinguish "offline" / "recognition failed
  (no corresponding `Failure`, research.md R7)" / "entry creation itself failed (a real
  `Failure`)" so `InsertionModalBloc` can show the right generic message for each — but all three
  render through the *same* plain failure-and-retry UI (research.md R11), so this distinction is
  for message selection only, never for a styling branch.
- **Single offline check per Save attempt**: `ConnectivityChecker.hasConnection()` is called once,
  at the start of each usecase, not re-checked between transcription/recognition and entry
  creation — a device that goes offline in the few seconds between those two steps surfaces as a
  normal `NetworkOfflineFailure` from the `entries-create` call itself (the existing reactive path),
  not a second proactive check.
- **Idempotency against double-tap (Assumptions)**: enforced in `InsertionModalBloc`, not here —
  the bloc simply ignores `SaveTextSubmitted`/`AudioStopRequested` (second tap)/
  `PhotoSourceSelected` while already in a `*Saving` state, so each usecase here is only ever
  invoked once per confirmed capture regardless of UI mashing.
- **Who depends on this**: `InsertionModalBloc` only. Registered as `get_it` factories (same
  per-dependency-graph pattern as every other usecase in this codebase), constructed from
  `CreateEntryUseCase`, the relevant `capture` repositories, and the shared `ConnectivityChecker`.
