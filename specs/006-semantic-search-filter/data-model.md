# Data Model: P-RF06 — Semantic search / filter

Source: spec.md §Key Entities, requirements.md §§1 (RF06), 6.2, 6.4, 8, 10, 13; `docs/input/backend/api/
openapi.yaml`'s `/entries` and `/entries/search` schemas; `docs/input/prototype/prototype-extract.md` §2.4.
This unit extends `entries/`'s shared `Entry`/`EntriesRepository` (RF01/RF07) and `records/`'s `RecordsBloc`/
`EntryMerger` (RF07) — it introduces two small new pure domain entities (`DateRangeOption`,
`ActiveFilterChip`) and widens two already-existing shapes (`Entry`, `EntryMerger`).

## `Entry` (`lib/features/entries/domain/entities/entry.dart`) — extended, not replaced

One new field, nullable, additive (research.md R3):

```dart
class Entry extends Equatable {
  const Entry({
    required this.id,
    // ...all existing fields, unchanged...
    this.similarity,   // NEW — 0.0–1.0, only ever non-null when parsed from `entries-search`'s response
  });

  final double? similarity;

  @override
  List<Object?> get props => [/* ...existing fields..., */ similarity];
}
```

Every existing construction site (RF01's `create()`, RF07's `list()`/`getById()`) omits it, so it defaults to
`null` — no behavior change for any existing consumer (`record_card.dart`, `DateGrouper`, `EntryMerger.merge`).

## `EntriesRepository` — extended (`lib/features/entries/domain/repositories/entries_repository.dart`)

```dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({required String content, required EntrySource source});  // unchanged

  List<Entry> get cachedEntries;                                                                    // unchanged

  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    EntrySource? source,     // NEW — GET /entries's existing `source` parameter
    DateTime? dateFrom,      // NEW — GET /entries's existing `dateFrom` parameter
    DateTime? dateTo,        // NEW — GET /entries's existing `dateTo` parameter
    int? limit,              // NEW — GET /entries's existing `limit` parameter; omitted ⇒ backend default (20)
  });

  Future<Either<Failure, Entry>> getById(String id);                                                // unchanged

  /// `GET /entries/search` (`entries-search`) — bounded, no cursor (FR-005b). Retries exactly once through
  /// `SessionRepository.refresh()` on `AuthExpiredFailure`, same as `list()`/`getById()` (research.md R6 of
  /// RF07's own plan, reused verbatim here).
  Future<Either<Failure, List<Entry>>> search({
    String? q,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,          // the endpoint's own maximum (openapi.yaml) — see research.md R1
  });
}
```

- `list()`'s four new parameters are each omitted from the request's `queryParameters` map when `null` —
  every existing call site (`RecordsBloc._loadFirstPage`/`_fetchNextPage` before this unit) is byte-for-byte
  unaffected.
- `search()` has no `cursor` parameter at all — `GET /entries/search` doesn't accept one (openapi.yaml).

### `EntriesRemoteDataSource` — extended (`lib/features/entries/data/entries_remote_data_source.dart`)

- `list()` passes `source`/`dateFrom`/`dateTo`/`limit` through to `ApiClient.call(..., queryParameters: {...})`
  exactly like RF07's `cursor` already does (string-keyed map, `null` entries omitted); `dateFrom`/`dateTo` are
  sent as `.toUtc().toIso8601String()`.
- `search()` calls `ApiClient.call('entries-search', method: 'GET', queryParameters: {...}, unwrapData:
  false)` — same `unwrapData: false` shape `list()` already uses, since the response is `{"data": [...],
  "meta": {"mode": ...}}`; `meta.mode` (`filter_only`/`semantic`) is read by the backend only, never consumed
  by the app (research.md — spec.md's own Clarification 2 already names which endpoint handles which case, so
  nothing here needs to branch on `meta.mode`).
- Both `list()`'s and `search()`'s per-entry parsing go through the *same* `_parseEntryFields` helper RF07
  already extracted, now additionally reading `data['similarity'] as num?` → `.toDouble()` when present (it
  never is for `entries-list`/`entries-get`/`entries-create` responses, so existing call sites keep getting
  `similarity: null`).

### `EntriesRepositoryImpl` — extended (`lib/features/entries/data/entries_repository_impl.dart`)

`search()` is implemented with the exact same `_retryAfterSilentRefresh` helper `list()`/`getById()` already
use — no new retry logic. No new constructor dependency (still just `EntriesRemoteDataSource` +
`SessionRepository`, unchanged from RF07).

## `DateRangeOption` (`lib/features/records/domain/entities/date_range_filter.dart`) — NEW

```dart
enum DateRangeOption { allTime, thisWeek, thisMonth }

extension DateRangeBounds on DateRangeOption {
  /// Pure, total; `now` defaults to `DateTime.now()` but is overridable for deterministic tests
  /// (research.md R2, mirroring `DateGrouper.group(..., {DateTime? now})`'s existing precedent).
  ({DateTime? from, DateTime? to}) boundsAt(DateTime now) => switch (this) {
    DateRangeOption.allTime => (from: null, to: null),
    DateRangeOption.thisWeek => (from: _mostRecentMonday(now), to: null),
    DateRangeOption.thisMonth => (from: DateTime(now.year, now.month), to: null),
  };
}
```

No `package:flutter` import, no I/O — pure `DateTime` arithmetic (research.md R2).

**Prototype label mapping** (prototype-extract.md §2.4's "Sheet de filtro", "INTERVALO DE DATA" group, single
choice):

| `DateRangeOption` | Label |
|---|---|
| `allTime` | "Todo o período" |
| `thisWeek` | "Esta semana" |
| `thisMonth` | "Este mês" |

## `ActiveFilterChip` (`lib/features/records/domain/entities/active_filter_chip.dart`) — NEW

```dart
sealed class ActiveFilterChip extends Equatable {
  const ActiveFilterChip();
}

class DateRangeChip extends ActiveFilterChip {
  const DateRangeChip(this.option);          // option is never DateRangeOption.allTime (see derive() below)
  final DateRangeOption option;
  @override List<Object?> get props => [option];
}

class EntryTypeChip extends ActiveFilterChip {
  const EntryTypeChip(this.source);
  final EntrySource source;
  @override List<Object?> get props => [source];
}

class ActiveFilterChips {
  const ActiveFilterChips._();

  /// Pure derivation — one chip per currently-applied Filter Set criterion (Key Entities: "Active Filter
  /// Chip"). The active search term is deliberately NOT a chip here (FR-006 scopes chips to the Filter Set —
  /// date range + entry types — not the Search Query, a separate Key Entity); "Limpar filtros" still clears
  /// both (FR-007).
  static List<ActiveFilterChip> derive({
    required DateRangeOption dateRange,
    required Set<EntrySource> entryTypes,
  }) => [
    if (dateRange != DateRangeOption.allTime) DateRangeChip(dateRange),
    for (final source in entryTypes) EntryTypeChip(source),
  ];
}
```

## `EntryMerger` (`lib/features/records/domain/entities/entry_merger.dart`) — extended

```dart
class EntryMerger {
  const EntryMerger._();

  static List<Entry> merge({required List<Entry> primary, required List<Entry> secondary});  // unchanged (RF07)

  /// NEW — N equal-weight sources (one per selected entry type, research.md R1), deduped by id (last write
  /// wins; in practice no two sources ever share an id, since every entry has exactly one `source`), sorted
  /// either by `similarity` (an active search term) or by `occurredAt` (no search term) — FR-005's "re-sorted
  /// ... by relevance when a search term is active, otherwise reverse-chronological."
  static List<Entry> mergeMany({
    required List<List<Entry>> sources,
    required bool byRelevance,
  }) {
    final byId = <String, Entry>{};
    for (final list in sources) {
      for (final entry in list) {
        byId[entry.id] = entry;
      }
    }
    final merged = byId.values.toList();
    merged.sort(
      byRelevance
          ? (a, b) => (b.similarity ?? 0).compareTo(a.similarity ?? 0)
          : (a, b) => b.occurredAt.compareTo(a.occurredAt),
    );
    return merged;
  }
}
```

`mergeMany` is used both when 2+ entry types are selected (R1) and, trivially, with a single-element `sources`
list for the ordinary single-type-or-no-type search path — keeping exactly one merge/sort code path for every
bounded fetch, rather than a special case for "only one type selected."

## `RecordsEvent` (`lib/features/records/presentation/bloc/records_event.dart`) — extended

| Event | When |
|---|---|
| `RecordsStarted` | Unchanged (RF07). |
| `NextPageRequested` | Unchanged (RF07) — now a no-op whenever the current criteria is bounded (R1/FR-005b), because `nextCursor` is `null` in that case. |
| `PageLoadRetried` | Unchanged (RF07) for a first-load/next-page failure; see `CriteriaLoadRetried` below for a criteria-change failure. |
| `RecordsLocalCacheRefreshed` | Unchanged signature; behavior gains the "no-op while criteria active" guard (research.md R5). |
| `SearchTextChanged(String text)` | **NEW** — the search bar's `onChanged`, fired on every keystroke. |
| `SearchDebounceElapsed(String text)` *(internal)* | **NEW** — fired by the bloc's own `Timer`, 300 ms after the last `SearchTextChanged` with non-empty text; never dispatched directly by any widget. |
| `FilterSheetApplied({required DateRangeOption dateRange, required Set<EntrySource> entryTypes})` | **NEW** — the filter sheet's "Aplicar" button. |
| `FilterChipRemoved(ActiveFilterChip chip)` | **NEW** — tapping a single active-filter chip's remove control. |
| `FiltersAndSearchCleared` | **NEW** — "Limpar filtros" (clears date range, entry types, **and** the search text — FR-007). |
| `CriteriaLoadRetried` | **NEW** — "Tentar novamente" on a failed criteria-change fetch (`criteriaLoadFailure`); re-attempts the same last-applied criteria. |

## `RecordsState` (`lib/features/records/presentation/bloc/records_state.dart`) — extended

```dart
class RecordsLoaded extends RecordsState {
  const RecordsLoaded({
    required this.entries,
    required this.nextCursor,          // null whenever the current criteria is bounded (R1) — see hasReachedEnd
    required this.isLoadingMore,
    this.pageLoadFailure,              // unchanged (RF07) — a further-page (unbounded-mode) fetch failed
    this.searchQuery = '',             // NEW
    this.dateRange = DateRangeOption.allTime,   // NEW
    this.entryTypes = const {},        // NEW
    this.isApplyingCriteria = false,   // NEW — a criteria-change fetch is in flight (RNF01's >300ms affordance)
    this.criteriaLoadFailure,          // NEW — a criteria-change fetch failed; entries/criteria fields unchanged
  });

  final List<Entry> entries;
  final String? nextCursor;
  final bool isLoadingMore;
  final Failure? pageLoadFailure;
  final String searchQuery;
  final DateRangeOption dateRange;
  final Set<EntrySource> entryTypes;
  final bool isApplyingCriteria;
  final Failure? criteriaLoadFailure;

  bool get hasReachedEnd => nextCursor == null;
  bool get isEmpty => entries.isEmpty;

  bool get isSearchActive => searchQuery.isNotEmpty;
  bool get hasActiveFilters => dateRange != DateRangeOption.allTime || entryTypes.isNotEmpty;
  bool get hasAnyActiveCriteria => isSearchActive || hasActiveFilters;

  List<ActiveFilterChip> get activeChips =>
      ActiveFilterChips.derive(dateRange: dateRange, entryTypes: entryTypes);

  /// FR-009 — distinct from `isEmpty` alone: only true when narrowing (not a true zero-entries account)
  /// produced the empty result.
  bool get isEmptyForCriteria => isEmpty && hasAnyActiveCriteria;
}
```

- `RecordsLoading`/`RecordsLoadFailure` are unchanged from RF07 — still only used for the very first app-level
  load, before any `RecordsLoaded` exists to carry criteria.
- `isEmptyForCriteria` vs. plain `isEmpty` is what `RecordsPage` uses to choose between
  `no_results_for_criteria_view.dart` (FR-009) and RF07's unmodified `records_empty_state.dart`
  (account-wide "Nenhum registro ainda").

## `RecordsBloc` (`lib/features/records/presentation/bloc/records_bloc.dart`) — extended

```dart
class RecordsBloc extends Bloc<RecordsEvent, RecordsState> {
  RecordsBloc({
    required EntriesRepository entriesRepository,
    Duration debounceDuration = const Duration(milliseconds: 300),   // NEW, injectable (research.md R4)
  });

  Stream<void> get reauthRequired;   // unchanged (RF07)
}
```

New private state: `String _query = ''`, `DateRangeOption _dateRange = DateRangeOption.allTime`,
`Set<EntrySource> _entryTypes = {}`, `Timer? _debounceTimer`, `int _fetchGeneration = 0` — see
`contracts/records-bloc-extension.md` for the exact handler-by-handler sequencing (debounce, generation
guard, bounded-vs-paginated branch, and how `FilterChipRemoved`/`FiltersAndSearchCleared` each re-fetch).

Still depends only on `EntriesRepository` — no new constructor dependency (research.md's Post-Design
Constitution Check).

## Widgets (`lib/features/records/presentation/`) — new/changed

Not separately contracted beyond `contracts/filter-sheet-widget.md` (pure prototype-fidelity rendering, no new
domain logic beyond what's above):

- `records_page.dart` — `_SearchBar`'s `TextField` becomes `enabled: true`, dispatching `SearchTextChanged` on
  every change; the funnel button's `onPressed` opens `FilterSheet` via `showModalBottomSheet`, and its icon
  swaps to the filled variant whenever `RecordsLoaded.hasActiveFilters` is true (FR-006). `_buildLoaded` adds
  the `ActiveFilterChipsRow` (only when `activeChips.isNotEmpty`) directly under `_SearchBar`, and branches
  `isEmptyForCriteria` to `NoResultsForCriteriaView` instead of `RecordsEmptyState`.
- `filter_sheet.dart` — **NEW**. A `StatefulWidget` holding its own local, uncommitted selections
  (`_localDateRange`, `_localEntryTypes`, `_localCategoryChips` — the last never leaves this widget, FR-004).
  "Aplicar" dispatches `FilterSheetApplied` with the local selections and closes the sheet; "Limpar" resets
  only this widget's own local `State` (no dispatch, no close — Story 2/Acceptance Scenario 3).
- `active_filter_chips_row.dart` — **NEW**. One removable chip per `RecordsLoaded.activeChips` entry (label
  via `DateRangeOption`'s mapping table above or `EntrySource`'s existing name), each dispatching
  `FilterChipRemoved(chip)`; a trailing "Limpar filtros" `TextButton` dispatching `FiltersAndSearchCleared`.
- `no_results_for_criteria_view.dart` — **NEW**. Distinct copy from `records_empty_state.dart` (FR-009), with
  a button that dispatches `FiltersAndSearchCleared` ("adjust or clear the applied criteria").

**Token reuse** (prototype-extract.md §2.4 — no new token, Principle IV):

| Element | Token |
|---|---|
| Filter sheet surface | `DesignTokens.colorSurfaceElevated` |
| Filter sheet group labels ("INTERVALO DE DATA" etc.) | `DesignTokens.textLabelMd` + `colorTextSecondary` |
| Unselected chip | `DesignTokens.colorSurfaceBg` fill, `colorBorder` side (same as `record_card.dart`'s tag chips) |
| Selected chip (date-range radio or entry-type multi-select) | `DesignTokens.colorPrimary` fill, `colorOnPrimary` text |
| Active-filter chip / filled funnel button | `DesignTokens.colorAccent` (matches the prototype's funnel-filled state) |
| "Limpar filtros" link | `DesignTokens.textLabelMd` + `colorAccent` |

## Routing / DI changes

None beyond what RF07 already registered — `RecordsBloc`'s `getIt.registerFactory` call keeps the same single
dependency; its new `debounceDuration` constructor parameter is left at its default in the DI registration
(production never overrides it — only tests do, by constructing `RecordsBloc` directly).
