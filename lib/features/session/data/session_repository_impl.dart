import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/data/session_remote_data_source.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';

class SessionRepositoryImpl implements SessionRepository {
  const SessionRepositoryImpl({
    required this._remoteDataSource,
    required this._tokenStorage,
  });

  final SessionRemoteDataSource _remoteDataSource;
  final SecureTokenStorage _tokenStorage;

  @override
  Future<Either<Failure, Session>> checkSession() async {
    final result = await _remoteDataSource.checkSession();
    return result.match<Future<Either<Failure, Session>>>(
      (failure) => Future.value(Left(failure)),
      _assembleFromCheckSession,
    );
  }

  @override
  Future<Either<Failure, Session>> refresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      return const Left(
        AuthInvalidFailure(message: 'No refresh token stored', requestId: ''),
      );
    }

    final result = await _remoteDataSource.refresh(refreshToken: refreshToken);
    return result.match<Future<Either<Failure, Session>>>(
      (failure) => Future.value(Left(failure)),
      _assembleFromRefresh,
    );
  }

  @override
  Future<void> persist(Session session) {
    return _tokenStorage.writeSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresAt: session.expiresAt,
      tokenType: session.tokenType,
    );
  }

  @override
  Future<void> clear() => _tokenStorage.delete();

  @override
  Future<bool> hasStoredSession() async {
    return (await _tokenStorage.readRefreshToken()) != null;
  }

  Future<Either<Failure, Session>> _assembleFromCheckSession(
    Map<String, dynamic> data,
  ) async {
    try {
      final userJson = data['user'] as Map<String, dynamic>;
      final expiresAt = data['expiresAt'] as int;

      final accessToken = await _tokenStorage.readAccessToken();
      final refreshToken = await _tokenStorage.readRefreshToken();
      final tokenType = await _tokenStorage.readTokenType();
      if (accessToken == null || refreshToken == null || tokenType == null) {
        return const Left(
          ValidationFailure(message: 'No stored session', requestId: ''),
        );
      }

      return Right(
        Session(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: expiresAt,
          tokenType: tokenType,
          account: Account(
            id: userJson['id'] as String,
            email: userJson['email'] as String,
          ),
        ),
      );
    } on TypeError {
      return const Left(
        ValidationFailure(message: 'Malformed session response', requestId: ''),
      );
    }
  }

  // auth-refresh's response carries only new tokens, never a `user` object
  // (openapi.yaml) — unlike auth-signup/auth-login. The new tokens are
  // persisted first, then auth-session is called again (now authenticated
  // with the fresh accessToken) to recover the Account, so refresh() still
  // returns a fully-populated Session. Reasonable choice where the contract
  // is silent on how a refresh alone would otherwise learn the account.
  Future<Either<Failure, Session>> _assembleFromRefresh(
    Map<String, dynamic> data,
  ) async {
    try {
      final sessionJson = data['session'] as Map<String, dynamic>;
      await _tokenStorage.writeSession(
        accessToken: sessionJson['accessToken'] as String,
        refreshToken: sessionJson['refreshToken'] as String,
        expiresAt: sessionJson['expiresAt'] as int,
        tokenType: sessionJson['tokenType'] as String,
      );

      return await checkSession();
    } on TypeError {
      return const Left(
        ValidationFailure(message: 'Malformed refresh response', requestId: ''),
      );
    }
  }
}
