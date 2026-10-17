---

description: "Task list for P-RF07 — Multi-source history (timeline)"
---

# Tasks: P-RF07 — Multi-source history (timeline)

**Input**: Design documents from `/specs/005-multi-source-timeline/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. RNF07 (`lib/**/domain/**` ≥80% coverage) is carried into this unit's Constitution
Check as "PASS (gate carried into tasks)", and both `contracts/entries-repository-extension.md` and
`contracts/records-bloc.md` each define an explicit scenario table "for `/speckit-tasks` to
schedule" — so test tasks are generated alongside implementation, matching RF01/RF02/RF03's existing
`bloc_test`/`mocktail` style exactly.

**Organization**: Tasks are grouped by user story (US1–US4, spec.md priorities P1/P1/P2/P3). Per
contracts/records-bloc.md, `RecordsBloc` and `RecordsPage` are each extended incrementally across
several stories (same convention RF02's own tasks.md used for the shared `InsertionModalBloc`) — "independent" here means each story's acceptance scenarios can be exercised and automated-tested on
their own once the prior stories it builds on exist, not that each story gets its own bloc or page.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 (seeing every entry, regardless of origin), US2 (starting from nothing /
  empty state), US3 (session expires while browsing), US4 (the sync badge tells the truth during
  session trouble)

## Path Conventions

Single Flutter project (F000/RF01/RF03's existing `lib/`, `test/`) — see plan.md Project Structure.
This unit fills in the already-existing `lib/features/records/` placeholder feature folder and
extends `lib/features/entries/`, `lib/core/network/`, `lib/core/di/`, `lib/core/routing/`, and
`lib/features/capture/presentation/widgets/` in place; no new top-level directory.

---

## Phase 1: Setup

**Purpose**: Project initialization — N/A for this unit.

No setup tasks apply. This unit adds no new package, no native-project change, and no new `.env`
variable — it reuses the full existing stack as-is (plan.md Technical Context, Primary
Dependencies: "No additions"; research.md R9 explicitly rejects adding `intl`). Proceed directly to
Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The `entries/` extensions every story's data ultimately flows through
(`ApiClient.queryParameters`, `EntrySource.chat`, `EntriesPage`, `EntriesRepository.list()`/
`.getById()` with silent-refresh-and-retry), plus the three pure `records/domain/` helpers
(`SyncBadge`, `DateGrouper`, `EntryMerger`) every story's presentation layer calls. No UI exists yet
after this phase — `RecordsBloc`/`RecordsPage` are built starting in User Story 1.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T001 [P] Add a `Map<String, dynamic>? queryParameters` parameter to `ApiClient.call()` in `lib/core/network/api_client.dart`, passed straight through to `Dio.request()`'s own `queryParameters` argument (research.md R1); every existing call site (`entries-create`, `auth-session`, `auth-refresh`, `media-ocr`) omits it and is byte-for-byte unaffected (contracts/entries-repository-extension.md)
- [X] T002 [P] Change `enum EntrySource { manual, audio, photo }` to `enum EntrySource { manual, audio, photo, chat }` in `lib/features/entries/domain/entities/entry.dart`, replacing the stale doc comment ("`chat` is RF10's own addition — this unit creates only these three") with one explaining that `chat` exists so a `GET /entries`-returned chat-origin entry parses and renders instead of throwing `ArgumentError` out of `EntrySource.values.byName(...)` (research.md R2, spec.md Edge Cases)
- [X] T003 [P] Create `EntriesPage` in `lib/features/entries/domain/entities/entries_page.dart`: an `Equatable` class with `final List<Entry> entries` (the order the backend returns, newest-occurred-first) and `final String? nextCursor` (`null` means the last page) — the shape of one `GET /entries` response minus `meta.total` and the `source`/`dateFrom`/`dateTo` filter params reserved for RF06 (data-model.md)
- [X] T004 Extend the `EntriesRepository` abstract class in `lib/features/entries/domain/repositories/entries_repository.dart` with `Future<Either<Failure, EntriesPage>> list({String? cursor})` and `Future<Either<Failure, Entry>> getById(String id)`; `create()`/`cachedEntries` stay unchanged (contracts/entries-repository-extension.md) — depends on T002, T003
- [X] T005 Extend `EntriesRemoteDataSource` in `lib/features/entries/data/entries_remote_data_source.dart`: keep the existing private `_parseEntry(Map<String, dynamic>)` (used by `create()`) reusable as-is for a single object; add `Future<Either<Failure, EntriesPage>> list({String? cursor})` calling `_apiClient.call('entries-list', method: 'GET', queryParameters: cursor == null ? null : {'cursor': cursor})` and parsing the result through a new private `_parseEntriesPage` (each element of `data` through `_parseEntry`, plus `meta.nextCursor`, with no duplicated per-entry parsing logic); add `Future<Either<Failure, Entry>> getById(String id)` calling `_apiClient.call('entries-get', method: 'GET', pathSegments: [id]).flatMap(_parseEntry)`; malformed-response `TypeError`/`FormatException` map to `ValidationFailure` for both new methods, exactly like `create()`'s existing catch clauses (contracts/entries-repository-extension.md) — depends on T001, T002, T004
- [X] T006 Extend `EntriesRepositoryImpl` in `lib/features/entries/data/entries_repository_impl.dart`: add a `SessionRepository` constructor dependency (`session/domain/repositories/session_repository.dart` — a cross-feature *domain*-interface dependency, the same shape `SessionRepositoryImpl` already has on `auth`'s `Account`, research.md R4); add a private `Future<Either<Failure, T>> _retryAfterSilentRefresh<T>(Future<Either<Failure, T>> Function() retry)` helper that calls `_sessionRepository.refresh()` and, on `Left`, returns `Left(const AuthExpiredFailure(message: 'Session could not be renewed', requestId: ''))` (a fresh instance regardless of the refresh attempt's own failure shape), or on `Right`, calls `retry()` exactly once (no loop, no second refresh attempt); implement `list({String? cursor})`/`getById(String id)` as: call the matching remote-data-source method once, and when it comes back `Left(AuthExpiredFailure)` route through `_retryAfterSilentRefresh`, otherwise return the `Left`/`Right` unchanged; `create()`/`cachedEntries` are untouched (contracts/entries-repository-extension.md) — depends on T004, T005
- [X] T007 Update `lib/core/di/service_locator.dart`'s `EntriesRepositoryImpl` registration to inject `sessionRepository: getIt<SessionRepository>()` (already registered earlier in the file for `SessionBloc`) — depends on T006
- [X] T008 [P] Extend `test/features/entries/data/entries_remote_data_source_test.dart` with `list()`/`getById()` coverage per contracts/entries-repository-extension.md's scenario table: `list(cursor: 'abc')` sends `queryParameters: {'cursor': 'abc'}` to `ApiClient.call`; `list()` with no cursor sends `queryParameters: null`; a response containing a `chat`-sourced entry parses to `EntrySource.chat` without throwing (research.md R2); a malformed response for either new method maps to `ValidationFailure` — depends on T005
- [X] T009 [P] Extend `test/features/entries/data/entries_repository_impl_test.dart` with `list()`/`getById()` coverage per contracts/entries-repository-extension.md's scenario table, against a `mocktail` fake `SessionRepository` and fake `EntriesRemoteDataSource`: success on the first attempt returns `Right` with no refresh call made; `AuthExpiredFailure` followed by a successful refresh retries and returns `Right`, with exactly 2 remote calls and 1 refresh call; `AuthExpiredFailure` followed by a refresh that itself fails returns `Left(AuthExpiredFailure)` with no second refresh attempt; any other failure code (timeout/offline/validation/...) passes through as `Left(<that failure>)` unchanged with no refresh attempted — depends on T006
- [X] T010 [P] Extend `test/core/network/api_client_test.dart` confirming `call()`'s new `queryParameters` argument reaches the underlying `Dio.request()` call verbatim when provided, and is omitted (`null`) when not provided — depends on T001
- [X] T011 [P] Create `SyncBadgeState`/`LocalWriteOutcome` enums and the pure, total `SyncBadge.derive(LocalWriteOutcome? localWrite)` static method in `lib/features/records/domain/entities/sync_badge_state.dart` (data-model.md): `null` → `SyncBadgeState.synchronized`, `LocalWriteOutcome.pending` → `synchronizing`, `LocalWriteOutcome.failed` → `error` — the function takes no session/auth-related input at all, trivially satisfying FR-005's independence requirement (research.md R6)
- [X] T012 [P] Create `test/features/records/domain/entities/sync_badge_state_test.dart` covering `SyncBadge.derive`'s 3 branches (`null`/`pending`/`failed` → `synchronized`/`synchronizing`/`error`) — depends on T011
- [X] T013 [P] Create `DateGroup`/`DateGrouper` in `lib/features/records/domain/entities/date_group.dart` (data-model.md): `DateGroup` is an `Equatable` with `final String label` and `final List<Entry> entries`; `DateGrouper.group(List<Entry> entries, {DateTime? now})` buckets entries by comparing each one's `occurredAt.toLocal()` calendar day against `(now ?? DateTime.now()).toLocal()`'s — "Hoje" for today, "Ontem" for yesterday, else `'{day} de {monthName}'` built from a 12-entry `const` Portuguese month-name list local to the file (research.md R9 — no `intl` dependency, no year shown); the input is assumed already sorted newest-to-oldest and `group()` only buckets, never re-sorts within or across groups
- [X] T014 [P] Create `test/features/records/domain/entities/date_group_test.dart` covering: entries occurring today/yesterday/an older explicit date bucket under "Hoje"/"Ontem"/`'{day} de {monthName}'` respectively, using the deterministic `now` override for repeatability; groups come out in the input's own newest-to-oldest order, with no re-sorting introduced within or across groups — depends on T013
- [X] T015 [P] Create `EntryMerger` in `lib/features/records/domain/entities/entry_merger.dart` (data-model.md, spec.md's resolved Clarification 3): `EntryMerger.merge({required List<Entry> primary, required List<Entry> secondary})` unions the two lists by `id`; on a shared id, `primary`'s copy wins (the Clarification's "prefer the freshly-fetched copy's `updatedAt`/`serverRevision`" is satisfied by always calling `merge` with the fresher data as `primary`); the result is sorted newest-to-oldest by `occurredAt` regardless of the two input lists' own order
- [X] T016 [P] Create `test/features/records/domain/entities/entry_merger_test.dart` covering: an entry present in only one of the two lists passes through unchanged; an id present in both lists is shown exactly once, using `primary`'s copy of that entry's fields (SC-001's "100% of entries appear exactly once"); the merged result is sorted newest-to-oldest by `occurredAt` even when the two inputs are supplied in a different or mixed order — depends on T015

**Checkpoint**: `EntriesRepository.list()`/`.getById()` work end to end with silent-refresh-and-retry
on `AuthExpiredFailure`, and `records/domain/`'s three pure helpers (`SyncBadge`, `DateGrouper`,
`EntryMerger`) all exist and are unit-tested. No UI exists yet — user story work can now begin.

---

## Phase 3: User Story 1 - Seeing every entry in one place, regardless of origin (Priority: P1) 🎯 MVP

**Goal**: Opening "Meus Registros" fetches and displays all of the signed-in user's entries —
manual, audio, photo, and chat — in one reverse-chronological, date-grouped list, each card carrying
an origin marker, a time, a text excerpt, tag chips (when present), and a synchronization badge;
scrolling to the bottom loads and appends further pages automatically without disturbing what's
already on screen.

**Independent Test**: Seed a user with entries of different origins across different days, open
"Meus Registros", and confirm every entry appears exactly once, grouped under the correct date
heading, with an origin-appropriate visual marker on each; scroll to exercise pagination.

### Implementation for User Story 1

- [X] T017 [P] [US1] Create the `RecordsEvent` sealed class with `RecordsStarted`, `NextPageRequested`, `PageLoadRetried`, and `RecordsLocalCacheRefreshed` (all four defined now per data-model.md's event table; the handler for `RecordsLocalCacheRefreshed` is wired in User Story 2) in `lib/features/records/presentation/bloc/records_event.dart`
- [X] T018 [P] [US1] Create the `RecordsState` sealed class with `RecordsLoading`, `RecordsLoadFailure(Failure failure)`, and `RecordsLoaded(entries, nextCursor, isLoadingMore, pageLoadFailure)` — including the `hasReachedEnd` (`nextCursor == null`) and `isEmpty` (`entries.isEmpty`) getters (data-model.md) in `lib/features/records/presentation/bloc/records_state.dart`
- [X] T019 [US1] Create `RecordsBloc` in `lib/features/records/presentation/bloc/records_bloc.dart`, depending only on `EntriesRepository` (research.md R4/R11 — never `SessionRepository`, `ConnectivityChecker`, or `SessionBloc`), exposing a one-shot broadcast `Stream<void> get reauthRequired`; implement `_onStarted`/`_loadFirstPage` and `_onNextPageRequested`/`_fetchNextPage` exactly per contracts/records-bloc.md: `_loadFirstPage` calls `_entriesRepository.list()` — on `Left`, fires `reauthRequired` whenever the failure `is AuthExpiredFailure` and always emits `RecordsLoadFailure(failure)` (never the empty state, so a true zero-entries account is never confused with "couldn't load"); on `Right`, emits `RecordsLoaded(entries: EntryMerger.merge(primary: page.entries, secondary: _entriesRepository.cachedEntries), nextCursor: page.nextCursor, isLoadingMore: false)`. `_onNextPageRequested` no-ops when `state is! RecordsLoaded || current.hasReachedEnd || current.isLoadingMore`; otherwise emits an `isLoadingMore: true` snapshot, calls `list(cursor: current.nextCursor)`, and on `Left(AuthExpiredFailure)` leaves `entries`/`nextCursor` exactly as they were with `isLoadingMore` reset to `false` and `pageLoadFailure` left `null` (FR-007's "restored exactly as it was" holds by construction) while still firing `reauthRequired`; on any other `Left`, sets `pageLoadFailure` to that failure with `entries`/`nextCursor` unchanged and `isLoadingMore` reset to `false` (FR-009); on `Right`, emits the merged (`EntryMerger.merge(primary: current.entries + page.entries, secondary: cachedEntries)`), appended entry list with the new `nextCursor`. Override `close()` to close the stream controller — depends on T017, T018, T015 (Foundational)
- [X] T020 [US1] Implement `_onPageLoadRetried` in `RecordsBloc` (`lib/features/records/presentation/bloc/records_bloc.dart`): from a `RecordsLoadFailure` state, re-emits `RecordsLoading` and re-attempts `_loadFirstPage`; from a `RecordsLoaded` state with `pageLoadFailure != null`, re-attempts `_fetchNextPage` against the same, still-unconsumed `nextCursor` (contracts/records-bloc.md) — depends on T019
- [X] T021 [P] [US1] Create `SyncBadgeDot` in `lib/features/records/presentation/widgets/sync_badge_dot.dart`: an 8px (`DesignTokens.sizeLoadingDot`) colored dot plus a mono-caption label pair, parameterized by `SyncBadgeState` and mapping `synchronized`/`synchronizing`/`error` to `DesignTokens.colorSuccess`/`colorWarningSync`/`colorError` and the labels "sincronizado"/"sincronizando"/"erro de sync" respectively (data-model.md's mapping table — all three colors already exist in `DesignTokens`, zero new tokens)
- [X] T022 [P] [US1] Create `RecordCard` in `lib/features/records/presentation/widgets/record_card.dart` rendering one `Entry`: a spine + icon colored by `source` — `manual` → `DesignTokens.colorPrimary`/`Icons.edit_outlined`, `audio` → `colorSecondary`/`Icons.mic_none`, `photo` → `colorTextSecondary`/`Icons.image_outlined`, `chat` → `colorAccent`/`Icons.chat_bubble_outline` (data-model.md's origin marker mapping table); a monospace time (`occurredAt.toLocal()` formatted `HH:mm`, `DesignTokens.textMonoCaption`); a `SyncBadgeDot(state: SyncBadge.derive(localWrite: null))` (research.md R6 — every entry this unit ever renders is, by construction, already server-confirmed); the text excerpt (`content`, no truncation logic beyond the card's own fixed layout clipping it); and tag chips built from `tags.map((t) => t.name)`, rendered only when `tags.isNotEmpty` (FR-002 / Acceptance Scenario 2 — an entry with an empty tags list renders no chips, same as one with none attached) — depends on T011 (Foundational), T021
- [X] T023 [US1] Create `RecordsPage` in `lib/features/records/presentation/pages/records_page.dart`: a `Scaffold` matching the prototype's header (back arrow, "Meus Registros" title, an inert download icon rendered but with no `onTap` behavior — FR-008) and an inert search bar + funnel button (FR-008, also no behavior); a `ScrollController` created once in `initState` and never recreated across `BlocBuilder` rebuilds (preserves scroll position — FR-003/FR-007), with a listener dispatching `NextPageRequested` once `position.pixels >= position.maxScrollExtent - 200`; a `BlocBuilder<RecordsBloc, RecordsState>` rendering `RecordsLoading` as a centered spinner, `RecordsLoadFailure` as a full-screen retryable error (the failure's message plus a "Tentar novamente" button dispatching `PageLoadRetried`), and `RecordsLoaded` (the non-empty case only — the `isEmpty` branch is added in User Story 2) as a `ListView` built from `DateGrouper.group(loaded.entries)` — one date-heading row per `DateGroup` followed by its `RecordCard`s, a bottom spinner when `isLoadingMore`, and an inline retryable banner dispatching `PageLoadRetried` when `pageLoadFailure != null`; dispatches `RecordsStarted` once in `initState` — depends on T019, T020, T022
- [X] T024 [US1] Replace `AppRoutes.records`'s builder in `lib/core/routing/app_router.dart` with `BlocProvider<RecordsBloc>(create: (_) => getIt<RecordsBloc>()..add(const RecordsStarted()), child: const RecordsPage())`, removing the `RecordsPlaceholderPage` import and builder — depends on T023
- [X] T025 [US1] Register `getIt.registerFactory<RecordsBloc>(() => RecordsBloc(entriesRepository: getIt<EntriesRepository>()))` in `lib/core/di/service_locator.dart` (alongside the existing Entries registrations) — depends on T019, T007 (Foundational)
- [X] T026 [US1] Delete `lib/features/records/presentation/pages/records_placeholder_page.dart` — fully superseded now that `AppRoutes.records` builds `RecordsPage` (research.md R8) — depends on T024
- [X] T027 [P] [US1] Write `RecordsBloc` tests in `test/features/records/presentation/bloc/records_bloc_test.dart` against a `mocktail` fake `EntriesRepository`, covering contracts/records-bloc.md's non-auth scenarios (the `AuthExpiredFailure`-specific scenarios are added in User Story 3): `RecordsStarted` with a successful `list()` emits `RecordsLoaded` with merged/deduped entries and `isLoadingMore: false` (scenario 1); `RecordsStarted` with a non-auth failure emits `RecordsLoadFailure` and `reauthRequired` does **not** fire (scenario 2); `NextPageRequested` while `hasReachedEnd` is a no-op with no state emitted (scenario 4); `NextPageRequested` while `isLoadingMore` is a no-op (scenario 5); a successful `NextPageRequested` appends (never replaces) entries, preserving already-rendered entries' identity (scenario 6); a non-auth `NextPageRequested` failure leaves entries unchanged, sets `pageLoadFailure`, and does not fire `reauthRequired` (scenario 8); `PageLoadRetried` from `RecordsLoadFailure` re-attempts the first page (scenario 9); `PageLoadRetried` from a `pageLoadFailure` re-attempts the same `nextCursor`, not a reload (scenario 10); a fetched page that is itself empty but carries a non-null `nextCursor` emits normally with no transition to an empty-account display (scenario 12, Edge Cases); a fetched page containing a `chat`-sourced entry renders without throwing (scenario 13, research.md R2) — depends on T019, T020

**Checkpoint**: User Story 1 is independently functional — opening "Meus Registros" shows every
entry, grouped by date, each card showing its origin, time, badge, excerpt, and tags, with automatic
scroll-triggered pagination and a retryable banner/screen on load failure. The empty-account case
and the session-expiry overlay are not yet handled (User Stories 2/3).

---

## Phase 4: User Story 2 - Starting from nothing (Priority: P1)

**Goal**: A zero-entries account sees a clear empty state (notebook illustration, "Nenhum registro
ainda", "Criar primeiro registro") instead of a blank list; completing a save from that action
returns to this screen with the new entry visible immediately, in place of the empty state.

**Independent Test**: Open "Meus Registros" on an account with zero entries, confirm the empty-state
illustration/message/CTA appear, and confirm tapping the CTA leads to creating an entry that then
populates the screen.

### Implementation for User Story 2

- [X] T028 [US2] Extract `openInsertionModal(BuildContext context)` from `home_chat_shell_page.dart`'s private `_openInsertionModal` into a new public function in `lib/features/capture/presentation/widgets/open_insertion_modal.dart` — identical body (the same `showModalBottomSheet`/`isScrollControlled: true`/`BlocProvider<InsertionModalBloc>`/`InsertionModalPage` call it already is, research.md R10); update `home_chat_shell_page.dart`'s "+" button to call the shared function and delete its now-redundant private copy
- [X] T029 [P] [US2] Create `RecordsEmptyState` in `lib/features/records/presentation/widgets/records_empty_state.dart`: a notebook icon, the text "Nenhum registro ainda", and a "Criar primeiro registro" `ElevatedButton` whose `onPressed` callback is supplied by the caller (data-model.md) — matches the prototype's "Tela 4 — Vazio"
- [X] T030 [US2] Implement `_onLocalCacheRefreshed` in `RecordsBloc` (`lib/features/records/presentation/bloc/records_bloc.dart`): no-ops when `state is! RecordsLoaded` (nothing to merge into before the first page has even loaded); otherwise re-emits `RecordsLoaded` with `entries: EntryMerger.merge(primary: current.entries, secondary: _entriesRepository.cachedEntries)` and every other field of `current` unchanged — purely re-reads `cachedEntries` (already updated by `CreateEntryUseCase` by the time the insertion modal's `showModalBottomSheet` future resolves), no network call (contracts/records-bloc.md, research.md R10) — depends on T019 (US1)
- [X] T031 [US2] Extend `RecordsPage` (`lib/features/records/presentation/pages/records_page.dart`): add the `RecordsLoaded.isEmpty` branch rendering `RecordsEmptyState` in place of the `ListView`; its CTA calls a new `_openEmptyStateCreate(BuildContext context)` method that `await`s `openInsertionModal(context)` and, once that `Future` resolves (checking `mounted` first), dispatches `RecordsLocalCacheRefreshed` (contracts/records-bloc.md's `RecordsPage` responsibilities — FR-004; Clarification 1: the save flow returns to this screen, not Home/Chat, because `showModalBottomSheet` always pops back onto whichever screen presented it — no new routing needed) — depends on T023 (US1), T028, T029, T030
- [X] T032 [P] [US2] Extend `test/features/records/presentation/bloc/records_bloc_test.dart` with `RecordsLocalCacheRefreshed` coverage per contracts/records-bloc.md's scenario table: dispatched from a `RecordsLoaded` state, a newly `cachedEntries`-held entry appears merged into `entries`, deduped by id if it is also later re-fetched from the backend (scenario 11, SC-001); dispatched while `state is! RecordsLoaded` is a no-op — depends on T030

**Checkpoint**: User Stories 1 AND 2 both work independently — a zero-entries account sees the empty
state, and completing a save from its CTA returns to "Meus Registros" with the new entry visible
immediately in its correct date group.

---

## Phase 5: User Story 3 - The session expires while browsing (Priority: P2)

**Goal**: A session expiring while the user is scrolled partway through their history surfaces the
existing "Sessão expirada" overlay without discarding the loaded entries or the scroll position;
re-authenticating dismisses the overlay and restores the screen exactly as it was.

**Independent Test**: Load the timeline, scroll to a known position, force a session-expired
response, confirm the overlay appears without resetting the list, and confirm re-authentication
restores that exact scroll position and content.

### Implementation for User Story 3

- [X] T033 [US3] Extend `RecordsPage` (`lib/features/records/presentation/pages/records_page.dart`): in `initState`, subscribe to `context.read<RecordsBloc>().reauthRequired` and, on each event, call `context.read<SessionBloc>().add(const AuthExpiredDetected())` — the exact event `SessionBloc` already defines for "Raised by any authenticated call elsewhere in the app that comes back AUTH_EXPIRED," unused by any unit until now; this is the one sanctioned cross-bloc touch point, living in a widget (`State<RecordsPage>`), never inside a `Bloc` subclass (research.md R5, requirements.md RF07's own "No BLoC imports another BLoC directly" acceptance criterion); cancel the subscription in `dispose()` — depends on T023 (US1), T031 (US2, same file)
- [X] T034 [US3] Create `test/architecture/no_bloc_imports_bloc_test.dart`, mirroring `test/architecture/domain_purity_test.dart`'s shape (RNF06, requirements.md RF07's own acceptance criterion): scan every file under any `presentation/bloc/` folder and assert none of them imports another feature's `presentation/bloc/` path; confirm `records_bloc.dart` passes this check, and that `records_page.dart` (under `presentation/pages/`, not matched by the scan) is where the one sanctioned `SessionBloc`/`AuthExpiredDetected` import lives — depends on T033
- [X] T035 [P] [US3] Extend `test/features/records/presentation/bloc/records_bloc_test.dart` with the `AuthExpiredFailure`-specific scenarios from contracts/records-bloc.md's table: `RecordsStarted` failing `AuthExpiredFailure` emits `RecordsLoadFailure` **and** fires `reauthRequired` exactly once (scenario 3); `NextPageRequested` failing `AuthExpiredFailure` leaves `entries`/`nextCursor` unchanged, `pageLoadFailure` stays `null`, `isLoadingMore` resets to `false`, and `reauthRequired` fires (scenario 7) — depends on T019 (US1)

**Checkpoint**: User Stories 1, 2, AND 3 all work independently — a session expiring mid-browse
surfaces the existing "Sessão expirada" overlay without disturbing the loaded entries or scroll
position, and re-authenticating restores the screen exactly as it was.

---

## Phase 6: User Story 4 - The synchronization badge tells the truth, even during session trouble (Priority: P3)

**Goal**: Every entry's synchronization badge keeps showing an accurate, unchanged state throughout
a silent session renewal or a "Sessão expirada" overlay cycle — never frozen, blanked, or delayed by
session/authentication handling.

**Independent Test**: Put entries in each of the three badge states, force a session expiration and
renewal in the background, and confirm every badge's state is unaffected by that session activity
throughout.

### Implementation for User Story 4

- [X] T036 [P] [US4] Extend `test/features/records/presentation/bloc/records_bloc_test.dart` with a scenario proving entry data relevant to the sync badge is unaffected by session trouble: capture the `entries` list (and each entry's `SyncBadge.derive(localWrite: null)` result) from a `RecordsLoaded` state, trigger a `NextPageRequested` that fails `AuthExpiredFailure`, and assert both the entry list and every entry's derived badge state are byte-identical afterward (data-model.md R6; spec.md User Story 4 Acceptance Scenario 1) — depends on T035 (US3)
- [ ] T037 [US4] No production-code change is expected for this story: `SyncBadge.derive` (T011, Foundational) takes no session- or auth-related input at all, and `RecordsState` never carries session data, so FR-005's independence holds by construction (research.md R6) — this task is to execute quickstart.md's Story 4 manual-verification steps on the iOS Simulator and confirm every visible badge reads "sincronizado" (green), unchanged, throughout both a forced silent renewal and a forced expire-and-overlay-and-restore cycle — note this unit's own data never produces a "synchronizing" or "error" badge (every entry rendered here is server-confirmed, per spec.md's Assumptions), so this manual pass and T036's automated check both validate state-preservation of the one state reachable in practice ("sincronizado"); the other two states' correctness is validated separately and exhaustively at the pure-function level (T012's 3-branch coverage of `SyncBadge.derive`), not at the rendered-card or bloc-state level — depends on T036, T033 (US3)

**Checkpoint**: All four user stories are independently functional and testable — the full "Meus
Registros" screen now matches spec.md end to end.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: The constitution/quickstart gates that span every story above.

- [X] T038 [P] Run `fvm flutter analyze` and resolve any lint findings introduced under `lib/features/records/`, `lib/features/entries/`, `lib/features/capture/presentation/widgets/open_insertion_modal.dart`, `lib/core/network/api_client.dart`, `lib/core/di/service_locator.dart`, and `lib/core/routing/app_router.dart` by this unit
- [X] T039 [P] Run `test/architecture/domain_purity_test.dart` and confirm it still reports 0 violations with `entries_page.dart`, `sync_badge_state.dart`, `date_group.dart`, and `entry_merger.dart` included — none of them may import `package:flutter` or any `data/` class (RNF06, Post-Design Constitution Check)
- [X] T040 Run `fvm flutter test --coverage`, extract `lib/**/domain/**` via `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info`, and confirm ≥80% coverage (RNF07) with `entry_merger.dart`/`date_group.dart`/`sync_badge_state.dart` and `EntriesRepositoryImpl`'s new `list()`/`getById()` silent-refresh-and-retry branches all covered
- [ ] T041 Execute quickstart.md's remaining manual verification on the iOS Simulator: Story 1's full scroll-to-end pagination and the seeded `chat`-origin entry's rendering; Story 2's empty-state-to-populated transition; Story 3's forced-expiry-and-overlay-and-restore cycle; and the Edge Cases section (airplane-mode mid-scroll retryable error with no write attempted; a forced first-load outright failure that never shows the empty state; the inert header download icon and search bar/funnel button rendering per the prototype but doing nothing; a seeded account whose newest page is empty while older entries exist continuing to page into those older groups rather than showing the empty state)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No tasks — proceed directly to Foundational.
- **Foundational (Phase 2)**: No dependencies — BLOCKS all user stories.
- **User Stories (Phase 3–6)**: All depend on Foundational completion.
  - US1 (P1) builds the core `RecordsBloc`/`RecordsPage`/widgets and is this unit's MVP.
  - US2 (P1) extends `RecordsBloc` (`_onLocalCacheRefreshed`) and `RecordsPage` (the empty-state
    branch) built in US1 — depends on US1's T019/T023 already existing.
  - US3 (P2) extends `RecordsPage` (the `reauthRequired` subscription) built in US1/US2 — depends on
    US1's T023 and US2's T031 (same file) already existing. `RecordsBloc`'s own `AuthExpiredFailure`
    branching was already built correctly in US1's T019; US3 adds the widget-level wiring plus the
    tests that specifically exercise it.
  - US4 (P3) depends on US3's `AuthExpiredFailure` test fixtures (T035) to build its own
    badge-independence assertion against, and on US3's overlay wiring (T033) for its manual
    verification step.
- **Polish (Phase 7)**: Depends on all four stories being complete.

### Within Each User Story

- Events/state additions before the bloc handler that needs them; the bloc handler before the DI
  registration that constructs it; DI before the page that reads it via `context.read<RecordsBloc>()`.
- Tests are written alongside (and can run immediately after) each handler task, extending one
  shared `records_bloc_test.dart` across stories — the same convention RF02's own tasks.md used for
  `insertion_modal_bloc_test.dart`.
- Story complete (events/state + bloc handlers + widgets + DI/routing + tests) before moving to the
  next priority.

### Parallel Opportunities

- T001, T002, T003 (Foundational `entries/` plumbing) in parallel with each other; T011, T013, T015
  (Foundational `records/domain/` helpers) in parallel with each other and with T001–T003 — all
  different files.
- T008, T009, T010 (Foundational test extensions) in parallel with each other once their respective
  implementation tasks land.
- T012, T014, T016 (pure-helper tests) in parallel with each other once T011/T013/T015 land.
- T017/T018 (US1 event/state files) in parallel with each other; T021/T022 (US1 widgets) in parallel
  with each other once T011 (Foundational) lands.
- T038/T039 (Polish) in parallel with each other.

---

## Parallel Example: Foundational Phase

```bash
Task: "Add queryParameters to ApiClient.call() in lib/core/network/api_client.dart"
Task: "Add EntrySource.chat to lib/features/entries/domain/entities/entry.dart"
Task: "Create EntriesPage in lib/features/entries/domain/entities/entries_page.dart"
Task: "Create SyncBadge in lib/features/records/domain/entities/sync_badge_state.dart"
Task: "Create DateGrouper in lib/features/records/domain/entities/date_group.dart"
Task: "Create EntryMerger in lib/features/records/domain/entities/entry_merger.dart"
```

## Parallel Example: User Story 1 bloc scaffolding

```bash
Task: "Create RecordsEvent in lib/features/records/presentation/bloc/records_event.dart"
Task: "Create RecordsState in lib/features/records/presentation/bloc/records_state.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
2. Complete Phase 3: User Story 1.
3. **STOP and VALIDATE**: open "Meus Registros" on a seeded account, confirm every entry appears
   exactly once grouped by date with the right origin marker/badge/excerpt/tags, and confirm
   scrolling to the bottom loads and appends further pages without disturbing what's on screen.

### Incremental Delivery

1. Foundational → `EntriesRepository.list()`/`.getById()` and the three pure `records/domain/`
   helpers exist; nothing visible changes yet.
2. Add US1 → "Meus Registros" works end to end for an account with entries (SC-001, SC-003).
3. Add US2 → a zero-entries account sees the empty state and can create its first entry from it
   (SC-002).
4. Add US3 → a session expiring mid-browse surfaces the overlay without data loss (SC-004).
5. Add US4 → the sync badge's session-independence property is explicitly verified (SC-005).
6. Polish → RNF06/RNF07 gates + quickstart's full manual pass.

---

## Notes

- `records_bloc.dart` and `records_page.dart` are each touched by multiple story phases
  (T019/T020/T030 for the bloc; T023/T031/T033 for the page) — this mirrors RF02's own tasks.md
  precedent: a deliberate consequence of one shared bloc/page serving the whole screen, not a
  same-file conflict to avoid.
- `records_placeholder_page.dart` is deleted only in T026 (US1), once `AppRoutes.records` no longer
  references it (T024) — the app must keep compiling at every checkpoint.
- No task in this list touches `docs/input/`, `docs/input/backend/api/openapi.yaml`, `.env`, any
  native iOS project file, or any RF04–RF10/extension-feature behavior — all explicitly out of scope
  (FR-010, FR-011).
- `EntriesRepository.getById()` is implemented and tested (T005, T006, T008, T009) but has no call
  site anywhere in this task list, by design (research.md R7) — nothing in this unit ever produces a
  locally-pending/unreconciled entry for it to reconcile.
- Every color `record_card.dart`/`sync_badge_dot.dart` render (T021, T022) already exists in
  `DesignTokens` — no task in this list adds a new design token (plan.md Constraints, Principle
  IV/RNF08).
