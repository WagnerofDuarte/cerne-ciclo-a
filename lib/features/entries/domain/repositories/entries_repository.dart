import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:fpdart/fpdart.dart';

/// The shared seam research.md R8 builds because requirements.md §RF10
/// already names it (contracts/entries-repository.md). Registered as a
/// `get_it` `lazySingleton` so [cachedEntries] survives across modal opens
/// (same lifetime pattern as RF03's `VaultRepository`).
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
  });

  /// FR-011's "local entries store/cache" — in-memory, this process's
  /// lifetime. Nothing in this unit ever reads this back out for display;
  /// it exists so RF07 has something to read from day one.
  List<Entry> get cachedEntries;

  /// `GET /entries` (`entries-list`), paginated newest-occurred-first.
  /// Retries exactly once through `SessionRepository.refresh()` on
  /// `AuthExpiredFailure` before giving up (research.md R4).
  Future<Either<Failure, EntriesPage>> list({String? cursor});

  /// `GET /entries/:id` (`entries-get`). Implemented and tested; no call
  /// site in this unit's UI flow (research.md R7).
  Future<Either<Failure, Entry>> getById(String id);
}
