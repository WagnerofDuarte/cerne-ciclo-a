---

description: "Task list for P-RF06 — Semantic search / filter"
---

# Tasks: P-RF06 — Semantic search / filter

**Input**: Design documents from `/specs/006-semantic-search-filter/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. `plan.md`'s Constitution Check marks RNF07 (domain coverage ≥80%) "PASS (gate carried
into tasks)", and `contracts/*.md` + `quickstart.md`'s "Automated checks" section each enumerate scenario
tables explicitly "for `/speckit-tasks` to schedule" — this is this feature's own design material requesting
test tasks, not an invented addition.

**Organization**: Tasks are grouped by user story (spec.md's four User Stories, P1/P1/P2/P3). This feature
extends exactly two existing feature folders (`lib/features/entries/`, `lib/features/records/`) in place —
there is no new bloc and no new feature folder, so most of the shared state-machine plumbing (one bloc, one
repository interface) is necessarily Foundational; each User Story phase then adds that story's own
event-handler bodies, widget wiring, and tests on top of the shared machinery.

## Path Conventions

Single Flutter project (plan.md's "Project Type"): `lib/features/<feature>/{domain,data,presentation}/`,
mirrored under `test/features/<feature>/...`. No `backend/`/`frontend/` split, no `.env`/native project file
touched (Constraints, FR-011).

---

## Phase 1: Setup

No setup tasks. `plan.md`'s "Primary Dependencies" is explicit — "No additions... reuses the full existing
stack" — and no new feature folder, package, or project file is introduced (Project Structure §Structure
Decision). Proceed directly to Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the shared data contract (`Entry`/`EntriesRepository`/data layer) and the shared `RecordsBloc`
state machine (events, state fields, generation-guarded fetch core) that every user story's handlers plug into.

**⚠️ CRITICAL**: No user story phase can begin until this phase is complete — `RecordsBloc`'s new event
handlers (one or more per story) all call into `_fetchForCriteria`/`_resolveEntries`, built here once.

- [X] T001 [P] Add a nullable `similarity` field to `Entry` in `lib/features/entries/domain/entities/entry.dart`:
  `final double? similarity;`, added to the constructor and to `props`. Per data-model.md: "0.0–1.0, only ever
  non-null when parsed from `entries-search`'s response." Every existing construction site (`create()`,
  `list()`, `getById()`) must keep compiling by omitting it, defaulting to `null` (research.md R3) — no other
  file changes.

- [X] T002 [P] Create `lib/features/records/domain/entities/date_range_filter.dart`: `enum DateRangeOption {
  allTime, thisWeek, thisMonth }` plus an extension `DateRangeBounds` with `({DateTime? from, DateTime? to})
  boundsAt(DateTime now)` (research.md R2): `allTime` → `(from: null, to: null)`; `thisWeek` → `from` = the
  most recent Monday at local 00:00:00, `to: null`; `thisMonth` → `from` = the 1st of `now`'s local calendar
  month at 00:00:00, `to: null`. Pure `DateTime` arithmetic — no `package:flutter` import, no I/O
  (Constitution Principle V/RNF06).

- [X] T003 [P] Create `lib/features/records/domain/entities/active_filter_chip.dart`: `sealed class
  ActiveFilterChip extends Equatable` with subclasses `DateRangeChip(DateRangeOption option)` and
  `EntryTypeChip(EntrySource source)`, plus `class ActiveFilterChips` with a static `derive({required
  DateRangeOption dateRange, required Set<EntrySource> entryTypes}) => List<ActiveFilterChip>` that emits a
  `DateRangeChip` only "when `dateRange != DateRangeOption.allTime`" and one `EntryTypeChip` per entry in
  `entryTypes` (data-model.md) — the active search query is deliberately never a chip (FR-006 scopes chips to
  the Filter Set only).

- [X] T004 [P] Add `static List<Entry> mergeMany({required List<List<Entry>> sources, required bool
  byRelevance})` to `lib/features/records/domain/entities/entry_merger.dart` (existing `merge()` unchanged):
  dedupe by `entry.id` across all `sources` (last write wins), then sort the result "by `similarity` (an
  active search term) or by `occurredAt` (no search term)" per `byRelevance` — `(b.similarity ?? 0)
  .compareTo(a.similarity ?? 0)` descending, or `b.occurredAt.compareTo(a.occurredAt)` descending (data-model.md).

- [X] T005 [P] Extend `EntriesRepository` in `lib/features/entries/domain/repositories/entries_repository.dart`:
  add `EntrySource? source`, `DateTime? dateFrom`, `DateTime? dateTo`, `int? limit` optional params to `list()`
  (all additive — "omitted ⇒ backend default (20)" for `limit`); add a new method `Future<Either<Failure,
  List<Entry>>> search({String? q, EntrySource? source, DateTime? dateFrom, DateTime? dateTo, int limit =
  50})` — `limit`'s default of 50 is "the endpoint's own maximum" (data-model.md); `search()` has no `cursor`
  parameter at all, since `GET /entries/search` doesn't accept one.

- [X] T006 Extend `lib/features/entries/data/entries_remote_data_source.dart` per
  `contracts/entries-repository-search-extension.md`: `list()` adds `source`/`dateFrom`/`dateTo`/`limit` to its
  `queryParameters` map, each omitted when `null` (`source.name`; `dateFrom`/`dateTo` as
  `.toUtc().toIso8601String()`; `limit.toString()`); add `search()` calling `_apiClient.call('entries-search',
  method: 'GET', queryParameters: {...}, unwrapData: false)` with `q` omitted "when `q` is `null` or empty"
  (never sends `q=`) and `limit` always sent; extend the shared `_parseEntryFields` helper with one more
  optional read: `similarity: (data['similarity'] as num?)?.toDouble()`. Depends on T001, T005.

- [X] T007 Implement `EntriesRepositoryImpl.search()` in `lib/features/entries/data/entries_repository_impl.dart`,
  reusing the existing `_retryAfterSilentRefresh` helper verbatim — "exactly one retry, no loop, no new
  helper" (contract) — on `AuthExpiredFailure`, identical shape to `list()`/`getById()`; update `list()`'s
  implementation to pass its four new parameters straight through to the data source. Depends on T006.

- [X] T008 [P] Add six new `RecordsEvent` subclasses to `lib/features/records/presentation/bloc/records_event.dart`:
  `SearchTextChanged(String text)`; `SearchDebounceElapsed(String text)` (internal — "never dispatched
  directly by any widget"); `FilterSheetApplied({required DateRangeOption dateRange, required Set<EntrySource>
  entryTypes})`; `FilterChipRemoved(ActiveFilterChip chip)`; `FiltersAndSearchCleared`; `CriteriaLoadRetried`.
  Depends on T002, T003 (for the types these events carry).

- [X] T009 [P] Extend `RecordsLoaded` in `lib/features/records/presentation/bloc/records_state.dart` with five
  new fields — `searchQuery` (default `''`), `dateRange` (default `DateRangeOption.allTime`), `entryTypes`
  (default `const {}`), `isApplyingCriteria` (default `false`), `criteriaLoadFailure` (nullable, default
  `null`) — plus getters `isSearchActive` (`searchQuery.isNotEmpty`), `hasActiveFilters` (`dateRange !=
  DateRangeOption.allTime || entryTypes.isNotEmpty`), `hasAnyActiveCriteria` (`isSearchActive ||
  hasActiveFilters`), `activeChips` (`ActiveFilterChips.derive(dateRange: dateRange, entryTypes: entryTypes)`),
  and `isEmptyForCriteria` ("only true when narrowing... produced the empty result": `isEmpty &&
  hasAnyActiveCriteria`); add a `copyWith(...)` method covering every `RecordsLoaded` field. Depends on T002, T003.

- [X] T010 Wire the `RecordsBloc` skeleton in `lib/features/records/presentation/bloc/records_bloc.dart`: add
  an injectable `Duration debounceDuration = const Duration(milliseconds: 300)` constructor parameter
  (research.md R4); add private fields `String _query = ''`, `DateRangeOption _dateRange =
  DateRangeOption.allTime`, `Set<EntrySource> _entryTypes = {}`, `Timer? _debounceTimer`, `int
  _fetchGeneration = 0`; register the six new `on<...>()` handlers (stub bodies for now) alongside the existing
  four; extend `close()` to `_debounceTimer?.cancel()` alongside the existing `_reauthController.close()`.
  Depends on T008, T009.

- [X] T011 Implement the shared fetch core in `lib/features/records/presentation/bloc/records_bloc.dart`
  (`contracts/records-bloc-extension.md`): `_fetchForCriteria(Emitter<RecordsState> emit)` — bumps
  `_fetchGeneration` before any `await`, emits `isApplyingCriteria: true` with the current
  `searchQuery`/`dateRange`/`entryTypes`, computes `_dateRange.boundsAt(DateTime.now())`, calls
  `_resolveEntries(...)`, and checks `if (generation != _fetchGeneration) return;` immediately after the
  `await` and before any `emit` (FR-005a/research.md R6) — then emits either `criteriaLoadFailure` (routing
  `AuthExpiredFailure` to `_reauthController` instead) or the fetched `entries`/`nextCursor`; and
  `_resolveEntries(...)` — "picks the shape... per research.md R1": when `types.length <= 1`, one
  `search()`/`list()` call (cursor-paginated via `list()` when no query, bounded via `search()` when `query`
  is non-empty); when `types.length >= 2`, one bounded call per type (`limit: 50`, `search()` when `query` is
  non-empty else `list()`), merged via `EntryMerger.mergeMany(byRelevance: query.isNotEmpty)`, first failure
  wins, `nextCursor: null`. Depends on T004, T007, T009, T010.

- [X] T012 [P] Unit tests for `DateRangeOption.boundsAt()` in
  `test/features/records/domain/entities/date_range_filter_test.dart`: `allTime` → both bounds `null`;
  `thisWeek` → `from` is the most recent Monday 00:00:00 for a fixed, non-Monday `now`; `thisMonth` → `from` is
  the 1st of `now`'s month at 00:00:00; all cases pass a fixed `now` for determinism. Depends on T002.

- [X] T013 [P] Unit tests for `ActiveFilterChips.derive()` in
  `test/features/records/domain/entities/active_filter_chip_test.dart`: `allTime` + empty `entryTypes` →
  empty list (no `DateRangeChip` for the "no filter" state); a non-`allTime` range → exactly one
  `DateRangeChip`; multiple `entryTypes` → one `EntryTypeChip` per source. Depends on T003.

- [X] T014 [P] Unit tests for `EntryMerger.mergeMany()` in
  `test/features/records/domain/entities/entry_merger_test.dart`: an id present in two of three `sources` lists
  is shown exactly once (last-write-wins); `byRelevance: true` sorts descending by `similarity` (entries with
  `similarity: null` treated as `0`); `byRelevance: false` sorts descending by `occurredAt`; a single-element
  `sources` list still dedupes/sorts (the "trivial" path noted in data-model.md). Depends on T004.

- [X] T015 [P] Regression tests for `EntriesRepository.list()`'s four new parameters in
  `test/features/entries/data/entries_remote_data_source_test.dart` and
  `test/features/entries/data/entries_repository_impl_test.dart`: contract scenario #1 (`list(source:
  EntrySource.audio)` → `queryParameters` includes `source: 'audio'`, no `dateFrom`/`dateTo`/`limit` keys);
  #2 (`list(dateFrom: d1, dateTo: d2)` → both sent as UTC ISO-8601 strings); #3 (`list()` with every new param
  omitted → `queryParameters` byte-for-byte identical to RF07's original call shape — no regression). Depends on T006.

**Checkpoint**: Foundation ready — `RecordsBloc` compiles with all ten event handlers registered (six new
stubs + four unchanged), the fetch core is implemented and generation-guarded, and the data layer's
`list()`/`search()` extensions are tested. User story implementation can now begin.

---

## Phase 3: User Story 1 - Finding an entry by what it means, not what it says (Priority: P1) 🎯 MVP

**Goal**: wire the search bar to `GET /entries/search`'s `q` parameter with a 300 ms debounce and
request-supersession, per FR-001/FR-002/FR-005a/FR-005b.

**Independent Test**: seed the three fixtures from `docs/input/backend/fixtures/seeded-search-entries.md`
(none containing the literal term) and confirm each of `ansiedade`/`cansaço`/`gratidão` returns its matching
entry via the live search bar.

### Implementation for User Story 1

- [X] T016 [US1] Implement `_onSearchTextChanged(SearchTextChanged event, Emitter<RecordsState> emit)` in
  `lib/features/records/presentation/bloc/records_bloc.dart`: cancel any pending `_debounceTimer`, set `_query
  = event.text`; when `event.text.isEmpty`, immediately `await _fetchForCriteria(emit)` and return (Acceptance
  Scenario 3/Edge Cases — "no request for empty text"); otherwise start a new `Timer(_debounceDuration, () =>
  add(SearchDebounceElapsed(event.text)))` (FR-002, research.md R4).

- [X] T017 [US1] Implement `_onSearchDebounceElapsed(SearchDebounceElapsed event, Emitter<RecordsState> emit)`
  in the same file: `if (event.text != _query) return;` (discards a timer that fired after a newer
  keystroke/clear already superseded it), else `await _fetchForCriteria(emit)`. Depends on T016 (same file).

- [X] T018 [P] [US1] Make `_SearchBar`'s `TextField` live in
  `lib/features/records/presentation/pages/records_page.dart`: change `enabled: false` to `enabled: true` and
  add `onChanged: (text) => context.read<RecordsBloc>().add(SearchTextChanged(text))` — "no local debounce
  logic in the widget" (contract), dispatched on every keystroke.

### Tests for User Story 1

- [X] T019 [P] [US1] Repository/data-source tests for `search()` in
  `test/features/entries/data/entries_remote_data_source_test.dart` and
  `test/features/entries/data/entries_repository_impl_test.dart` — contract scenarios #4 (`search(q:
  'ansiedade')` → `entries-search` called with `q`, default `limit: 50`, no `source`/`dateFrom`/`dateTo`); #5
  (a response `similarity` value parses into non-null `Entry.similarity`); #6 (a response omitting
  `similarity` parses to `Entry.similarity == null`, no `TypeError`); #7 (`AuthExpiredFailure` → silent refresh
  succeeds → retried exactly once, final result is the retry's); #8 (silent refresh also fails →
  `AuthExpiredFailure` returned, no second retry); #9 (an empty `q` string omits the `q` key entirely —
  "never sends `q=`"); #10 (a malformed `entries-search` response → `ValidationFailure`, not a thrown
  exception).

- [X] T020 [P] [US1] Debounce `bloc_test` cases in `test/features/records/presentation/bloc/records_bloc_test.dart`
  (construct with `debounceDuration: Duration.zero`) — contract scenario #1 (`SearchTextChanged('a')`, `'an'`,
  `'ans'` fired in quick succession → exactly one `search()` call, with the final text only); #2
  (`SearchTextChanged('a')` then `SearchTextChanged('')` before the timer fires → `search()` is never called;
  a filter-only/unfiltered refetch happens instead).

- [X] T021 [US1] Widget test for the live search bar in `test/features/records/presentation/pages/records_page_test.dart`
  (new file) — `filter-sheet-widget.md` scenario #10: typing into the `TextField` dispatches
  `SearchTextChanged` to a mocked/fake `RecordsBloc` once per keystroke (debounce coalescing itself is
  verified in T020, not here).

**Checkpoint**: Typing in the search bar now returns semantically-ranked results 300 ms after the user
pauses, with no request for an abandoned or cleared term, and a stale response can never overwrite a newer
one. User Story 1 is independently testable and shippable as the MVP.

---

## Phase 4: User Story 2 - Narrowing the list with filters (Priority: P1)

**Goal**: the filter sheet's date-range and multi-select entry-type criteria narrow the list via
`dateFrom`/`dateTo`/`source`, ANDed with each other and any active search term, ORed within the entry-type
axis (FR-003/FR-004/FR-005).

**Independent Test**: on an account with mixed dates/sources, open the filter sheet, apply a date range plus
an entry-type selection together, and confirm the result list satisfies both.

### Implementation for User Story 2

- [X] T022 [US2] Implement `_onFilterSheetApplied(FilterSheetApplied event, Emitter<RecordsState> emit)` in
  `lib/features/records/presentation/bloc/records_bloc.dart`: `_dateRange = event.dateRange; _entryTypes =
  event.entryTypes;` then `await _fetchForCriteria(emit)`.

- [X] T023 [US2] Extend `_fetchNextPage` (RF07's existing further-page fetch, same file) to thread
  `source`/`dateFrom`/`dateTo` through to `_entriesRepository.list(cursor: ..., source: ..., dateFrom: ...,
  dateTo: ...)` and wrap it with the same generation-guard `_fetchForCriteria` uses — relevant whenever exactly
  one entry type (or none) is selected alongside a date range but no search term, so cursor pagination keeps
  narrowing correctly on later pages too. Depends on T011, T022 (same file).

- [X] T024 [P] [US2] Create `lib/features/records/presentation/widgets/filter_sheet.dart`
  (`contracts/filter-sheet-widget.md`): a `StatefulWidget` seeded with `initialDateRange`/`initialEntryTypes`;
  "INTERVALO DE DATA" single-choice chip group over `DateRangeOption.values` (labels: "Todo o período" / "Esta
  semana" / "Este mês" — data-model.md's mapping table); "CATEGORIA" multi-select chip group over a
  presentation-only `enum _CategoryChip { work, routine, rest, relationships }` (English identifiers per
  Constitution Principle IV, with a local label map to the Portuguese chip text — same pattern
  `DateRangeOption` uses) whose selection "exists only inside `filter_sheet.dart`" and is never read outside it
  (FR-004); "TIPO DE ENTRADA" multi-select chip group
  over `EntrySource.values`; "Aplicar" pops the route with `(dateRange: _dateRange, entryTypes: _entryTypes)`
  (category selections discarded); "Limpar" resets only this widget's own local state (`_dateRange =
  DateRangeOption.allTime; _entryTypes = {}; _categoryChips = {}`) without closing the sheet and without
  dispatching anything (Story 2/Acceptance Scenario 3).

- [X] T025 [US2] In `lib/features/records/presentation/pages/records_page.dart`, wire the funnel `IconButton`'s
  `onPressed` to open `FilterSheet` via `showModalBottomSheet`, seeded with the current `RecordsLoaded
  .dateRange`/`.entryTypes` (so re-opening reflects what's already applied); on a non-null pop result, dispatch
  `FilterSheetApplied(dateRange: ..., entryTypes: ...)` to `RecordsBloc`. Depends on T024.

### Tests for User Story 2

- [X] T026 [P] [US2] Filter-param tests for `EntriesRepository.list()` in
  `test/features/entries/data/entries_remote_data_source_test.dart`/`entries_repository_impl_test.dart` —
  contract scenarios #1 and #2 (already covered structurally by T015; this task adds the
  `EntriesRepositoryImpl`-level assertions that `list(source:, dateFrom:, dateTo:)` reaches the remote data
  source unchanged, exercised through the public repository API the bloc actually calls).

- [X] T027 [P] [US2] `FilterSheetApplied` `bloc_test` cases in
  `test/features/records/presentation/bloc/records_bloc_test.dart` — contract scenarios #3 (one entry type +
  a date range, no query → a single `list(source:, dateFrom:, dateTo:)` call, cursor-paginated, non-null
  `nextCursor` when the fake backend returns one); #4 (two entry types, no query → two `list()` calls, one per
  type, each `limit: 50`, merged+deduped+sorted by `occurredAt` descending, `nextCursor: null`); #5 (two entry
  types + an active query → two `search()` calls, merged+deduped+sorted by `similarity` descending); #9 (two
  `FilterSheetApplied` events fired back-to-back, the first repository call resolving after the second → the
  first call's result never reaches `emit`; only the second renders — FR-005a).

- [X] T028 [P] [US2] Widget tests for `FilterSheet` in
  `test/features/records/presentation/widgets/filter_sheet_test.dart` (new file) — contract scenarios #1
  (select "Esta semana" + "áudio", tap "Aplicar" → pops with `dateRange: thisWeek, entryTypes: {audio}`); #2
  (opened with `{audio, photo}` already applied → both chips render pre-selected, not a blank form); #3 (select
  a "CATEGORIA" chip, tap "Aplicar" → the popped result carries no category information at all); #4 (select
  several chips, tap "Limpar" → all local selections visually clear; the sheet stays open; nothing pops).

**Checkpoint**: Both User Story 1 and User Story 2 work independently and together (AND across date
range/entry-type/search, OR within entry-type) — a filter-only combination, a search-only combination, and a
combined search+filter combination each narrow the list correctly.

---

## Phase 5: User Story 3 - Seeing and clearing what's currently applied (Priority: P2)

**Goal**: every active Filter Set criterion shows a removable chip, a "Limpar filtros" link, and the funnel
button's filled state, per FR-006/FR-007.

**Independent Test**: apply two filters, confirm one chip per criterion plus the filled funnel button; remove
one chip and confirm only that criterion drops; use "Limpar filtros" and confirm the full list returns without
reloading the screen.

### Implementation for User Story 3

- [X] T029 [US3] Implement `_onFilterChipRemoved(FilterChipRemoved event, Emitter<RecordsState> emit)` in
  `lib/features/records/presentation/bloc/records_bloc.dart`: `switch (event.chip) { case DateRangeChip():
  _dateRange = DateRangeOption.allTime; case EntryTypeChip(source: final s): _entryTypes = {..._entryTypes}
  ..remove(s); }` then `await _fetchForCriteria(emit)` — only the targeted criterion is dropped.

- [X] T030 [US3] Implement `_onFiltersAndSearchCleared(FiltersAndSearchCleared event, Emitter<RecordsState>
  emit)` in the same file: cancel `_debounceTimer`, reset `_query = ''`, `_dateRange =
  DateRangeOption.allTime`, `_entryTypes = {}`, then `await _fetchForCriteria(emit)` — "clears date range,
  entry types, **and** the search text" (FR-007). Depends on T029 (same file).

- [X] T031 [P] [US3] Create `lib/features/records/presentation/widgets/active_filter_chips_row.dart`
  (`contracts/filter-sheet-widget.md`): one removable chip per entry in the `chips` constructor param — a
  `DateRangeChip(option)` labeled via data-model.md's mapping table, an `EntryTypeChip(source)` labeled with
  the prototype's own entry-type names ("manual"/"áudio"/"foto"/"chat") — each chip's remove control
  dispatching `FilterChipRemoved(chip)`; a trailing "Limpar filtros" `TextButton` dispatching
  `FiltersAndSearchCleared`.

- [X] T032 [US3] In `lib/features/records/presentation/pages/records_page.dart`: render
  `ActiveFilterChipsRow(chips: loaded.activeChips)` directly under `_SearchBar`, only when
  `loaded.activeChips.isNotEmpty` (FR-006); swap the funnel `IconButton`'s icon/background between the neutral
  RF07 styling and the filled variant (`Icons.filter_alt`, `colorAccent` background/`colorOnAccent` icon) based
  on `loaded.hasActiveFilters`. Depends on T031.

### Tests for User Story 3

- [X] T033 [P] [US3] `FilterChipRemoved`/`FiltersAndSearchCleared` `bloc_test` cases in
  `test/features/records/presentation/bloc/records_bloc_test.dart` — contract scenarios #6
  (`FilterChipRemoved(DateRangeChip(...))` → `_dateRange` resets to `allTime`, refetch with the remaining
  criteria only); #7 (`FilterChipRemoved(EntryTypeChip(EntrySource.audio))` with `{audio, photo}` selected →
  only `audio` is removed, refetch runs with `{photo}`); #8 (`FiltersAndSearchCleared` while a query + filters
  are active → `_query`/`_dateRange`/`_entryTypes` all reset, one refetch call with no criteria — equivalent to
  RF07's original unfiltered `list()`).

- [X] T034 [P] [US3] Widget tests in
  `test/features/records/presentation/widgets/active_filter_chips_row_test.dart` (new file) and for the funnel
  button in `records_page_test.dart` — contract scenarios #5 (`hasActiveFilters == true` → funnel renders
  filled); #6 (`activeChips` has 2 entries → `ActiveFilterChipsRow` renders 2 removable chips + "Limpar
  filtros"); #7 (tapping a chip's remove control dispatches `FilterChipRemoved` with that exact chip value);
  #8 (tapping "Limpar filtros" dispatches `FiltersAndSearchCleared`).

**Checkpoint**: Applied criteria are always visible and individually or collectively removable without
reloading the screen — User Stories 1–3 are each independently functional and correctly compose together.

---

## Phase 6: User Story 4 - Cached results stay trustworthy through a connectivity blip (Priority: P3)

**Goal**: offline, the last successfully loaded search/filter results stay on screen; reconnecting reconciles
without duplicating entries; a failed criteria-change fetch is retryable without losing what's shown
(FR-010, research.md R5/R7).

**Independent Test**: load a search/filter result list, simulate a connectivity loss and restoration, and
confirm the cached list stays visible throughout with no duplicate entries once reconnected.

### Implementation for User Story 4

- [X] T035 [US4] Guard `_onLocalCacheRefreshed` in `lib/features/records/presentation/bloc/records_bloc.dart`
  (research.md R5): add `if (current is! RecordsLoaded || current.hasAnyActiveCriteria) return;` before the
  existing merge — a just-created entry that doesn't satisfy the current search/filter criteria must never be
  merged in while criteria are active, to avoid violating FR-005's AND-across-axes guarantee.

- [X] T036 [US4] Implement `_onCriteriaLoadRetried(CriteriaLoadRetried event, Emitter<RecordsState> emit)` in
  the same file: `await _fetchForCriteria(emit)` — re-attempts with the exact same last-applied
  `_query`/`_dateRange`/`_entryTypes` already stored on the bloc. Depends on T035 (same file).

- [X] T037 [P] [US4] In `lib/features/records/presentation/pages/records_page.dart`, add an inline retryable
  error banner for `loaded.criteriaLoadFailure` (mirroring the existing `pageLoadFailure`/`_RetryBanner`
  pattern), whose retry action dispatches `CriteriaLoadRetried` — "a clear, retryable error without discarding
  whatever cached results are already displayed" (Edge Cases); the previously-shown `entries` must remain on
  screen underneath the banner.

### Tests for User Story 4

- [X] T038 [P] [US4] `bloc_test` cases in `test/features/records/presentation/bloc/records_bloc_test.dart` —
  contract scenarios #10 (a non-auth criteria-change failure → `entries`/criteria fields unchanged,
  `criteriaLoadFailure` set, `isApplyingCriteria: false`); #11 (an `AuthExpiredFailure` criteria-change failure
  → `reauthRequired` fires, `entries` unchanged, `criteriaLoadFailure` stays `null`); #12
  (`CriteriaLoadRetried` after `criteriaLoadFailure` is set → re-attempts with the same last-applied criteria);
  #13 (`RecordsLocalCacheRefreshed` while `hasAnyActiveCriteria` is true → no-op, state unchanged); #14
  (`RecordsLocalCacheRefreshed` while no criteria active → unchanged RF07 behavior, `cachedEntries` merged in);
  #16 (`CriteriaLoadRetried` succeeds after a prior `criteriaLoadFailure`, simulating reconnection, where some
  cached IDs also appear in the fresh response → emitted `entries` equals the fresh response exactly, no
  duplicate ID — SC-006's automated anchor, since the fetch is a full replace rather than a merge).

**Checkpoint**: All four user stories are independently functional — search, filters, active-filter
visibility/clearing, and offline/failure resilience each work on their own and in combination.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: the FR-009 "no results for this search/filter" state (an edge case shared by every story's
narrowing, not specific to any one of them) and the project's own verification gates (RNF06/RNF07,
quickstart.md).

- [X] T039 [P] Create `lib/features/records/presentation/widgets/no_results_for_criteria_view.dart`
  (FR-009/`contracts/filter-sheet-widget.md`): a `StatelessWidget` with distinct copy/icon from
  `records_empty_state.dart` ("Nenhum resultado para esta busca/filtro" or equivalent prototype-faithful copy)
  plus an `onAdjustPressed` button callback.

- [X] T040 In `lib/features/records/presentation/pages/records_page.dart`'s `_buildLoaded`, branch on
  `loaded.isEmptyForCriteria` (checked before the plain `loaded.isEmpty` branch) to render
  `NoResultsForCriteriaView(onAdjustPressed: () => context.read<RecordsBloc>().add(const
  FiltersAndSearchCleared()))` instead of `RecordsEmptyState` — keeping RF07's account-wide "Nenhum registro
  ainda" empty state reachable only for a true zero-entries account. Depends on T039.

- [X] T041 [P] `bloc_test` case for the zero-result state in
  `test/features/records/presentation/bloc/records_bloc_test.dart` — contract scenario #15: a zero-result
  search/filter combination on a non-empty account yields `isEmptyForCriteria: true`.

- [X] T042 [P] Widget test in `test/features/records/presentation/widgets/no_results_for_criteria_view_test.dart`
  (new file) — contract scenario #9: when `isEmptyForCriteria == true`, `records_page.dart` renders
  `NoResultsForCriteriaView`, not `RecordsEmptyState`. Depends on T040.

- [X] T043 Run `fvm flutter analyze` (RNF06 import-shape lint) and `dart
  test/architecture/no_bloc_imports_bloc_test.dart` plus `test/architecture/domain_purity_test.dart`, confirming
  both continue to pass unmodified — `records_bloc.dart`'s import set gains nothing beyond `dart:async`'s
  `Timer` and this unit's own new `records/domain/entities/*.dart` files (quickstart.md "Automated checks").

- [X] T044 Run `fvm flutter test --coverage`, then `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o
  coverage/domain.info` and `genhtml coverage/domain.info -o coverage/domain-html`; confirm ≥80% domain
  coverage (RNF07 gate) including `date_range_filter.dart`, `active_filter_chip.dart`,
  `EntryMerger.mergeMany()`, and `EntriesRepositoryImpl.search()`'s silent-refresh-and-retry branch.

- [ ] T045 Execute `quickstart.md`'s manual verification walkthrough on a device/Simulator — Stories 1–4 plus
  "Edge cases worth exercising manually at least once" (bounded-mode scroll, mid-flight supersession, zero
  results, `AUTH_EXPIRED` while search/filter active) — using the seeded fixtures and a mixed-source,
  mixed-date test account per quickstart.md's Prerequisites.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: no dependencies — can start immediately. **BLOCKS** every user story phase.
- **User Story 1 (Phase 3)**: depends on Foundational only.
- **User Story 2 (Phase 4)**: depends on Foundational only; independently testable from US1, though
  T027's scenario #5 exercises the combined search+filter path (both already built by Foundational's shared
  `_resolveEntries`).
- **User Story 3 (Phase 5)**: depends on Foundational only; in practice most naturally verified after US2
  (there must be an active filter to see a chip for), but introduces no new code dependency on US1/US2's own
  tasks.
- **User Story 4 (Phase 6)**: depends on Foundational only.
- **Polish (Phase 7)**: depends on all four user stories being complete (FR-009's zero-result state is
  reachable from any of them).

### Within Each Phase

- Tasks touching the *same* file (`records_bloc.dart`, `records_page.dart`) are listed in the sequential order
  they must be applied, even within one user story phase.
- Tasks creating a *new* file with no dependency on that phase's other new files are marked `[P]`.
- Test tasks are marked `[P]` relative to each other (distinct test files); each still depends on its
  corresponding implementation task(s) existing to pass, per that task's own description.

### Parallel Opportunities

- All of T001–T005, T008, T009 (Foundational) can run in parallel — five distinct domain/data/event/state
  files, no cross-dependencies among them.
- T012–T015 (Foundational tests) can all run in parallel once their respective implementation tasks land.
- Within each user story phase, the "new widget file" implementation task (T018, T024, T031, T037, T039) can
  run in parallel with that phase's `records_bloc.dart` handler task(s).
- All test tasks within a single user story phase can run in parallel with each other.

---

## Parallel Example: Foundational Phase

```bash
# Launch the five independent Foundational entities/layers together:
Task: "Add nullable similarity field to Entry in lib/features/entries/domain/entities/entry.dart"
Task: "Create DateRangeOption + boundsAt() in lib/features/records/domain/entities/date_range_filter.dart"
Task: "Create ActiveFilterChip + ActiveFilterChips.derive() in lib/features/records/domain/entities/active_filter_chip.dart"
Task: "Add EntryMerger.mergeMany() in lib/features/records/domain/entities/entry_merger.dart"
Task: "Extend EntriesRepository with list()'s new params + search() in lib/features/entries/domain/repositories/entries_repository.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (the shared bloc/repository machinery — unavoidable before any story works).
2. Complete Phase 3: User Story 1 (live semantic search, debounced, supersession-safe).
3. **STOP and VALIDATE**: seed `seeded-search-entries.md`'s three fixtures, confirm each search term finds its
   entry (SC-001), confirm the debounce behavior (SC-002).
4. Demo/ship if ready — this alone already delivers RF06's "entire premise" (spec.md, User Story 1's "Why
   this priority").

### Incremental Delivery

1. Foundational → User Story 1 (MVP: semantic search alone).
2. + User Story 2 (date-range/entry-type filters, independently and combined with search).
3. + User Story 3 (visible/removable active-filter chips — a usability layer on top of 1 and 2).
4. + User Story 4 (offline/failure resilience — a correctness property layered on top of 1–3).
5. + Polish (FR-009's zero-result state, verification gates).

Each stage adds value without breaking the previous one, matching spec.md's own stated priority order
(P1, P1, P2, P3).
