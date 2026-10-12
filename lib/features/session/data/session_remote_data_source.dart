import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// Calls `auth-session`/`auth-refresh` and returns the raw `data` object —
/// parsing into [Session] happens in [SessionRepositoryImpl], which alone
/// has the stored-token context needed to complete it (contracts/http-client.md).
class SessionRemoteDataSource {
  const SessionRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, Map<String, dynamic>>> checkSession() {
    return _apiClient.call(
      'auth-session',
      method: 'GET',
      authMode: AuthMode.userSession,
    );
  }

  Future<Either<Failure, Map<String, dynamic>>> refresh({
    required String refreshToken,
  }) {
    return _apiClient.call(
      'auth-refresh',
      method: 'POST',
      body: {'refreshToken': refreshToken},
      authMode: AuthMode.anonKey,
    );
  }
}
