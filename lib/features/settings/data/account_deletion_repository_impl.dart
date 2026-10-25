import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/settings/data/account_deletion_remote_data_source.dart';
import 'package:cerne/features/settings/domain/repositories/account_deletion_repository.dart';
import 'package:fpdart/fpdart.dart';

/// No retry-on-`AuthExpiredFailure` here (contracts/account-deletion-repository.md)
/// — an expired session during the delete-confirmation dialog surfaces as a
/// plain failure and fires `reauthRequired`, letting the existing overlay
/// take over rather than silently re-sending a destructive request.
class AccountDeletionRepositoryImpl implements AccountDeletionRepository {
  const AccountDeletionRepositoryImpl(this._remoteDataSource);

  final AccountDeletionRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, Unit>> deleteAccount() async {
    final result = await _remoteDataSource.deleteAccount();
    return result.flatMap(_validateOk);
  }

  Either<Failure, Unit> _validateOk(Map<String, dynamic> data) {
    if (data['ok'] == true) return const Right(unit);
    // A 200 with `data.ok` missing or not `true` — never reports success
    // on an ambiguous response.
    return const Left(
      ValidationFailure(message: 'Malformed account deletion response', requestId: ''),
    );
  }
}
