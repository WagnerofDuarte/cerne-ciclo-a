import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/data/entries_local_cache.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps [EntriesRemoteDataSource] and owns [cachedEntries] — an in-memory
/// mirror, backed by [EntriesLocalCache], of every entry this process has
/// seen (via a successful [create]/[list]/[search]), so it survives an app
/// restart. Registered as a `get_it` `lazySingleton` so the cache survives
/// across modal opens (same lifetime pattern as RF03's `VaultRepository`).
/// Read back out for display by `RecordsBloc` when a fetch fails outright —
/// the on-device fallback the PRD's "local read cache" describes
/// (requirements.md line 50/125).
class EntriesRepositoryImpl implements EntriesRepository {
  EntriesRepositoryImpl(
    this._remoteDataSource, {
    required this._sessionRepository,
    required this._localCache,
  });

  final EntriesRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;
  final EntriesLocalCache _localCache;

  final List<Entry> _cachedEntries = [];
  Future<void>? _localCacheLoad;

  // Runs once per process; every public method awaits it before touching
  // `_cachedEntries`, so the persisted cache is always merged in before
  // either a remote call resolves or `cachedEntries` is read back out —
  // closing the race between "app just launched" and "first read of the
  // cache."
  Future<void> _ensureLocalCacheLoaded() {
    return _localCacheLoad ??= _localCache.readAll().then(_mergeEntries);
  }

  void _mergeEntries(List<Entry> fetched) {
    for (final entry in fetched) {
      final index = _cachedEntries.indexWhere((e) => e.id == entry.id);
      if (index >= 0) {
        _cachedEntries[index] = entry;
      } else {
        _cachedEntries.add(entry);
      }
    }
  }

  Future<void> _cacheAndPersist(List<Entry> fetched) async {
    _mergeEntries(fetched);
    await _localCache.writeAll(_cachedEntries);
  }

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
  }) async {
    await _ensureLocalCacheLoaded();
    final result = await _remoteDataSource.create(
      content: content,
      source: source,
    );
    return result.match(
      (failure) => Future.value(Left(failure)),
      (entry) async {
        await _cacheAndPersist([entry]);
        return Right(entry);
      },
    );
  }

  @override
  List<Entry> get cachedEntries => List.unmodifiable(_cachedEntries);

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? limit,
  }) async {
    await _ensureLocalCacheLoaded();
    Future<Either<Failure, EntriesPage>> fetch() => _remoteDataSource.list(
      cursor: cursor,
      source: source,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
    );
    final result = await fetch();
    final Either<Failure, EntriesPage> afterRetry = await result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(fetch)
          : Future.value(Left(failure)),
      (page) => Future.value(Right(page)),
    );
    return afterRetry.match(
      (failure) => Future.value(Left(failure)),
      (page) async {
        await _cacheAndPersist(page.entries);
        return Right(page);
      },
    );
  }

  @override
  Future<Either<Failure, List<Entry>>> search({
    String? q,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,
  }) async {
    await _ensureLocalCacheLoaded();
    Future<Either<Failure, List<Entry>>> fetch() => _remoteDataSource.search(
      q: q,
      source: source,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
    );
    final result = await fetch();
    final Either<Failure, List<Entry>> afterRetry = await result.match(
      (failure) => failure is AuthExpiredFailure
          ? _retryAfterSilentRefresh(fetch)
          : Future.value(Left(failure)),
      (entries) => Future.value(Right(entries)),
    );
    return afterRetry.match(
      (failure) => Future.value(Left(failure)),
      (entries) async {
        await _cacheAndPersist(entries);
        return Right(entries);
      },
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
