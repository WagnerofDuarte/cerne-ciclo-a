import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// Calls `account-delete` (`DELETE /account`), always sending
/// `{"confirmation": "DELETE"}` supplied internally (FR-018) — no caller
/// parameter for it.
class AccountDeletionRemoteDataSource {
  const AccountDeletionRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, Map<String, dynamic>>> deleteAccount() => _apiClient.call(
    'account-delete',
    method: 'DELETE',
    body: const {'confirmation': 'DELETE'},
  );
}
