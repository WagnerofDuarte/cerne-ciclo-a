import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// The only class importing `record`'s `AudioRecorder`/`RecordConfig`/
/// `AudioEncoder` types (contracts/audio-capture-repository.md).
class AudioRecorderDataSource {
  AudioRecorderDataSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  static const _config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Records to a fresh 16 kHz mono WAV temp file (research.md R1) — the
  /// exact format `whisper_ggml` needs, no conversion step.
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/capture_audio_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(_config, path: path);
  }

  Stream<double> onAmplitudeChanged(Duration interval) =>
      _recorder.onAmplitudeChanged(interval).map((amplitude) => amplitude.current);

  Future<String?> stop() => _recorder.stop();

  Future<void> cancel() => _recorder.cancel();
}
