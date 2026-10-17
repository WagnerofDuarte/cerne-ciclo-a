import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';

/// Distinguishes "offline" from "the `entries-create` call itself failed"
/// (data-model.md) — the one seam every explicit "Salvar"/"Salvar só a
/// foto" trigger across Áudio and Foto funnels through (research.md R7).
sealed class ConfirmEntrySaveFailure {
  const ConfirmEntrySaveFailure();
}

class ConfirmEntrySaveOffline extends ConfirmEntrySaveFailure {
  const ConfirmEntrySaveOffline();
}

class ConfirmEntrySaveCreationFailed extends ConfirmEntrySaveFailure {
  const ConfirmEntrySaveCreationFailed(this.failure);

  final Failure failure;
}

/// Replaces `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` now that
/// recognition is a separate step for both modalities (data-model.md,
/// contracts/recognition-and-save-usecases.md). Does not re-validate
/// `content` non-emptiness — that is the bloc's job before calling this
/// (FR-009), the same contract `CreateEntryUseCase` itself already has.
class ConfirmEntrySaveUseCase {
  const ConfirmEntrySaveUseCase({
    required this._createEntryUseCase,
    required this._connectivityChecker,
  });

  final CreateEntryUseCase _createEntryUseCase;
  final ConnectivityChecker _connectivityChecker;

  Future<Either<ConfirmEntrySaveFailure, Entry>> call(
    String content,
    EntrySource source,
  ) async {
    if (!await _connectivityChecker.hasConnection()) {
      return const Left(ConfirmEntrySaveOffline());
    }

    final created = await _createEntryUseCase(content, source);
    return created.match(
      (failure) => Left(ConfirmEntrySaveCreationFailed(failure)),
      (entry) => Right(entry),
    );
  }
}
