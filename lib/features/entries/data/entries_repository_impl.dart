import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps [EntriesRemoteDataSource] and owns the in-memory [cachedEntries]
/// list — appended to only on a successful [create] (FR-011). Registered as
/// a `get_it` `lazySingleton` so the cache survives across modal opens (same
/// lifetime pattern as RF03's `VaultRepository`).
class EntriesRepositoryImpl implements EntriesRepository {
  EntriesRepositoryImpl(this._remoteDataSource, {required this._sessionRepository});

  final EntriesRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;

  final List<Entry> _cachedEntries = [];

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
  }) async {
    final result = await _remoteDataSource.create(
      content: content,
      source: source,
    );
    return result.map((entry) {
      _cachedEntries.add(entry);
      return entry;
    });
  }

  @override
  List<Entry> get cachedEntries => List.unmodifiable(_cachedEntries);

  @override
  Future<Either<Failure, EntriesPage>> list({String? cursor}) async {
    final result = await _remoteDataSource.list(cursor: cursor);
    return result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(() => _remoteDataSource.list(cursor: cursor))
          : Future.value(Left(failure)),
      (page) => Future.value(Right(page)),
    );
  }

  @override
  Future<Either<Failure, Entry>> getById(String id) async {
    final result = await _remoteDataSource.getById(id);
    return result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(() => _remoteDataSource.getById(id))
          : Future.value(Left(failure)),
      (entry) => Future.value(Right(entry)),
    );
  }

  // Exactly one retry. If it also comes back `AuthExpiredFailure` (a
  // pathological double-expiry), that is returned as-is — no second refresh
  // attempt, no loop (research.md R4, contracts/entries-repository-extension.md).
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
