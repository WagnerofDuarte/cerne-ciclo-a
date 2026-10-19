# Contract: `RecordsBloc` extension (`lib/features/records/presentation/bloc/records_bloc.dart`)

Extends RF07's contract (`specs/005-multi-source-timeline/contracts/records-bloc.md`) in place. Still depends
only on `EntriesRepository`. Everything below is additive; RF07's own `_onStarted`/`_onNextPageRequested`/
`_onPageLoadRetried`(first-load/next-page branch)/`close()` are unchanged except where noted.

```dart
class RecordsBloc extends Bloc<RecordsEvent, RecordsState> {
  RecordsBloc({
    required this._entriesRepository,
    this._debounceDuration = const Duration(milliseconds: 300),
  }) : super(const RecordsLoading()) {
    on<RecordsStarted>(_onStarted);
    on<NextPageRequested>(_onNextPageRequested);
    on<PageLoadRetried>(_onPageLoadRetried);
    on<RecordsLocalCacheRefreshed>(_onLocalCacheRefreshed);
    on<SearchTextChanged>(_onSearchTextChanged);
    on<SearchDebounceElapsed>(_onSearchDebounceElapsed);
    on<FilterSheetApplied>(_onFilterSheetApplied);
    on<FilterChipRemoved>(_onFilterChipRemoved);
    on<FiltersAndSearchCleared>(_onFiltersAndSearchCleared);
    on<CriteriaLoadRetried>(_onCriteriaLoadRetried);
  }

  final EntriesRepository _entriesRepository;
  final Duration _debounceDuration;
  final _reauthController = StreamController<void>.broadcast();

  String _query = '';
  DateRangeOption _dateRange = DateRangeOption.allTime;
  Set<EntrySource> _entryTypes = {};
  Timer? _debounceTimer;
  int _fetchGeneration = 0;

  Stream<void> get reauthRequired => _reauthController.stream;
}
```

## Search text → debounce → fetch (FR-001/FR-002, research.md R4/R6)

```dart
Future<void> _onSearchTextChanged(SearchTextChanged event, Emitter<RecordsState> emit) async {
  _debounceTimer?.cancel();
  _query = event.text;
  if (event.text.isEmpty) {
    // Acceptance Scenario 3 / Edge Case: no request for empty text — refetch immediately under
    // whatever filters are still active.
    await _fetchForCriteria(emit);
    return;
  }
  _debounceTimer = Timer(
    _debounceDuration,
    () => add(SearchDebounceElapsed(event.text)),
  );
}

Future<void> _onSearchDebounceElapsed(SearchDebounceElapsed event, Emitter<RecordsState> emit) async {
  if (event.text != _query) return;   // superseded by a newer keystroke/clear that arrived after the timer fired
  await _fetchForCriteria(emit);
}
```

- Deleting the text entirely before 300 ms elapses: `_debounceTimer?.cancel()` on the next
  `SearchTextChanged('')` guarantees the pending timer never fires for the abandoned partial text (Edge
  Cases).
- `_debounceTimer` is cancelled in `close()` too (alongside the existing `_reauthController.close()`).

## Filter sheet / chips / clear (FR-003/FR-005/FR-007, research.md R1/R6)

```dart
Future<void> _onFilterSheetApplied(FilterSheetApplied event, Emitter<RecordsState> emit) async {
  _dateRange = event.dateRange;
  _entryTypes = event.entryTypes;
  await _fetchForCriteria(emit);
}

Future<void> _onFilterChipRemoved(FilterChipRemoved event, Emitter<RecordsState> emit) async {
  switch (event.chip) {
    case DateRangeChip(): _dateRange = DateRangeOption.allTime;
    case EntryTypeChip(source: final s): _entryTypes = {..._entryTypes}..remove(s);
  }
  await _fetchForCriteria(emit);
}

Future<void> _onFiltersAndSearchCleared(FiltersAndSearchCleared event, Emitter<RecordsState> emit) async {
  _debounceTimer?.cancel();
  _query = '';
  _dateRange = DateRangeOption.allTime;
  _entryTypes = {};
  await _fetchForCriteria(emit);
}

Future<void> _onCriteriaLoadRetried(CriteriaLoadRetried event, Emitter<RecordsState> emit) async {
  await _fetchForCriteria(emit);   // re-attempts the exact same last-applied criteria (_query/_dateRange/_entryTypes)
}
```

## The core fetch (bounded-vs-paginated branch — research.md R1, generation guard — R6)

```dart
Future<void> _fetchForCriteria(Emitter<RecordsState> emit) async {
  final generation = ++_fetchGeneration;
  final current = state;
  if (current is RecordsLoaded) {
    emit(current.copyWith(
      isApplyingCriteria: true,
      searchQuery: _query, dateRange: _dateRange, entryTypes: _entryTypes,
    ));
  }
  // Nothing to show yet (still on RecordsLoading/RecordsLoadFailure) — RecordsStarted's own
  // _loadFirstPage() owns the very first fetch; this path is only reachable once a RecordsLoaded exists.

  final now = DateTime.now();
  final bounds = _dateRange.boundsAt(now);
  final result = await _resolveEntries(
    query: _query, dateFrom: bounds.from, dateTo: bounds.to, types: _entryTypes,
  );
  if (generation != _fetchGeneration) return;   // superseded — discard silently (FR-005a)

  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) _reauthController.add(null);
      final latest = state;
      if (latest is RecordsLoaded) {
        emit(latest.copyWith(isApplyingCriteria: false, criteriaLoadFailure: failure));
      }
    },
    (fetched) {
      final latest = state;
      if (latest is! RecordsLoaded) return;
      emit(latest.copyWith(
        entries: fetched.entries,
        nextCursor: fetched.nextCursor,          // null whenever bounded (R1)
        isApplyingCriteria: false,
        criteriaLoadFailure: null,
      ));
    },
  );
}

/// Picks the shape (single call+cursor vs. bounded fan-out-and-merge) per research.md R1.
Future<Either<Failure, ({List<Entry> entries, String? nextCursor})>> _resolveEntries({
  required String query,
  required DateTime? dateFrom,
  required DateTime? dateTo,
  required Set<EntrySource> types,
}) async {
  if (types.length <= 1) {
    final source = types.isEmpty ? null : types.single;
    if (query.isNotEmpty) {
      final result = await _entriesRepository.search(
        q: query, source: source, dateFrom: dateFrom, dateTo: dateTo,
      );
      return result.map((entries) => (entries: entries, nextCursor: null));
    }
    final result = await _entriesRepository.list(source: source, dateFrom: dateFrom, dateTo: dateTo);
    return result.map((page) => (entries: page.entries, nextCursor: page.nextCursor));
  }

  // 2+ entry types — bounded fan-out, one call per type (research.md R1).
  final calls = types.map(
    (source) => query.isNotEmpty
        ? _entriesRepository.search(q: query, source: source, dateFrom: dateFrom, dateTo: dateTo)
        : _entriesRepository.list(source: source, dateFrom: dateFrom, dateTo: dateTo, limit: 50)
            .then((r) => r.map((page) => page.entries)),
  );
  final results = await Future.wait(calls);
  for (final r in results) {
    if (r.isLeft()) return r.map((_) => (entries: <Entry>[], nextCursor: null));   // first failure wins
  }
  final merged = EntryMerger.mergeMany(
    sources: [for (final r in results) r.getOrElse((_) => [])],
    byRelevance: query.isNotEmpty,
  );
  return Right((entries: merged, nextCursor: null));
}
```

- Changing criteria always restarts from "page 1" — `_resolveEntries` never threads an old `cursor` through;
  the previous `nextCursor` is discarded the moment any criteria-changing event fires.
- `RecordsLoaded.copyWith(...)` is the one new convenience method added to `RecordsLoaded` purely to keep
  these handlers from re-listing every unrelated field on every emit (standard Dart data-class ergonomics,
  not a new domain concept).

## `_onLocalCacheRefreshed` — guarded (research.md R5)

```dart
void _onLocalCacheRefreshed(RecordsLocalCacheRefreshed event, Emitter<RecordsState> emit) {
  final current = state;
  if (current is! RecordsLoaded || current.hasAnyActiveCriteria) return;   // NEW guard
  emit(current.copyWith(
    entries: EntryMerger.merge(primary: current.entries, secondary: _entriesRepository.cachedEntries),
  ));
}
```

## `NextPageRequested` — unchanged logic, now naturally gated by bounded mode

`_onNextPageRequested`'s existing `current.hasReachedEnd` check already becomes `true` whenever the current
fetch was bounded (R1), since `_fetchForCriteria` never sets a non-`null` `nextCursor` in that case — no new
condition needed in `_onNextPageRequested` itself. `_fetchNextPage` (RF07's existing further-page fetch) gains
the same generation-guard wrapping as `_fetchForCriteria` and now also threads `source`/`dateFrom`/`dateTo`
through to `_entriesRepository.list(cursor: ..., source: ..., dateFrom: ..., dateTo: ...)` — relevant when
exactly one entry type (or none) is selected alongside a date range but no search term.

## `close()` — extended

```dart
@override
Future<void> close() {
  _debounceTimer?.cancel();
  unawaited(_reauthController.close());
  return super.close();
}
```

## Test scenarios this contract owns (for `/speckit-tasks` to schedule)

| # | Scenario | Expected |
|---|---|---|
| 1 | `SearchTextChanged('a')`, `'an'`, `'ans'` fired within the debounce window, `debounceDuration: Duration.zero` in test | exactly one `search()` call, with the final text |
| 2 | `SearchTextChanged('a')` then `SearchTextChanged('')` before the timer fires | `search()` is never called; a filter-only/unfiltered refetch happens instead |
| 3 | `FilterSheetApplied` with 1 entry type + a date range, no query | single `list(source: ..., dateFrom: ..., dateTo: ...)` call, cursor-paginated (`nextCursor` non-null when the backend returns one) |
| 4 | `FilterSheetApplied` with 2 entry types, no query | two `list()` calls (one per type, `limit: 50`), merged+deduped+sorted by `occurredAt` desc, `nextCursor: null` |
| 5 | `FilterSheetApplied` with 2 entry types + an active query | two `search()` calls, merged+deduped+sorted by `similarity` desc |
| 6 | `FilterChipRemoved(DateRangeChip(...))` | `_dateRange` resets to `allTime`, refetch fires with the remaining criteria only |
| 7 | `FilterChipRemoved(EntryTypeChip(EntrySource.audio))` with `{audio, photo}` selected | only `audio` is removed; refetch runs with `{photo}` |
| 8 | `FiltersAndSearchCleared` while a query + filters are active | `_query`/`_dateRange`/`_entryTypes` all reset; one refetch call with no criteria (equivalent to RF07's original unfiltered `list()`) |
| 9 | Two `FilterSheetApplied` events fired back-to-back, first repository call resolves after the second | the first call's result is discarded (never reaches `emit`); only the second's is shown (FR-005a) |
| 10 | A criteria-change fetch fails (non-auth) | `entries`/criteria fields unchanged, `criteriaLoadFailure` set, `isApplyingCriteria: false` |
| 11 | A criteria-change fetch fails `AuthExpiredFailure` | `reauthRequired` fires; `entries` unchanged; `criteriaLoadFailure` stays `null` (same "no visible disruption" rule RF07's next-page path already follows) |
| 12 | `CriteriaLoadRetried` after `criteriaLoadFailure` is set | re-attempts with the same `_query`/`_dateRange`/`_entryTypes` |
| 13 | `RecordsLocalCacheRefreshed` while `hasAnyActiveCriteria` is true | no-op, state unchanged (research.md R5) |
| 14 | `RecordsLocalCacheRefreshed` while no criteria active | unchanged RF07 behavior — merges `cachedEntries` in |
| 15 | A zero-result search/filter combination on a non-empty account | `isEmptyForCriteria: true`; `RecordsPage` renders `NoResultsForCriteriaView`, not `RecordsEmptyState` |
| 16 | `CriteriaLoadRetried` succeeds (simulating reconnection) after a prior `criteriaLoadFailure`, where some IDs in the stale cached `entries` also appear in the fresh server response | the emitted `entries` equals the fresh response exactly — no ID appears twice, and no leftover cached-only entry survives the replace (SC-006: the fetch is a full replace, never a merge, so reconnection can never duplicate an entry) |

Architecture check: `no_bloc_imports_bloc_test.dart` (RF07) continues to pass unmodified —
`records_bloc.dart`'s import set gains nothing beyond `dart:async`'s `Timer` and this unit's own new
`records/domain/entities/*.dart` files.
