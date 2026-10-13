import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';

/// Same shape as `SaveAudioFailure` (contracts/save-usecases.md).
sealed class SavePhotoFailure {
  const SavePhotoFailure();
}

class SavePhotoOffline extends SavePhotoFailure {
  const SavePhotoOffline();
}

class SavePhotoRecognitionFailed extends SavePhotoFailure {
  const SavePhotoRecognitionFailed(this.failure);

  final Failure failure;
}

class SavePhotoEntryCreationFailed extends SavePhotoFailure {
  const SavePhotoEntryCreationFailed(this.failure);

  final Failure failure;
}

/// The one thing `InsertionModalBloc` calls for the Foto tab's Save
/// trigger — substitutes `PhotoRecognitionRepository.recognize` for the
/// transcription call, ignoring `OcrResult.confidence` entirely regardless
/// of value (Clarification 3).
class SavePhotoEntryUseCase {
  const SavePhotoEntryUseCase({
    required this._recognitionRepository,
    required this._createEntryUseCase,
    required this._connectivityChecker,
  });

  final PhotoRecognitionRepository _recognitionRepository;
  final CreateEntryUseCase _createEntryUseCase;
  final ConnectivityChecker _connectivityChecker;

  Future<Either<SavePhotoFailure, Entry>> call(String imageFilePath) async {
    if (!await _connectivityChecker.hasConnection()) {
      return const Left(SavePhotoOffline());
    }

    final recognized = await _recognitionRepository.recognize(imageFilePath);
    if (recognized.isLeft()) {
      final failure = recognized.getLeft().toNullable()!;
      return Left(SavePhotoRecognitionFailed(failure));
    }

    final ocrResult = recognized.getRight().toNullable()!;
    final created = await _createEntryUseCase(ocrResult.text, EntrySource.photo);
    return created.match(
      (failure) => Left(SavePhotoEntryCreationFailed(failure)),
      (entry) => Right(entry),
    );
  }
}
