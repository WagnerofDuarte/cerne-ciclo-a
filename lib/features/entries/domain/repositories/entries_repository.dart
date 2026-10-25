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
    String? chatMessageId,
    DateTime? occurredAt,
  });

  /// FR-011's "local entries store/cache" — every entry this app has ever
  /// successfully fetched or created, backed by on-device persistence so it
  /// survives a restart. `RecordsBloc` reads this back out as the offline
  /// fallback when a fetch fails outright (the PRD's "local read cache",
  /// requirements.md line 50/125).
  List<Entry> get cachedEntries;

  /// `GET /entries` (`entries-list`), paginated newest-occurred-first.
  /// Retries exactly once through `SessionRepository.refresh()` on
  /// `AuthExpiredFailure` before giving up (research.md R4).
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? limit,
  });

  /// `GET /entries/:id` (`entries-get`). Implemented and tested; no call
  /// site in this unit's UI flow (research.md R7).
  Future<Either<Failure, Entry>> getById(String id);

  /// `GET /entries/search` (`entries-search`) — bounded, no cursor
  /// (FR-005b). Retries exactly once through `SessionRepository.refresh()`
  /// on `AuthExpiredFailure`, same as `list()`/`getById()`.
  Future<Either<Failure, List<Entry>>> search({
    String? q,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,
  });

  /// Wipes [cachedEntries] and the backing `EntriesLocalCache` entirely —
  /// part of account deletion's "any other locally held user data" clear
  /// (FR-019, research.md R9). Never called by sign-out.
  Future<void> clearLocalData();
}
