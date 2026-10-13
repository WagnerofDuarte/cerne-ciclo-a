/// Wraps device audio I/O only — no network, no recognition
/// (contracts/audio-capture-repository.md). `AudioCaptureRepositoryImpl`
/// maps everything to plain `bool`/`String`/`Stream<double>` before it
/// reaches this boundary (RNF06).
abstract class AudioCaptureRepository {
  /// The OS mic-permission request (research.md R1).
  Future<bool> hasPermission();

  /// Begins recording to a fresh 16 kHz mono WAV temp file.
  Future<void> start();

  /// Forwarded from the recorder's own amplitude signal — read directly by
  /// the waveform widget via `get_it`, NOT routed through
  /// `InsertionModalBloc`'s event stream (too high-frequency to belong in
  /// bloc event history).
  Stream<double> get amplitudeStream;

  /// Stops; returns the finished WAV file's path.
  Future<String> stop();

  /// Stops (if active) and deletes the temp file — nothing from an
  /// abandoned capture ever reaches `CreateEntryUseCase` (FR-008).
  void discard();
}
