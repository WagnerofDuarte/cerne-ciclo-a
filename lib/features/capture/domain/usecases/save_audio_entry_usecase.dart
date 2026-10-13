import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_transcription_repository.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';

/// Distinguishes "offline" / "recognition failed (no corresponding
/// `Failure`, research.md R7)" / "entry creation itself failed" so
/// `InsertionModalBloc` can show the right message for each
/// (contracts/save-usecases.md) — never for a styling branch (research.md
/// R11: all three render through the same plain failure-and-retry UI).
sealed class SaveAudioFailure {
  const SaveAudioFailure();
}

class SaveAudioOffline extends SaveAudioFailure {
  const SaveAudioOffline();
}

class SaveAudioRecognitionFailed extends SaveAudioFailure {
  const SaveAudioRecognitionFailed(this.recognitionFailure);

  final RecognitionFailure recognitionFailure;
}

class SaveAudioEntryCreationFailed extends SaveAudioFailure {
  const SaveAudioEntryCreationFailed(this.failure);

  final Failure failure;
}

/// The one thing `InsertionModalBloc` calls for the Áudio tab's Save
/// trigger (contracts/save-usecases.md).
class SaveAudioEntryUseCase {
  const SaveAudioEntryUseCase({
    required this._transcriptionRepository,
    required this._createEntryUseCase,
    required this._connectivityChecker,
  });

  final AudioTranscriptionRepository _transcriptionRepository;
  final CreateEntryUseCase _createEntryUseCase;
  final ConnectivityChecker _connectivityChecker;

  Future<Either<SaveAudioFailure, Entry>> call(String audioFilePath) async {
    if (!await _connectivityChecker.hasConnection()) {
      return const Left(SaveAudioOffline());
    }

    final transcribed = await _transcriptionRepository.transcribe(
      audioFilePath,
    );
    if (transcribed.isLeft()) {
      final recognitionFailure = transcribed.getLeft().toNullable()!;
      return Left(SaveAudioRecognitionFailed(recognitionFailure));
    }

    final text = transcribed.getRight().toNullable()!;
    final created = await _createEntryUseCase(text, EntrySource.audio);
    return created.match(
      (failure) => Left(SaveAudioEntryCreationFailed(failure)),
      (entry) => Right(entry),
    );
  }
}
