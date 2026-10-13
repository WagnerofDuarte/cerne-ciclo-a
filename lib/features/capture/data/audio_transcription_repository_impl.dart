import 'package:cerne/features/capture/data/whisper_transcription_data_source.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_transcription_repository.dart';
import 'package:fpdart/fpdart.dart';

class AudioTranscriptionRepositoryImpl implements AudioTranscriptionRepository {
  const AudioTranscriptionRepositoryImpl(this._dataSource);

  final WhisperTranscriptionDataSource _dataSource;

  @override
  Future<Either<RecognitionFailure, String>> transcribe(
    String audioFilePath,
  ) async {
    try {
      final text = await _dataSource.transcribe(audioFilePath);
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        return const Left(EmptyRecognitionResult());
      }
      return Right(trimmed);
    } catch (_) {
      return const Left(TranscriptionError());
    }
  }
}
