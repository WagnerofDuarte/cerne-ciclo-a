# Contract: Audio capture & transcription (`lib/features/capture/domain/`)

Two separate domain interfaces, deliberately not merged (research.md R1/R7): one wraps the
`record` plugin (device I/O, no network, no recognition), the other wraps on-device `whisper_ggml`
(recognition, still no network). Neither crosses into `presentation/` directly — `InsertionModalBloc`
only ever calls these through `capture/domain/usecases/save_audio_entry_usecase.dart`, except for
the live amplitude stream (below).

```dart
// lib/features/capture/domain/repositories/audio_capture_repository.dart
abstract class AudioCaptureRepository {
  Future<bool> hasPermission();           // `record`'s own OS mic-permission request (research.md R1)
  Future<void> start();                   // begins recording to a fresh 16 kHz mono WAV temp file
  Stream<double> get amplitudeStream;      // forwarded from `record`'s onAmplitudeChanged — read directly
                                           // by the waveform widget via get_it, NOT routed through
                                           // InsertionModalBloc's event stream (too high-frequency to
                                           // belong in bloc event history)
  Future<String> stop();                   // stops; returns the finished WAV file's path
  void discard();                          // stops (if active) and deletes the temp file, no path returned
}

// lib/features/capture/domain/repositories/audio_transcription_repository.dart
sealed class RecognitionFailure {}
class EmptyRecognitionResult extends RecognitionFailure {}     // transcript was empty/whitespace-only
class TranscriptionError extends RecognitionFailure {}         // whisper_ggml threw / model failed to load

abstract class AudioTranscriptionRepository {
  Future<Either<RecognitionFailure, String>> transcribe(String audioFilePath);
}
```

- **`AudioRecorderDataSource`** (`lib/features/capture/data/audio_recorder_data_source.dart`) is
  the only class importing `record`'s `AudioRecorder`/`RecordConfig`/`AudioEncoder` types —
  `AudioCaptureRepositoryImpl` maps everything to plain `bool`/`String`/`Stream<double>` before it
  reaches `domain/` (RNF06, mirrors RF03's `LocalAuthBiometricDataSource` boundary).
- **`WhisperTranscriptionDataSource`** (`lib/features/capture/data/whisper_transcription_data_source.dart`)
  is the only class importing `whisper_ggml`'s `WhisperController`/`WhisperModel` types. It owns the
  one-time "copy the bundled model asset to a writable path" step (research.md R2) the first time
  `transcribe()` is called; subsequent calls reuse the already-copied file.
- **`transcribe()`'s empty-result rule**: a transcript that is empty or whitespace-only after
  `.trim()` is reported as `Left(EmptyRecognitionResult())`, not `Right('')` — this is what makes
  the silence Edge Case ("Save fails with a clear message rather than creating an empty or
  near-empty entry") true without `SaveAudioEntryUseCase` needing its own blank-check duplicated
  across audio and photo (photo's equivalent check lives in `PhotoRecognitionRepository`/the
  backend's own `OCR_NO_TEXT` code instead — see photo-capture-repository.md).
- **Why `discard()` has no return value**: callers that need `stop()`'s path (to transcribe it)
  always call `stop()`; callers that abandon a capture (modal closed, tab switched away mid-
  recording — Edge Cases) always call `discard()` and never look at a path, since FR-008 requires
  that nothing from an abandoned capture ever reaches `CreateEntryUseCase`.
- **Who depends on this**: `SaveAudioEntryUseCase` (both repositories), `InsertionModalBloc`
  (`start`/`stop`/`discard`/`hasPermission`, to drive its own sub-states), the waveform widget
  (`amplitudeStream` only, read via `get_it` directly — the one sanctioned exception to "always
  through the bloc" for this unit, justified above).
