import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:whisper_ggml/whisper_ggml.dart';

/// Thrown when `whisper_ggml` fails to produce a transcription (internal
/// error or model-load failure) — mapped to `TranscriptionError` by
/// `AudioTranscriptionRepositoryImpl`.
class WhisperTranscriptionFailedException implements Exception {
  const WhisperTranscriptionFailedException();
}

/// The only class importing `whisper_ggml`'s `WhisperController`/
/// `WhisperModel` types (contracts/audio-capture-repository.md). Owns the
/// one-time "copy the bundled model asset to a writable app-support
/// directory" step (research.md R2); subsequent calls reuse the copied
/// file.
class WhisperTranscriptionDataSource {
  WhisperTranscriptionDataSource({WhisperController? controller})
    : _controller = controller ?? WhisperController();

  final WhisperController _controller;
  bool _modelCopied = false;

  Future<String> transcribe(String audioFilePath) async {
    await _ensureModelCopied();
    final result = await _controller.transcribe(
      model: WhisperModel.tiny,
      audioPath: audioFilePath,
      lang: 'pt',
    );
    if (result == null) {
      throw const WhisperTranscriptionFailedException();
    }
    return result.transcription.text;
  }

  Future<void> _ensureModelCopied() async {
    if (_modelCopied) return;

    final dir = await WhisperController.getModelDir();
    final destination = File('$dir/ggml-${WhisperModel.tiny.modelName}.bin');
    if (!destination.existsSync()) {
      final asset = await rootBundle.load('assets/models/ggml-tiny-q5_1.bin');
      await destination.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
    }
    _modelCopied = true;
  }
}
