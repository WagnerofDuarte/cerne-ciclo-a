import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps [EntriesRemoteDataSource] and owns the in-memory [cachedEntries]
/// list — appended to only on a successful [create] (FR-011). Registered as
/// a `get_it` `lazySingleton` so the cache survives across modal opens (same
/// lifetime pattern as RF03's `VaultRepository`).
class EntriesRepositoryImpl implements EntriesRepository {
  EntriesRepositoryImpl(this._remoteDataSource);

  final EntriesRemoteDataSource _remoteDataSource;

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
}
