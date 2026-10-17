# Implementation Plan: P-RF07 — Multi-source history (timeline)

**Branch**: `005-multi-source-timeline` (spec directory only — no git branch exists; see spec.md header)

**Date**: 2026-10-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-multi-source-timeline/spec.md`, `docs/input/requirements.md`
§1 (RF07), §6.1/§6.2 (`/auth/session`, `/auth/refresh`, `/entries`, `/entries/:id`), §8 (data model), §9, §13;
`docs/input/backend/sync-badge.md`; `docs/input/backend/api/openapi.yaml`'s `/entries` and `/entries/{id}`
schemas; `docs/input/prototype/prototype-extract.md` §§2.4, 3, 4, 6; and `.specify/memory/constitution.md`.
Depends on F000 (`specs/001-foundation/`) and RF01 (`specs/003-multimodal-capture/`), both already
implemented — this is the first unit to make the already-built `SessionBloc`/overlay machinery and
`EntriesRepository`/`cachedEntries` seam actually earn their keep from outside `session/`/`capture/`.

## Summary

"Meus Registros" fetches and displays every one of the signed-in user's journal entries — manual, audio,
photo, and (origin-agnostically) chat — in one reverse-chronological, date-grouped, infinitely-scrolling
timeline, each card carrying a per-entry synchronization badge computed purely on-device. It reuses RF01's
`Entry`/`EntriesRepository`/`CreateEntryUseCase` (extended with two new read methods and a fourth
`EntrySource` value, never replaced) and F000's `SessionBloc`/"Sessão expirada" overlay (extended with its
first real caller, never modified) rather than building either from scratch. The screen's own new code is a
single `RecordsBloc` (depending only on `EntriesRepository`) plus a small amount of pure domain logic
(date-grouping, local-cache/fetched-page merge-by-ID, sync-badge derivation) — the one piece of genuine new
architecture this unit introduces is *how* a session expiring mid-browse reaches the existing, unmodified
overlay without one BLoC ever importing another (research.md R4/R5): the silent refresh-and-retry lives
inside `EntriesRepositoryImpl` (reusable by any future authenticated entries read), and the final "I could not
renew, please show the overlay" signal crosses from `RecordsBloc` to the app-wide `SessionBloc` through a
one-shot stream consumed by the page widget — never by one bloc holding a reference to the other.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000/RF03/RF01/RF02.

**Primary Dependencies**: No additions (research.md R9 explicitly rejects adding `intl`). Reuses the full
existing stack — `flutter_bloc`, `fpdart`, `get_it`, `equatable`, `dio` (via `ApiClient`, extended with
`queryParameters` support — research.md R1), `go_router`; dev-only `mocktail`, `bloc_test`.

**Storage**: No new persistence. `EntriesRepositoryImpl.cachedEntries` (RF01's existing in-memory
`get_it` `lazySingleton` list) is read, never written, by this unit — this is the "local entries store" RF01
documented as existing "for later units ... to read." No local database, no new secure-storage key.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter (RNF07), now exercising
`entry_merger.dart`/`date_group.dart`/`sync_badge_state.dart` (all pure, trivially testable) and
`EntriesRepositoryImpl.list()`/`.getById()`'s silent-refresh-and-retry branches. One new architecture test
(`test/architecture/no_bloc_imports_bloc_test.dart`, for `/speckit-tasks` to schedule) mechanically checks
requirements.md RF07's own "no BLoC imports another BLoC directly" acceptance criterion, mirroring the
existing `domain_purity_test.dart`'s shape.

**Target Platform**: iOS, portrait only — unchanged. No native project file touched.

**Project Type**: Same single Flutter mobile app. One feature folder gains real content for the first time:
`lib/features/records/` (today holding only `RecordsPlaceholderPage`, F000's navigable stub — research.md
R8 keeps this name rather than introducing a parallel `timeline/`). `lib/features/entries/` (RF01) and
`lib/features/session/` (F000) are both extended in place, not forked or duplicated. No backend/server code,
no change to `docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 unchanged — any page fetch exceeding 300 ms shows a loading affordance (the
initial `RecordsLoading` state's spinner; `RecordsLoaded.isLoadingMore`'s bottom-of-list spinner for further
pages). Scroll-triggered pagination is a local `ScrollController` threshold check (<100 ms, RNF01) that only
*dispatches* a fetch, never blocks the scroll itself.

**Constraints**:
- No RF04/RF05/RF06/RF08/RF09/RF10 behavior, no extension feature (FR-010) — the header's download icon and
  the search bar/funnel button are rendered but inert (FR-008).
- No backend/contract/config change (FR-011) — `queryParameters` support (research.md R1) is a change to
  this app's own `ApiClient` wrapper, not to any backend function or its contract.
- Clean Architecture, 3 layers per feature (Principle V) — `records/` has no `data/` folder (research.md R8,
  mirroring `home/`'s existing partial-layer shape) since it introduces no data source/repository of its own.
- "No BLoC imports another BLoC directly" (requirements.md RF07's own acceptance criterion) — `RecordsBloc`
  depends only on `EntriesRepository`; the one cross-cutting touch point (`AuthExpiredDetected` into
  `SessionBloc`) lives in `RecordsPage`, a widget, not a BLoC (research.md R5, data-model.md, contracts/
  records-bloc.md).
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — every color this
  unit needs (origin spines/icons, sync-badge dots) already exists in the token scale (data-model.md's
  mapping tables); zero new color tokens.

**Scale/Scope**: 1 feature folder filled in (`records/`, replacing its placeholder page); 2 new domain
entities + 2 pure-function helper classes (`EntriesPage`, `SyncBadgeState`/`SyncBadge`,
`DateGroup`/`DateGrouper`, `EntryMerger`); 1 new bloc (`RecordsBloc`, 4 events, 3 state subtypes); 4 new
presentation widgets/pages; 2 new `EntriesRepository` methods (+ remote-data-source/repository-impl support);
1 `ApiClient` parameter addition; 1 `EntrySource` enum value addition; 1 shared helper extracted
(`openInsertionModal()`, research.md R10) with its one existing call site (`home_chat_shell_page.dart`)
updated to use it; 2 DI registrations updated/added.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only. The genuinely silent spots this unit resolves by reasonable technical judgment — where the AUTH_EXPIRED silent-refresh-and-overlay-trigger plumbing lives given "no BLoC imports another BLoC" (research.md R4/R5), why `GET /entries/:id` ends up with no call site despite being a named dependency (R7), why the sync badge's other two states are correctly implemented but unreachable today (R6) — are each built directly on spec.md's own already-resolved Clarifications and Assumptions, not reopening them. |
| II. Fixed Technology Stack | PASS | No new package; `flutter_bloc`/`fpdart`/Clean Architecture unchanged. |
| III. Backend Boundary | PASS | Only already-contracted functions called (`entries-list`, `entries-get`, reusing `auth-session`/`auth-refresh` as-is); `ApiClient`'s `queryParameters` addition is this app's own HTTP wrapper, not the backend's contract. |
| IV. Design Token Discipline & Visual Fidelity | PASS | Every color this unit renders (4 origin spines/icons, 3 sync-badge states) already exists in `DesignTokens` (data-model.md's mapping tables, sourced from the prototype's own `sourceMeta`/`syncMeta` JS, not invented) — zero new color tokens. |
| V. Clean Architecture Folder Convention | PASS | `RecordsBloc`/domain helpers import only `fpdart`, `equatable`, `core/network/failure.dart`, and existing domain types — no `package:flutter`, no `data/` class, confirmed by the existing `domain_purity_test.dart` plus this unit's own new `no_bloc_imports_bloc_test.dart`. |
| RNF01 (latency) | PASS | Unchanged thresholds; new loading affordances (`RecordsLoading`, `isLoadingMore`) follow the same 300 ms rule. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF07 | Backend-side, unaffected. |
| RNF05 (hard delete) | N/A to RF07 | Belongs to Settings/RF09. |
| RNF06 (layer violations) | PASS | No domain file imports Flutter or a `data/` class; `RecordsBloc` imports no other feature's bloc (the new architecture test makes this mechanically checked, not just asserted). |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `EntryMerger`/`DateGrouper`/`SyncBadge` are pure, total functions — as directly testable as anything RF01/RF02 shipped; `EntriesRepositoryImpl`'s new silent-refresh-and-retry branches are testable against `mocktail` fakes of `SessionRepository`/`EntriesRemoteDataSource` — see contracts/ scenario tables. |
| RNF08 (visual fidelity) | PASS | Record card, empty state, and sync badge match prototype-extract.md §2.4/§6 exactly — spine/icon colors and sync-dot colors pulled from the prototype's own `sourceMeta`/`syncMeta` data, not approximated. |
| RNF09 (Either + 15/15 error scenarios) | N/A new count to RF07 | RF07 adds two **read** endpoints, not write endpoints — RNF09's "5 write endpoints × 3 failures" count is unaffected (still RF01/RF02's `entries-create`/`media-ocr`, 6/15 cumulative); `list()`/`getById()` still return `Either<Failure, T>` (Principle II/Constitution-wide pattern) and are tested for their own 3 failure shapes regardless, just outside RNF09's specific write-endpoint tally. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/005-multi-source-timeline/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── entries-repository-extension.md
│   └── records-bloc.md
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
└── lib/
    ├── core/
    │   ├── network/
    │   │   └── api_client.dart                              # + queryParameters param (research.md R1)
    │   ├── routing/
    │   │   └── app_router.dart                               # AppRoutes.records now builds RecordsPage + BlocProvider<RecordsBloc>
    │   └── di/
    │       └── service_locator.dart                          # EntriesRepositoryImpl gains SessionRepository dep; + RecordsBloc registration
    ├── features/
    │   ├── entries/
    │   │   ├── domain/
    │   │   │   ├── entities/
    │   │   │   │   ├── entry.dart                            # EntrySource + chat (research.md R2)
    │   │   │   │   └── entries_page.dart                     # NEW
    │   │   │   └── repositories/
    │   │   │       └── entries_repository.dart                # + list(), getById()
    │   │   └── data/
    │   │       ├── entries_remote_data_source.dart            # + list(), getById()
    │   │       └── entries_repository_impl.dart               # + SessionRepository dep, silent-refresh-and-retry
    │   ├── capture/
    │   │   └── presentation/
    │   │       └── widgets/
    │   │           └── open_insertion_modal.dart               # NEW — extracted from home_chat_shell_page.dart (research.md R10)
    │   ├── home/
    │   │   └── presentation/
    │   │       └── pages/
    │   │           └── home_chat_shell_page.dart               # "+" button now calls the shared openInsertionModal()
    │   ├── session/                                            # UNCHANGED — SessionBloc/AuthExpiredDetected/overlay all reused as-is
    │   └── records/
    │       ├── domain/
    │       │   └── entities/
    │       │       ├── sync_badge_state.dart                   # NEW
    │       │       ├── date_group.dart                         # NEW
    │       │       └── entry_merger.dart                       # NEW
    │       └── presentation/
    │           ├── bloc/
    │           │   ├── records_event.dart                      # NEW
    │           │   ├── records_state.dart                      # NEW
    │           │   └── records_bloc.dart                       # NEW
    │           ├── pages/
    │           │   ├── records_page.dart                       # NEW — replaces records_placeholder_page.dart
    │           │   └── records_placeholder_page.dart            # DELETED
    │           └── widgets/
    │               ├── record_card.dart                         # NEW
    │               ├── records_empty_state.dart                 # NEW
    │               └── sync_badge_dot.dart                      # NEW
    └── (capture/, vault/, auth/, splash/ — unchanged otherwise)
```

**Structure Decision**: Fills in the existing `records/` placeholder feature (research.md R8) rather than
introducing a new `timeline/` feature; extends `entries/` and `core/network`/`core/di` in place; makes one
small, genuinely new cross-feature wire (the `reauthRequired` one-shot stream into the page, research.md R5)
rather than touching `session/`'s already-built, already-correct machinery at all.

## Complexity Tracking

*No entries — this unit adds no new dependency and no new feature folder (reuses `records/`); its one
cross-cutting concern (reaching the existing session-expired overlay without bloc-to-bloc coupling) is solved
with a one-shot stream pattern already proven in this codebase (`InsertionModalBloc.closeRequests`), not a
new kind of architectural seam.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `RecordsBloc` and every `records/domain/` file were re-checked against their actual planned imports:
  `fpdart`, `equatable`, `core/network/failure.dart`, `entries/domain/entities/entry.dart`,
  `entries/domain/repositories/entries_repository.dart` — no `package:flutter`, no `data/` class, no other
  feature's `presentation/bloc/` path. RNF06/Principle V confirmed before any code exists.
- `EntriesRepositoryImpl`'s new `SessionRepository` dependency was re-checked against RNF06: it is a
  `data/`-to-`domain/` cross-feature dependency (the same shape `SessionRepositoryImpl` → `auth`'s `Account`
  already has), never a `data/`-to-`data/` or `data/`-to-`presentation/` one — no violation.
- The one place `SessionBloc` is imported outside `session/` (`records_page.dart`) was re-checked against
  requirements.md RF07's literal wording ("No BLoC imports another BLoC directly") — `RecordsPage` is a
  `State<StatefulWidget>`, not a `Bloc` subclass, so this holds literally, not just in spirit. This mirrors
  `main.dart`'s and `session_expired_overlay.dart`'s own existing, already-shipped pattern of a *widget*
  (never a bloc) being the thing that reads one feature's bloc stream and dispatches into another's.
- Re-checked R7's "no call site for `getById()`" conclusion against `requirements.md` §9 ("Entries are
  immutable: there is no `PATCH /entries/:id` or `DELETE /entries/:id`") and found it still holds: nothing in
  this design ever produces a locally-pending/failed write for an entry this unit can display, so no
  reconciliation trigger exists to wire up — confirmed not an oversight, documented as a deliberate, narrow
  scope boundary. This resolves spec.md Clarification 2's own illustrative example ("after the Sessão
  expirada overlay is dismissed and the session is renewed") as a description of `getById()`'s intended
  future purpose, not a call site this unit implements.
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file,
  or any AI provider — Principle III remains intact.

No new violations. Gate remains PASS.
