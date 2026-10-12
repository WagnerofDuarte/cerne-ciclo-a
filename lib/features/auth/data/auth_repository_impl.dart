import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/data/auth_remote_data_source.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';

/// On `Right`, persists the session via [SecureTokenStorage] before
/// returning — sign-up and login leave the app in an identical
/// post-condition (contracts/auth-repository.md).
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required this._remoteDataSource,
    required this._tokenStorage,
  });

  final AuthRemoteDataSource _remoteDataSource;
  final SecureTokenStorage _tokenStorage;

  @override
  Future<Either<Failure, Session>> signUp({
    required String email,
    required String password,
  }) async {
    final result = await _remoteDataSource.signUp(
      email: email,
      password: password,
    );
    return _persistOnSuccess(result);
  }

  @override
  Future<Either<Failure, Session>> login({
    required String email,
    required String password,
  }) async {
    final result = await _remoteDataSource.login(
      email: email,
      password: password,
    );
    return _persistOnSuccess(result);
  }

  Future<Either<Failure, Session>> _persistOnSuccess(
    Either<Failure, Session> result,
  ) async {
    final session = result.toNullable();
    if (session != null) {
      await _tokenStorage.writeSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
        tokenType: session.tokenType,
      );
    }
    return result;
  }
}
