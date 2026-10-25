import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// `DELETE /account`, always sending `{"confirmation": "DELETE"}` supplied
/// internally (FR-018) — no caller-supplied parameter for it. No
/// retry-on-`AuthExpiredFailure` (contracts/account-deletion-repository.md):
/// an expired session here surfaces as a plain failure and fires
/// `reauthRequired`, letting the existing overlay take over rather than
/// silently re-sending a destructive request.
abstract class AccountDeletionRepository {
  Future<Either<Failure, Unit>> deleteAccount();
}
