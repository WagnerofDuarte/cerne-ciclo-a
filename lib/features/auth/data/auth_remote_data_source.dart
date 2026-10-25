import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';

/// Calls `auth-signup`/`auth-login` and parses the `session`/`user` objects
/// into [Session]/[Account] (contracts/http-client.md, openapi.yaml).
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, Session>> signUp({
    required String email,
    required String password,
  }) {
    return _submit('auth-signup', email: email, password: password);
  }

  Future<Either<Failure, Session>> login({
    required String email,
    required String password,
  }) {
    return _submit('auth-login', email: email, password: password);
  }

  /// `POST /auth/logout` (`auth-logout`), empty body. Returns `Right(unit)`
  /// on any 200 regardless of the response's `ok` value
  /// (contracts/account-session-actions.md).
  Future<Either<Failure, Unit>> logout() async {
    final result = await _apiClient.call('auth-logout', method: 'POST');
    return result.map((_) => unit);
  }

  Future<Either<Failure, Session>> _submit(
    String function, {
    required String email,
    required String password,
  }) async {
    final result = await _apiClient.call(
      function,
      method: 'POST',
      body: {'email': email, 'password': password},
      authMode: AuthMode.anonKey,
    );

    return result.flatMap(_parseSession);
  }

  Either<Failure, Session> _parseSession(Map<String, dynamic> data) {
    try {
      final sessionJson = data['session'] as Map<String, dynamic>?;
      final userJson = data['user'] as Map<String, dynamic>?;

      if (sessionJson == null || userJson == null) {
        return const Left(
          ValidationFailure(message: 'Malformed auth response', requestId: ''),
        );
      }

      final account = Account(
        id: userJson['id'] as String,
        email: userJson['email'] as String,
      );

      final session = Session(
        accessToken: sessionJson['accessToken'] as String,
        refreshToken: sessionJson['refreshToken'] as String,
        expiresAt: sessionJson['expiresAt'] as int,
        tokenType: sessionJson['tokenType'] as String,
        account: account,
      );

      return Right(session);
    } on TypeError {
      // A field was the wrong type — treat as a malformed response, never a
      // thrown exception past this boundary (FR-003).
      return const Left(
        ValidationFailure(message: 'Malformed auth response', requestId: ''),
      );
    }
  }
}
