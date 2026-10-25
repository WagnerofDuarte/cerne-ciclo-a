import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/settings/data/dashboard_remote_data_source.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_narrative.dart';
import 'package:cerne/features/settings/domain/repositories/dashboard_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps [DashboardRemoteDataSource] + [SessionRepository] (for the
/// silent-refresh retry) — same shape as `EntriesRepositoryImpl`
/// (contracts/dashboard-repository.md).
class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl(this._remoteDataSource, {required this._sessionRepository});

  final DashboardRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;

  @override
  Future<Either<Failure, DashboardAggregate>> fetchAggregate() =>
      _retryAfterSilentRefreshIfExpired(_remoteDataSource.fetchAggregate);

  @override
  Future<Either<Failure, DashboardNarrative>> fetchNarrative() =>
      _retryAfterSilentRefreshIfExpired(_remoteDataSource.fetchNarrative);

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
