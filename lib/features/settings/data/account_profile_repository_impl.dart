import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/settings/data/account_profile_local_cache.dart';
import 'package:cerne/features/settings/data/account_settings_remote_data_source.dart';
import 'package:cerne/features/settings/domain/repositories/account_profile_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps [AccountSettingsRemoteDataSource] + [AccountProfileLocalCache] +
/// [SessionRepository] (for the silent-refresh retry) — same shape as
/// `EntriesRepositoryImpl` (contracts/account-profile-repository.md).
class AccountProfileRepositoryImpl implements AccountProfileRepository {
  AccountProfileRepositoryImpl(
    this._remoteDataSource, {
    required this._sessionRepository,
    required this._localCache,
  });

  final AccountSettingsRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;
  final AccountProfileLocalCache _localCache;

  @override
  Future<String?> readCachedDisplayName() => _localCache.read();

  @override
  Future<Either<Failure, String>> updateDisplayName(String name) async {
    final result = await _retryAfterSilentRefreshIfExpired(
      () => _remoteDataSource.updateDisplayName(name),
    );
    return result.match(
      (failure) => Future.value(Left(failure)),
      // Defensive against the backend ever normalizing the value (e.g.
      // trimming) — the response's own confirmed name is what gets
      // cached, never the caller's input string verbatim.
      (confirmedName) async {
        await _localCache.write(confirmedName);
        return Right(confirmedName);
      },
    );
  }

  @override
  Future<void> clearCachedDisplayName() => _localCache.clear();

  // Exactly one retry. If it also comes back `AuthExpiredFailure` (a
  // pathological double-expiry), that is returned as-is — no second refresh
  // attempt, no loop (same shape EntriesRepositoryImpl already uses).
  Future<Either<Failure, T>> _retryAfterSilentRefreshIfExpired<T>(
    Future<Either<Failure, T>> Function() call,
  ) async {
    final result = await call();
    return result.match(
      (f) => f is AuthExpiredFailure
          ? _retryAfterSilentRefresh(call)
          : Future.value(Left(f)),
      (v) => Future.value(Right(v)),
    );
  }

  Future<Either<Failure, T>> _retryAfterSilentRefresh<T>(
    Future<Either<Failure, T>> Function() retry,
  ) async {
    final refreshed = await _sessionRepository.refresh();
    return refreshed.match(
      (_) => Future.value(
        const Left(
          AuthExpiredFailure(message: 'Session could not be renewed', requestId: ''),
        ),
      ),
      (_) => retry(),
    );
  }
}
