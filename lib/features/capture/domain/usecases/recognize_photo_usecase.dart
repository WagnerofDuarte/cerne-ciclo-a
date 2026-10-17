import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Distinguishes "never called `media-ocr`" (offline) from "the call itself
/// failed" (data-model.md) — the recognition half of what used to be fused
/// with entry creation in `SavePhotoEntryUseCase` (research.md).
sealed class PhotoRecognitionAttemptFailure {
  const PhotoRecognitionAttemptFailure();
}

class PhotoRecognitionOffline extends PhotoRecognitionAttemptFailure {
  const PhotoRecognitionOffline();
}

class PhotoRecognitionCallFailed extends PhotoRecognitionAttemptFailure {
  const PhotoRecognitionCallFailed(this.failure);

  final Failure failure;
}

/// Callable any number of times against the same `imageFilePath` — used by
/// both the initial automatic call on image selection and every "Tentar
/// novamente" (contracts/recognition-and-save-usecases.md). Does not call
/// `CreateEntryUseCase` or touch `EntriesRepository` in any way.
class RecognizePhotoUseCase {
  const RecognizePhotoUseCase({
    required this._recognitionRepository,
    required this._connectivityChecker,
  });

  final PhotoRecognitionRepository _recognitionRepository;
  final ConnectivityChecker _connectivityChecker;

  Future<Either<PhotoRecognitionAttemptFailure, OcrResult>> call(
    String imageFilePath,
  ) async {
    if (!await _connectivityChecker.hasConnection()) {
      return const Left(PhotoRecognitionOffline());
    }

    final result = await _recognitionRepository.recognize(imageFilePath);
    return result.match(
      (failure) => Left(PhotoRecognitionCallFailed(failure)),
      (ocrResult) => Right(ocrResult),
    );
  }
}
