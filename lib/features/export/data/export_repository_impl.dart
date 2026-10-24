import 'dart:typed_data';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/data/export_remote_data_source.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';

/// No local cache — `export_jobs`/their downloaded files are explicitly
/// ephemeral (Key Entities: "never shown anywhere outside the export
/// sheet"), unlike `EntriesRepositoryImpl`/`ChatRepositoryImpl`.
class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl(this._remoteDataSource, {required this._sessionRepository});

  final ExportRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;

  @override
  Future<Either<Failure, String>> create({
    required DateTime? periodStart,
    required DateTime? periodEnd,
  }) async {
    Future<Either<Failure, String>> fetch() =>
        _remoteDataSource.create(periodStart: periodStart, periodEnd: periodEnd);
    final result = await fetch();
    return result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(fetch)
          : Future.value(Left(failure)),
      (jobId) => Future.value(Right(jobId)),
    );
  }

  @override
  Future<Either<Failure, ExportJob>> status(String jobId) async {
    Future<Either<Failure, ExportJob>> fetch() => _remoteDataSource.status(jobId);
    final result = await fetch();
    return result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(fetch)
          : Future.value(Left(failure)),
      (job) => Future.value(Right(job)),
    );
  }

  @override
  Future<Either<Failure, Uint8List>> download({
    required String jobId,
    required ExportFormat format,
  }) async {
    Future<Either<Failure, Uint8List>> fetch() =>
        _remoteDataSource.download(jobId: jobId, format: format);
    final result = await fetch();
    return result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(fetch)
          : Future.value(Left(failure)),
      (bytes) => Future.value(Right(bytes)),
    );
  }

  // Exactly one retry. If it also comes back AuthExpiredFailure (a
  // pathological double-expiry), that is returned as-is — no second refresh
  // attempt, no loop (research.md R7, copied verbatim from
  // EntriesRepositoryImpl's shape).
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
