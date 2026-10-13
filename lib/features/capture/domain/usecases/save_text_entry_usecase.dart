import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';

/// (contracts/save-usecases.md) The one thing `InsertionModalBloc` calls for
/// the Texto tab's Save trigger.
class SaveTextEntryUseCase {
  const SaveTextEntryUseCase({
    required this._createEntryUseCase,
    required this._connectivityChecker,
  });

  final CreateEntryUseCase _createEntryUseCase;
  final ConnectivityChecker _connectivityChecker;

  static const offlineMessage =
      'Sem conexão. Conecte-se à internet para salvar.';

  Future<Either<Failure, Entry>> call(String text) async {
    if (!await _connectivityChecker.hasConnection()) {
      return const Left(
        NetworkOfflineFailure(message: offlineMessage, requestId: ''),
      );
    }
    return _createEntryUseCase(text, EntrySource.manual);
  }
}
