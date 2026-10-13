import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:fpdart/fpdart.dart';

/// On-device only (research.md R2) — deliberately returns
/// `Either<RecognitionFailure, String>`, not `Either<Failure, String>`,
/// because there is no network call and no corresponding backend code
/// (research.md R7).
abstract class AudioTranscriptionRepository {
  /// A transcript that is empty or whitespace-only after `.trim()` is
  /// reported as `Left(EmptyRecognitionResult())`, never `Right('')`
  /// (contracts/audio-capture-repository.md).
  Future<Either<RecognitionFailure, String>> transcribe(String audioFilePath);
}
