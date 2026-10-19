# Implementation Plan: P-RF06 — Semantic search / filter

**Branch**: `006-semantic-search-filter` (spec directory only — no git branch exists; none of this repo's
extension hooks are configured, per spec.md's own header)

**Date**: 2026-10-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-semantic-search-filter/spec.md`, `docs/input/requirements.md`
§1 (RF06), §6.4 (`GET /entries/search`), §6.2 (`GET /entries`), §8, §9, §10 (300 ms debounce), §13;
`docs/input/backend/api/openapi.yaml`'s `/entries` and `/entries/search` schemas; `docs/input/backend/fixtures/
seeded-search-entries.md`; `docs/input/prototype/prototype-extract.md` §2.4 ("Tela 4 — Meus Registros", "Sheet
de filtro", "Filtros ativos"); and `.specify/memory/constitution.md`. Depends on RF07
(`specs/005-multi-source-timeline/`), already implemented — this is the unit that makes RF07's own inert
search bar and funnel button on "Meus Registros" actually do something.

## Summary

"Meus Registros" gains a live semantic search bar (`GET /entries/search`'s `q`, 300 ms debounced) and a filter
sheet (date-range + entry-type, mapped to `GET /entries`'/`GET /entries/search`'s shared `dateFrom`/`dateTo`/
`source` parameters), both narrowing the same `RecordsLoaded` list RF07 already renders. No new screen, no new
bloc: the already-built `RecordsBloc` is extended in place with six new events (`SearchTextChanged`,
`FilterSheetApplied`, `FilterChipRemoved`, `FiltersAndSearchCleared`, `CriteriaLoadRetried`, and an internal
`SearchDebounceElapsed`) and five new `RecordsLoaded` fields (the currently-applied
`searchQuery`/`dateRange`/`entryTypes`, plus `isApplyingCriteria`/`criteriaLoadFailure`), because
the two things RF06 must guarantee — "a new action supersedes any in-flight earlier one" (FR-005a) and "AND
across axes, OR within the entry-type axis" (FR-005) — both need a single, already-serialized owner of
"what the current criteria is and which fetch is the latest one," which is exactly what one bloc already is.
`EntriesRepository.list()` gains optional `source`/`dateFrom`/`dateTo`/`limit` parameters (additive, RF07's own
cursor-pagination callers unaffected) and gains a new `search()` method (`GET /entries/search`, bounded,
no cursor — FR-005b). Multi-select entry types (`source` is single-valued; FR-003/FR-005's resolved
Clarification) fan out one repository call per selected type and merge+dedupe+re-sort the results with a new
`EntryMerger.mergeMany()` — the same dedupe-by-ID idea RF07's `EntryMerger.merge()` already implements,
extended to N equal-weight sources instead of a primary/secondary pair. The one genuinely new domain concept
this unit introduces is `DateRangeOption` (a pure, testable date-range → `dateFrom`/`dateTo` mapping) and
`ActiveFilterChip` (a pure derivation of which removable chips the screen shows) — both total functions with
zero I/O, directly unit-testable like every other `records/domain/` helper RF07 already shipped.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000/RF01/RF02/RF03/RF07.

**Primary Dependencies**: No additions. Reuses the full existing stack — `flutter_bloc`, `fpdart`, `get_it`,
`equatable`, `dio` (via `ApiClient`), `go_router`; dev-only `mocktail`, `bloc_test`. The 300 ms debounce is
implemented with a plain `dart:async` `Timer` inside `RecordsBloc` (the same primitive
`login_signup_page.dart` already uses for its own 300 ms RNF01 loading-indicator delay) — research.md R4
explicitly rejects adding `rxdart`/`bloc_concurrency` for this, since a single `Timer` + a monotonic
generation counter already gives both the debounce and the request-supersession guarantee FR-002/FR-005a need.

**Storage**: No new persistence. "Offline shows cached results" (FR-010/User Story 4) falls out of the
existing pattern RF07's `_fetchNextPage` failure branch already established — a failed fetch never clears
`RecordsLoaded.entries` — extended here to every new fetch path this unit adds (research.md R7). No local
database, no new secure-storage key, no new in-memory store beyond the `RecordsLoaded` fields already planned.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter (RNF07), now exercising
`date_range_filter.dart`/`active_filter_chip.dart`/`EntryMerger.mergeMany()` (all pure) and
`EntriesRepositoryImpl.search()`'s silent-refresh-and-retry branch. `RecordsBloc`'s debounce `Duration` is an
injectable constructor parameter (default 300 ms, research.md R4) so tests pass `Duration.zero` instead of
waiting on a real timer. No new architecture test is needed — `no_bloc_imports_bloc_test.dart` (RF07) already
covers every file this unit touches.

**Target Platform**: iOS, portrait only — unchanged. No native project file touched.

**Project Type**: Same single Flutter mobile app. `lib/features/records/` (RF07) gains new domain entities and
presentation widgets but no `data/` folder of its own (unchanged from RF07 — it still introduces no data
source/repository of its own, research.md R1 of RF07's plan, reaffirmed here). `lib/features/entries/` (RF01/
RF07) is extended in place with `search()`. No backend/server code, no change to
`docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 unchanged. The 300 ms search debounce is this unit's own fixed parameter
(requirements.md §10), distinct from but implemented with the same `Timer` primitive as RNF01's "loading
indicator after 300 ms" rule; a criteria-change fetch that takes longer than 300 ms shows an inline loading
affordance near the search/filter UI (a new `RecordsLoaded.isApplyingCriteria` flag), mirroring RF07's existing
`isLoadingMore` pattern rather than inventing a new one.

**Constraints**:
- No RF04/RF05/RF08/RF09/RF10 behavior, no extension feature (FR-011) — the header's download icon stays
  inert (unchanged from RF07/FR-008); the "CATEGORIA" chip group is rendered but never filters or reaches the
  backend (FR-004).
- No backend/contract/config change (FR-011) — `EntriesRemoteDataSource.search()`/`.list()`'s new query
  parameters are this app's own typed wrapper around parameters `GET /entries`/`GET /entries/search` already
  both accept per the OpenAPI contract; nothing new is sent that the contract doesn't already define.
- Clean Architecture, 3 layers per feature (Principle V) — every new `records/domain/` file imports only
  `fpdart`/`equatable`/`entries/domain/entities/entry.dart`, same shape as RF07's existing domain helpers;
  `RecordsBloc` still depends only on `EntriesRepository`, never `SessionRepository`/`ConnectivityChecker`/
  `SessionBloc` (unchanged from RF07, reaffirmed below).
- "A new search, filter change, or clear action supersedes any in-flight earlier request" (FR-005a) — a single
  monotonic `_fetchGeneration` counter inside `RecordsBloc`, checked after every `await`, before every `emit`
  (research.md R6) — not a cancellation token, not a stream-transformer library.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — the filter sheet
  and active-filter chips reuse existing tokens only (data-model.md's mapping table); zero new color tokens.

**Scale/Scope**: 1 feature folder extended (`records/`, no new feature folder); 2 new pure domain entities
(`DateRangeOption`/`date_range_filter.dart`, `ActiveFilterChip`/`active_filter_chip.dart`) + 1 extended domain
helper (`EntryMerger.mergeMany()`); 1 extended bloc (`RecordsBloc`: +6 events, +5 `RecordsLoaded` fields); 3 new
presentation widgets (`filter_sheet.dart`, `active_filter_chips_row.dart`, `no_results_for_criteria_view.dart`)
+ 2 widgets made live (`_SearchBar`'s `TextField`/funnel button in `records_page.dart`, previously `enabled:
false`/inert `onPressed: () {}`); 1 `EntriesRepository` method added (`search()`) + 1 extended (`list()`'s new
optional params); 1 `Entry` field added (`similarity`, nullable, defaults `null` for every non-search
response — research.md R3); 1 DI registration unchanged (`RecordsBloc`'s factory keeps the same single
dependency).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only. The spots this unit resolves by reasonable technical judgment rather than reopening spec.md's own already-resolved Clarifications — whether a multi-type filter-only (no-query) combination keeps RF07's cursor pagination or becomes a bounded one-shot merge like search mode (research.md R1), how `DateRangeOption`'s bounds are computed from "now" (R2), why `Entry` gains a nullable `similarity` field rather than a parallel entity (R3), why the debounce needs no new dependency (R4), how `RecordsLocalCacheRefreshed` behaves once criteria exist (R5), the generation-counter mechanics for FR-005a (R6), and why "offline shows cached results" needs no new code (R7) — are each built directly on spec.md's own Clarifications/Assumptions/FR wording, not reopening them. |
| II. Fixed Technology Stack | PASS | No new package; `flutter_bloc`/`fpdart`/Clean Architecture unchanged. |
| III. Backend Boundary | PASS | Only already-contracted functions called (`entries-search`, reusing `entries-list` with its own already-documented `source`/`dateFrom`/`dateTo` parameters) — no parameter sent that `docs/input/backend/api/openapi.yaml` doesn't already define for these two operations. |
| IV. Design Token Discipline & Visual Fidelity | PASS | The filter sheet, active-filter chips, and "no results" view reuse existing `DesignTokens` entries only (data-model.md's mapping table, sourced from prototype-extract.md §2.4's own described layout) — zero new color/spacing/radius tokens. |
| V. Clean Architecture Folder Convention | PASS | Every new/changed `records/domain/` file imports only `fpdart`, `equatable`, and `entries/domain/entities/entry.dart` — no `package:flutter`, no `data/` class; confirmed against the existing `domain_purity_test.dart`. `RecordsBloc` adds no new dependency beyond the `EntriesRepository` it already had. |
| RNF01 (latency) | PASS | The 300 ms search debounce is requirements.md's own fixed parameter, not a performance budget this unit invents; criteria-change fetches exceeding 300 ms show `isApplyingCriteria`'s loading affordance, same threshold RNF01 already requires app-wide. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF06 | Backend-side, unaffected — this unit adds no write endpoint. |
| RNF05 (hard delete) | N/A to RF06 | Belongs to Settings/RF09. |
| RNF06 (layer violations) | PASS | No domain file imports Flutter or a `data/` class; `RecordsBloc` still imports no other feature's bloc — `no_bloc_imports_bloc_test.dart` (RF07) continues to pass unmodified. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `date_range_filter.dart`/`active_filter_chip.dart`/`EntryMerger.mergeMany()` are pure, total functions — as directly testable as every other `records/domain/` helper RF07 shipped; `EntriesRepositoryImpl.search()`'s silent-refresh-and-retry branch is testable against the same `mocktail` fakes RF07's `list()`/`getById()` tests already use. |
| RNF08 (visual fidelity) | PASS | Filter sheet groups ("INTERVALO DE DATA"/"CATEGORIA"/"TIPO DE ENTRADA"), active-filter chips, and funnel button's filled state match prototype-extract.md §2.4 exactly — no approximated layout or invented chip style. |
| RNF09 (Either + 15/15 error scenarios) | N/A new count to RF06 | RF06 adds one more **read** endpoint (`entries-search`) and extends another (`entries-list`) — RNF09's "5 write endpoints × 3 failures" tally is unaffected (still RF01/RF02's two write endpoints, 6/15 cumulative); `search()`/`list()` still return `Either<Failure, T>` (Principle II) and are tested for their own 3 failure shapes regardless, outside RNF09's specific write-endpoint count. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/006-semantic-search-filter/
├── plan.md               # This file
├── research.md           # Phase 0 output
├── data-model.md          # Phase 1 output
├── quickstart.md          # Phase 1 output
├── contracts/              # Phase 1 output
│   ├── entries-repository-search-extension.md
│   ├── records-bloc-extension.md
│   └── filter-sheet-widget.md
└── tasks.md                # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
└── lib/
    └── features/
        ├── entries/
        │   ├── domain/
        │   │   ├── entities/
        │   │   │   └── entry.dart                                  # + similarity (nullable, research.md R3)
        │   │   └── repositories/
        │   │       └── entries_repository.dart                      # list() + source/dateFrom/dateTo/limit; + search()
        │   └── data/
        │       ├── entries_remote_data_source.dart                  # list()/search() query params; similarity parsing
        │       └── entries_repository_impl.dart                     # search() gets the same silent-refresh-and-retry as list()
        └── records/
            ├── domain/
            │   └── entities/
            │       ├── date_range_filter.dart                       # NEW — DateRangeOption + boundsAt()
            │       ├── active_filter_chip.dart                      # NEW — ActiveFilterChip + ActiveFilterChips.derive()
            │       └── entry_merger.dart                            # + mergeMany() (merge() untouched)
            └── presentation/
                ├── bloc/
                │   ├── records_event.dart                           # + SearchTextChanged, FilterSheetApplied,
                │   │                                                 #   FilterChipRemoved, FiltersAndSearchCleared,
                │   │                                                 #   CriteriaLoadRetried, SearchDebounceElapsed
                │   │                                                 #   (internal)
                │   ├── records_state.dart                           # RecordsLoaded + searchQuery/dateRange/entryTypes/
                │   │                                                 #   isApplyingCriteria/criteriaLoadFailure
                │   └── records_bloc.dart                            # + 6 handlers, debounce Timer, generation counter
                ├── pages/
                │   └── records_page.dart                            # _SearchBar made live; funnel opens FilterSheet
                └── widgets/
                    ├── filter_sheet.dart                             # NEW — "Sheet de filtro" (date range + entry
                    │                                                 #   type + inert category chips, Aplicar/Limpar)
                    ├── active_filter_chips_row.dart                  # NEW — "Filtros ativos" row + "Limpar filtros"
                    └── no_results_for_criteria_view.dart             # NEW — distinct from records_empty_state.dart
```

**Structure Decision**: Extends `records/` and `entries/` in place (same two feature folders RF07 already
filled in) — no new feature folder, no new bloc, no new repository. The one new cross-cutting concern this
unit introduces (FR-005a's request-supersession rule) is solved inside the one bloc that already owns "what
the screen is currently showing," not with a new architectural seam.

## Complexity Tracking

*No entries — this unit adds no new dependency and no new feature folder; its two genuinely new mechanisms
(the generation counter for request supersession, and the per-type fan-out-and-merge for multi-select entry
types) are both already-proven patterns in this codebase (RF07's own `EntryMerger`, extended rather than
duplicated) or small enough to need no justification beyond this plan's own research.md.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `date_range_filter.dart`, `active_filter_chip.dart`, and `EntryMerger.mergeMany()` were re-checked against
  their actual planned imports: `equatable`, `entries/domain/entities/entry.dart` only (`date_range_filter.dart`
  imports neither — it is pure `DateTime` arithmetic). No `package:flutter`, no `data/` class — RNF06/Principle
  V confirmed before any code exists.
- `RecordsBloc`'s new dependency surface was re-checked: still exactly one constructor dependency
  (`EntriesRepository`) plus a plain `Duration` value (the debounce window) — no `SessionRepository`, no
  `ConnectivityChecker`, no `SessionBloc` import added. The one new `dart:async` `Timer` field is a private
  implementation detail of the bloc itself, not a new dependency.
- Re-checked `EntriesRepositoryImpl.search()`'s retry branch against the exact shape `list()`/`getById()`
  (RF07) already established (`_retryAfterSilentRefresh`) — reused verbatim, no new retry logic duplicated.
- Re-checked the "CATEGORIA" chip group's placement: it lives entirely inside `filter_sheet.dart`
  (presentation), with no backing domain entity and no field anywhere in `RecordsEvent`/`RecordsState` —
  confirming FR-004's "rendered for visual fidelity... MUST NOT... send any category-related parameter" holds
  by construction (there is nothing to send because nothing stores its selection past the sheet's own local
  `setState`).
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file,
  or any AI provider — Principle III remains intact.

No new violations. Gate remains PASS.
