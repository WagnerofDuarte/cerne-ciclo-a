---

description: "Task list for P-RF09 — Temporal summaries / dashboard"
---

# Tasks: P-RF09 — Temporal summaries / dashboard

**Input**: Design documents from `/specs/011-settings-dashboard/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Not explicitly requested in spec.md beyond the constitutional RNF07 (≥80% domain coverage) and
RNF09 (full `Either`/scenario-table coverage) gates, which this project's every prior unit has satisfied with
real `flutter_test`/`bloc_test`/`mocktail` tests (not skipped). Test tasks are therefore included, scoped
exactly to what research.md/contracts/*.md's own scenario tables enumerate — no broader test suite than that.

**Organization**: Tasks are grouped by user story (US1 = dashboard, US2 = account deletion, US3 =
profile/biometric/sign-out) per spec.md's own priority order (US1 = P1, US2 = P1, US3 = P2). Foundational
work shared by all three stories (entities, the two existing-feature extensions, DI, tokens) is Phase 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (dashboard), US2 (account deletion), US3 (profile/biometric/sign-out)
- Every file path is exact; every entity/field constraint is quoted from data-model.md/contracts/*.md verbatim
  where one exists.

## Path Conventions

Single Flutter mobile project. New feature folder: `lib/features/settings/{domain,data,presentation}/`.
Tests mirror under `test/features/settings/` and `test/features/{auth,entries,chat,home}/` for the three
extended-in-place files, following this repo's existing `test/features/<feature>/<layer>/...` convention.

---

## Phase 1: Setup

No new dependencies, no new project scaffolding beyond the feature folder structure itself (plan.md Technical
Context: "No primary dependencies added"). This phase only creates the directory skeleton; no file content.

- [X] T001 Create the empty `lib/features/settings/domain/entities/`, `lib/features/settings/domain/repositories/`,
  `lib/features/settings/domain/usecases/`, `lib/features/settings/data/`,
  `lib/features/settings/presentation/bloc/`, `lib/features/settings/presentation/widgets/` directories
  (`lib/features/settings/presentation/pages/` already exists, holding `settings_placeholder_page.dart`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Domain entities, design tokens, and the three existing-feature extensions (`auth`, `entries`,
`chat`) that every user story's implementation phase depends on, plus DI wiring for everything not already
registered. **⚠️ CRITICAL**: No user story phase can be completed until this phase is done — `SettingsBloc`
(built across all three story phases) depends on every repository/usecase interface defined here.

### Design tokens

- [X] T002 [P] Add 5 new `DesignTokens` values to `lib/core/design_tokens.dart` (research.md R14,
  data-model.md): `static const double sizeAvatarSettings = 52;` (prototype-extract.md §6, "52px in
  Configurações"), `static const double sizeChartBarMaxHeight = 120;`, `static const double
  sizeChartBarWidth = 20;`, `static const double sizeChartBarGap = 6;` (Sizes section), and `static const
  Color colorChartPlaceholder = Color(0xFFE1DACB);` (Colors section — same hex as existing `colorBorder`,
  added under a new, semantically distinct name)

### Domain entities (`lib/features/settings/domain/entities/`)

- [X] T003 [P] Create `DashboardSourceCounts` (`{manual, audio, photo, chat}`, each `int`, each "≥ 0"
  data-model.md), `AggregateBucket` (`{date: DateTime, count: int, sources: DashboardSourceCounts}` — "Parsed
  from the backend's `YYYY-MM-DD` string, date-only (no time component kept)", "count ≥ 0"), and
  `DashboardTotals` (`{count: int, sources: DashboardSourceCounts}`) in
  `lib/features/settings/domain/entities/dashboard_aggregate.dart`, each `Equatable`
- [X] T004 [P] Create `DashboardAggregate` (`{buckets: List<AggregateBucket>, totals: DashboardTotals}`,
  `Equatable`) with the pure method `List<int> tenBars({DateTime? today})` in
  `lib/features/settings/domain/entities/dashboard_aggregate.dart`, implementing the exact algorithm from
  research.md R2: if `buckets.isEmpty` return `List.filled(10, 0)`; else compute `start` as the earliest
  bucket date, `totalDaySpan = (today ?? DateTime.now()).difference(start).inDays`; if `totalDaySpan == 0`,
  put the full summed count in `bars[9]`; otherwise for each bucket compute `index = (daysSinceStart * 10) ~/
  (totalDaySpan + 1)` clamped to `[0, 9]` and accumulate `count` into `bars[index]`
- [X] T005 [P] Create `DashboardNarrative` (`{text: String, generatedAt: DateTime}`, `Equatable`) in
  `lib/features/settings/domain/entities/dashboard_narrative.dart`
- [X] T006 [P] Create `AccountProfile` (`{displayName: String, email: String}`, `Equatable`) in
  `lib/features/settings/domain/entities/account_profile.dart` with: `static String
  defaultDisplayNameFromEmail(String email)` — relocate `app_drawer.dart`'s existing
  `_displayNameFromEmail`/`_emailNameWords` logic byte-for-byte unchanged (splits the email's local part on
  `._-`, title-cases each word, joins with a space; returns `email` itself if the local part is empty,
  contracts/app-drawer-display-name-extension.md point 2); `String get initials` — 1–2 uppercase letters from
  `displayName`'s whitespace-split words (first letter of the first word, plus first letter of the second
  word if one exists), `"?"` if `displayName` is empty (relocated from `_initialsFromEmail`, now deriving from
  `displayName` rather than always from email); `static bool isValidDisplayName(String value)` — `value.trim()
  .isNotEmpty && value.trim().length <= 80` (FR-011)

### Domain repository interfaces (`lib/features/settings/domain/repositories/`)

- [X] T007 [P] Create `DashboardRepository` abstract class in
  `lib/features/settings/domain/repositories/dashboard_repository.dart`: `Future<Either<Failure,
  DashboardAggregate>> fetchAggregate();` and `Future<Either<Failure, DashboardNarrative>> fetchNarrative();`
  (contracts/dashboard-repository.md)
- [X] T008 [P] Create `AccountProfileRepository` abstract class in
  `lib/features/settings/domain/repositories/account_profile_repository.dart`: `Future<String?>
  readCachedDisplayName();`, `Future<Either<Failure, String>> updateDisplayName(String name);`,
  `Future<void> clearCachedDisplayName();` (contracts/account-profile-repository.md)
- [X] T009 [P] Create `AccountDeletionRepository` abstract class in
  `lib/features/settings/domain/repositories/account_deletion_repository.dart`: `Future<Either<Failure,
  Unit>> deleteAccount();` (contracts/account-deletion-repository.md)

### Domain usecase

- [X] T010 [US3-shared] Create `SaveSettingsBiometricPreferenceUseCase` in
  `lib/features/settings/domain/usecases/save_settings_biometric_preference_usecase.dart`, depending on
  `BiometricsPreferenceRepository` and `VaultRepository` (both `vault/domain/`, unmodified): `Future<Either<
  Failure, void>> call(bool enabled)` awaits `_biometricsPreferenceRepository.save(enabled)`; on `Left`,
  returns the failure untouched (local mirror left alone); on `Right`, calls
  `_vaultRepository.setBiometricPreferenceLocally(enabled)` then returns `const Right(null)`
  (contracts/biometric-preference-settings-extension.md)

### Existing-feature extensions (`auth`, `entries`, `chat`) — additive methods only

- [X] T011 [P] Add `Future<Either<Failure, Unit>> logout();` to `AuthRepository` abstract class in
  `lib/features/auth/domain/repositories/auth_repository.dart`
- [X] T012 Add `Future<Either<Failure, Unit>> logout()` to `AuthRemoteDataSource`
  (`lib/features/auth/data/auth_remote_data_source.dart`), calling `auth-logout` (`POST /auth/logout`,
  `bearerAuth`, empty body), returning `Right(unit)` on any 200 regardless of the response's `ok` value
  (contracts/account-session-actions.md — depends on T011)
- [X] T013 Implement `logout()` in `AuthRepositoryImpl`
  (`lib/features/auth/data/auth_repository_impl.dart`) delegating to `AuthRemoteDataSource.logout()`,
  **without** calling `SecureTokenStorage`/`SessionRepository.clear()` itself (that stays `SettingsBloc`'s
  job per contracts/account-session-actions.md — depends on T011, T012)
- [X] T014 [P] Add `Future<void> clear();` to `EntriesLocalCache`
  (`lib/features/entries/data/entries_local_cache.dart`), deleting every key it owns
- [X] T015 [P] Add `Future<void> clearLocalData();` to `EntriesRepository` abstract class
  (`lib/features/entries/domain/repositories/entries_repository.dart`)
- [X] T016 Implement `clearLocalData()` in `EntriesRepositoryImpl`
  (`lib/features/entries/data/entries_repository_impl.dart`) wiping its in-memory mirror and calling
  `EntriesLocalCache.clear()` (depends on T014, T015)
- [X] T017 [P] Add `Future<void> clear();` to `ChatLocalCache` (`lib/features/chat/data/chat_local_cache.dart`),
  deleting every key it owns
- [X] T018 [P] Add `Future<void> clearLocalData();` to `ChatRepository` abstract class
  (`lib/features/chat/domain/repositories/chat_repository.dart`)
- [X] T019 Implement `clearLocalData()` in `ChatRepositoryImpl`
  (`lib/features/chat/data/chat_repository_impl.dart`) wiping its in-memory mirror and calling
  `ChatLocalCache.clear()` (depends on T017, T018)

### Foundational tests (structural + pure-domain, no I/O)

- [X] T020 [P] Unit tests for `DashboardAggregate.tenBars()` in
  `test/features/settings/domain/entities/dashboard_aggregate_test.dart` covering exactly the five cases
  contracts/dashboard-repository.md lists: empty input → 10 zeros; a single bucket dated "today" → all
  weight in bar index 9; buckets spanning exactly 10 days → one bucket per bar, 1:1; buckets spanning 100
  days → several buckets folding into the same bar; a bucket dated after `today` → clamps to bar 9 rather
  than throwing or indexing out of range
- [X] T021 [P] Unit tests for `AccountProfile` in
  `test/features/settings/domain/entities/account_profile_test.dart` covering
  `defaultDisplayNameFromEmail` (including the empty-local-part fallback to the email itself), `initials`
  (two-word name, one-word name, empty `displayName` → `"?"`), and `isValidDisplayName` (empty string →
  `false`, exactly 80 chars → `true`, 81 chars → `false`, whitespace-only → `false`)
- [X] T022 Run `flutter test test/architecture/domain_purity_test.dart
  test/architecture/no_bloc_imports_bloc_test.dart` and confirm both still pass with `features/settings/`
  present (quickstart.md Edge Cases) — no code change expected, this task is a verification gate

**Checkpoint**: Foundation ready — domain entities, repository interfaces, the biometric usecase, and all
three existing-feature extensions exist and are tested. User story phases can now proceed.

---

## Phase 3: User Story 1 - Seeing your evolution dashboard (Priority: P1) 🎯 MVP

**Goal**: Settings shows the ten-bar evolution chart and AI narrative, correctly distinguishing the
zero/one/multi-entry/error states, always recomputed fresh.

**Independent Test**: Open Settings for accounts seeded with zero, one, and more-than-thirty entries; each
renders its own distinct, non-crashing state with the correct chart and narrative text (quickstart.md Story
1).

### Tests for User Story 1

- [X] T023 [P] [US1] Test for `DashboardRemoteDataSource`/`DashboardRepositoryImpl.fetchAggregate()` in
  `test/features/settings/data/dashboard_repository_impl_test.dart` covering contracts/dashboard-repository.md's
  scenario table #1–7 for `fetchAggregate`: 200 zero-entry (`buckets: []`, `totals.count: 0`) → `Right` with
  empty bucket list; 200 well-formed non-empty → `Right`; Dio timeout → `Left(NetworkTimeoutFailure)`; no
  connection → `Left(NetworkOfflineFailure)`; malformed body (`buckets` not a list / `count` missing) →
  `Left(ValidationFailure)`; 401 `AUTH_EXPIRED` + successful silent refresh → retried result; 401
  `AUTH_EXPIRED` + failed silent refresh → `Left(AuthExpiredFailure)`
- [X] T024 [P] [US1] Test for `DashboardRepositoryImpl.fetchNarrative()` in
  `test/features/settings/data/dashboard_repository_impl_test.dart` (same file as T023) covering the same
  scenario shapes for `fetchNarrative`, plus scenario #8: `dashboard-narrative-get` returning
  `AI_GENERATION_TIMEOUT` → `Left(AiGenerationTimeoutFailure)`
- [X] T024a [P] [US1] Bloc test for `SettingsBloc`'s `SettingsOpened`/`DashboardRetryRequested` dashboard
  handling in `test/features/settings/presentation/bloc/settings_bloc_test.dart` (shared file, extended
  across phases) covering: zero-entry aggregate → `dashboardStatus → loaded`, `narrativeStatus` stays
  `notRequested`, `fetchNarrative()` never called (FR-003); one-entry aggregate → same `notRequested`
  skip (FR-004); two-or-more-entry aggregate → `narrativeStatus: loading` then `loaded` once
  `fetchNarrative()` resolves `Right`, or `unavailable` on `Left` (FR-005/006); aggregate fetch `Left` →
  `dashboardStatus → loadFailure`, `dashboardFailure` set, `fetchNarrative()` never called (FR-007);
  aggregate fetch `Left(AuthExpiredFailure)` after a failed silent refresh additionally emits exactly one
  event on `settingsBloc.reauthRequired` (contracts/dashboard-repository.md #7); `DashboardRetryRequested`
  re-runs the same aggregate-then-conditional-narrative sequence from a prior `loadFailure` state

### Implementation for User Story 1

- [X] T025 [P] [US1] Create `DashboardRemoteDataSource` in
  `lib/features/settings/data/dashboard_remote_data_source.dart` with two methods calling
  `dashboard-aggregate-get` (`GET /dashboard/aggregate?period=all`) and `dashboard-narrative-get`
  (`GET /dashboard/narrative?period=all`) via `ApiClient`, decoding `data.buckets[]`
  (`date`/`count`/`sources.{manual,audio,photo,chat}`) and `data.totals` for the aggregate, `data.text`/
  `data.generatedAt` for the narrative, per `docs/input/backend/api/openapi.yaml`'s schema
- [X] T026 [US1] Implement `DashboardRepositoryImpl` in
  `lib/features/settings/data/dashboard_repository_impl.dart` implementing `DashboardRepository`, calling
  `DashboardRemoteDataSource`, catching `TypeError` on decode as `ValidationFailure` (never thrown past the
  boundary, same pattern as `SessionRepositoryImpl._assembleFromCheckSession`), and applying the
  retry-once-on-`AuthExpiredFailure` shape from `EntriesRepositoryImpl._retryAfterSilentRefresh` to both
  methods (depends on T007, T025)
- [X] T027 [P] [US1] Create `lib/features/settings/presentation/bloc/settings_event.dart` with (at minimum
  for this phase) `SettingsOpened` and `DashboardRetryRequested` events, as `Equatable` classes
- [X] T028 [P] [US1] Create `lib/features/settings/presentation/bloc/settings_state.dart`: one `Equatable`
  class per data-model.md's full field table — `dashboardStatus` (`DashboardStatus` enum: `loading, loaded,
  loadFailure`, default `loading`), `aggregate` (`DashboardAggregate?`, default `null`), `dashboardFailure`
  (`Failure?`, default `null`), `narrativeStatus` (`NarrativeStatus` enum: `notRequested, loading, loaded,
  unavailable`, default `notRequested`), `narrativeText` (`String?`, default `null`), `displayName`
  (`String`, default `''`), `email` (`String`, default `''`), `nameEditStatus` (`NameEditStatus` enum:
  `viewing, editing, saving, error`, default `viewing`), `nameDraft` (`String`, default `''`),
  `nameEditFailureMessage` (`String?`, default `null`), `biometricToggleVisible` (`bool`, default `false`),
  `biometricEnabled` (`bool`, default `false`), `biometricSaving` (`bool`, default `false`),
  `biometricFailureMessage` (`String?`, default `null`), `isSigningOut` (`bool`, default `false`),
  `isDeletingAccount` (`bool`, default `false`), `deleteDialogOpen` (`bool`, default `false`),
  `deleteFailureMessage` (`String?`, default `null`), `signedOutDestination` (`SettingsDestination?`:
  `vault`/`login`, default `null`), `accountDeletedDestination` (`SettingsDestination?`, default `null`) —
  with a `copyWith` using the `RecordsLoaded`-style `_unset` sentinel for every nullable field that must be
  explicitly clearable (research.md R4)
- [X] T029 [US1] Create `lib/features/settings/presentation/bloc/settings_bloc.dart` as a `Bloc<SettingsEvent,
  SettingsState>` depending on `DashboardRepository`, `AccountProfileRepository`, `AccountDeletionRepository`,
  `AuthRepository`, `SessionRepository`, `SaveSettingsBiometricPreferenceUseCase`, `VaultRepository`
  (contracts/settings-bloc.md's Dependencies list); implement the broadcast `reauthRequired` stream
  (`StreamController<void>.broadcast()`, fired whenever a repository call's own single silent-refresh retry
  still returns `AuthExpiredFailure`), with `close()` overridden to also close it (mirroring `RecordsBloc`);
  implement the `SettingsOpened` handler's dashboard half per research.md R1: always fetch the aggregate
  (`dashboardStatus → loading` then `loaded`/`loadFailure`); only fetch the narrative once the aggregate
  resolves `Right` **and** `aggregate.totals.count >= 2` (`narrativeStatus` stays `notRequested` below 2,
  otherwise `loading → loaded`/`unavailable` — FR-003/004/005/006); implement `DashboardRetryRequested` as a
  re-run of the same aggregate-then-conditionally-narrative sequence (FR-007) (depends on T007, T027, T028)
- [X] T030 [P] [US1] Create `lib/features/settings/presentation/widgets/dashboard_bar_chart.dart`: a `Row` of
  10 `Container`s (research.md R3, no charting package), each bar's height `= count / maxBarCount *
  DesignTokens.sizeChartBarMaxHeight` (clamped to a minimum visible sliver for a non-zero sub-pixel bar),
  width `DesignTokens.sizeChartBarWidth`, gap `DesignTokens.sizeChartBarGap`, fill color
  `DesignTokens.colorAccent` (ochre); also render the single-bar state (exactly one bar) when
  `tenBars()` effectively collapses to one populated index
- [X] T031 [P] [US1] Create `lib/features/settings/presentation/widgets/dashboard_card.dart`: switches
  between the dashboard's states — `loading` (a loading indicator, satisfying RNF01's >300ms affordance
  requirement), zero-entries empty state (light-gray `DesignTokens.colorChartPlaceholder` placeholder chart
  icon + the exact text "Comece a registrar para ver sua evolução aqui", FR-003), one-entry state (single
  small bar + the exact text "Ainda é cedo pra ver um padrão — volte em alguns dias.", FR-004), multi-bar
  state (renders `DashboardBarChart` with whatever of the ten bars are populated, FR-005), and `loadFailure`
  (a clear, non-crashing, retryable error state distinct from the empty state, dispatching
  `DashboardRetryRequested` on retry tap, FR-007)
- [X] T032 [P] [US1] Create `lib/features/settings/presentation/widgets/narrative_view.dart`: renders
  `narrativeText` when `narrativeStatus == loaded`; renders a distinct "narrativa indisponível" message
  (this unit's one new authored copy string, in Portuguese, consistent with the rest of the screen's
  register) when `narrativeStatus == unavailable`; renders nothing when `notRequested` or `loading` (a
  loading affordance only, never conflated with the "indisponível" message or the zero-entries empty state —
  FR-006)
- [X] T033 [US1] Create `lib/features/settings/presentation/pages/settings_page.dart` as a
  `StatelessWidget`/`StatefulWidget` wrapping a `BlocProvider<SettingsBloc>(create: (_) =>
  getIt<SettingsBloc>()..add(const SettingsOpened()))`, rendering `DashboardCard` and `NarrativeView` at the
  top of the screen (the other two widgets, `ProfileHeader`/`BiometricToggleRow`, are added to this same page
  in Phase 5 — this task only wires the dashboard section plus the page's basic `Scaffold`/`AppBar` shell so
  US1 is independently viewable) (depends on T029, T030, T031, T032)
- [X] T034 [US1] Wire `AppRoutes.settings`'s route builder in `lib/core/routing/app_router.dart` to
  `SettingsPage` instead of `SettingsPlaceholderPage`, removing the now-unused
  `SettingsPlaceholderPage` import
- [X] T035 [US1] Register `DashboardRemoteDataSource` (lazy singleton, depends on `ApiClient`),
  `DashboardRepository` (lazy singleton, `DashboardRepositoryImpl`), and `SettingsBloc` (factory — screen-
  scoped, never a singleton, per contracts/settings-bloc.md's own lifetime note) in
  `lib/core/di/service_locator.dart`, following the existing `ExportBloc`/`RecordsBloc` registration
  pattern (depends on T025, T026, T029 — registrations for the US2/US3 dependencies this bloc also needs are
  added incrementally in those phases' own DI tasks, T047 and T057)

**Checkpoint**: User Story 1 is fully functional and independently testable — opening Settings for any of
the four quickstart.md Story-1 account states renders the correct chart/narrative combination.

---

## Phase 4: User Story 2 - Deleting your account for good (Priority: P1)

**Goal**: "Apagar conta" opens a destructive confirmation dialog; confirming permanently deletes the account
and wipes every local trace; cancelling does nothing.

**Independent Test**: Tap "Apagar conta", confirm through the dialog, and verify the account can no longer
log in and Settings is left entirely with no residual session (quickstart.md Story 2).

### Tests for User Story 2

- [X] T036 [P] [US2] Test for `AccountDeletionRepositoryImpl.deleteAccount()` in
  `test/features/settings/data/account_deletion_repository_impl_test.dart` covering
  contracts/account-deletion-repository.md's scenario table: 200 `{data: {ok: true}}` → `Right(unit)`; Dio
  timeout → `Left(NetworkTimeoutFailure)`; no connection → `Left(NetworkOfflineFailure)`; 200 with
  `data.ok` missing/not `true` → `Left(ValidationFailure)`; 401 `AUTH_EXPIRED` → `Left(AuthExpiredFailure)`
  (no retry attempted — confirm the request is sent exactly once, never silently refreshed-and-resent);
  also assert the request body is always exactly `{"confirmation": "DELETE"}`
- [X] T037 [P] [US2] Bloc test for `DeleteAccountConfirmed` in
  `test/features/settings/presentation/bloc/settings_bloc_test.dart` (shared file, extended across phases)
  covering: `Right` result → `SessionRepository.clear()`, `AccountProfileRepository
  .clearCachedDisplayName()`, `EntriesRepository.clearLocalData()`, `ChatRepository.clearLocalData()` are all
  called, and `accountDeletedDestination` resolves to `vault` when `VaultRepository.hasPinConfigured()` is
  `true` / `login` when `false`; `Left` result → `deleteFailureMessage` set, no local state cleared, dialog
  stays open; a second `DeleteAccountConfirmed` while `isDeletingAccount == true` triggers no second call
  (FR-022, research.md R12); `Left(AuthExpiredFailure)` after a failed silent refresh additionally emits
  exactly one event on `settingsBloc.reauthRequired` (contracts/account-deletion-repository.md #5)

### Implementation for User Story 2

- [X] T038 [US2] Create `AccountDeletionRemoteDataSource` in
  `lib/features/settings/data/account_deletion_remote_data_source.dart` calling `account-delete`
  (`DELETE /account`) with body `{"confirmation": "DELETE"}` always supplied internally — no caller parameter
  for it (FR-018)
- [X] T039 [US2] Implement `AccountDeletionRepositoryImpl` in
  `lib/features/settings/data/account_deletion_repository_impl.dart` implementing
  `AccountDeletionRepository`, treating a 200 with `data.ok` missing or not `true` as
  `Left(ValidationFailure)`, with **no** retry-on-`AuthExpiredFailure` (contracts/
  account-deletion-repository.md — an expired session here surfaces as a plain failure and fires
  `reauthRequired`, letting the existing overlay take over rather than silently re-sending a destructive
  request) (depends on T009, T038)
- [X] T040 [US2] Add `DeleteAccountDialogOpened`, `DeleteAccountDialogCancelled`, and
  `DeleteAccountConfirmed` events to `lib/features/settings/presentation/bloc/settings_event.dart`
  (depends on T027)
- [X] T041 [US2] In `SettingsBloc` (`lib/features/settings/presentation/bloc/settings_bloc.dart`): handle
  `DeleteAccountDialogOpened`/`DeleteAccountDialogCancelled` as presentation-only toggles of
  `deleteDialogOpen` with **no** backend call on cancel (FR-021); handle `DeleteAccountConfirmed` per
  contracts/account-deletion-repository.md — guard on `isDeletingAccount` (FR-022), set it `true`, call
  `AccountDeletionRepository.deleteAccount()`; on `Right(unit)`: call `SessionRepository.clear()`,
  `AccountProfileRepository.clearCachedDisplayName()`, `EntriesRepository.clearLocalData()`,
  `ChatRepository.clearLocalData()`, then resolve `accountDeletedDestination` via
  `VaultRepository.hasPinConfigured()` (`vault` if `true`, `login` if `false` — research.md R10); on `Left`:
  set `deleteFailureMessage`, leave the dialog open, fire `reauthRequired` if the failure is
  `AuthExpiredFailure` (depends on T029, T039, T040)
- [X] T042 [P] [US2] Create `lib/features/settings/presentation/widgets/delete_account_dialog.dart`: a
  centered `AlertDialog` with red title "Apagar sua conta?", explanatory text stating the action is
  permanent and irreversible, a red "Apagar tudo" button (dispatches `DeleteAccountConfirmed`), and an
  outline "Cancelar" button (dispatches `DeleteAccountDialogCancelled`), showing `deleteFailureMessage`
  inline when set (FR-017/FR-020), reusing `DesignTokens.colorError`/`textTitleLg`/`textBodyMd`/`radiusLg`/
  `elevation2` (the same confirmation-dialog component shape the session-expired overlay already uses)
- [X] T043 [US2] In `settings_page.dart` (`lib/features/settings/presentation/pages/settings_page.dart`):
  add a `BlocListener<SettingsBloc, SettingsState>` with `listenWhen` on
  `signedOutDestination`/`accountDeletedDestination` becoming non-null, performing `context.go()` to
  `AppRoutes.vault`/`AppRoutes.login` (research.md R10); show `DeleteAccountDialog` via `showDialog` while
  `deleteDialogOpen == true`, auto-closing it on the destination-change listener firing in the same frame;
  add the "Apagar conta" destructive button to the page that dispatches `DeleteAccountDialogOpened` (depends
  on T033, T041, T042)
- [X] T044 [US2] Add the following `DI` registrations to `lib/core/di/service_locator.dart`:
  `AccountDeletionRemoteDataSource` (lazy singleton, depends on `ApiClient`), `AccountDeletionRepository`
  (lazy singleton, `AccountDeletionRepositoryImpl`); update the existing `SettingsBloc` factory registration
  (from T035) to also pass `accountDeletionRepository: getIt<AccountDeletionRepository>()` (depends on T038,
  T039, T035)

**Checkpoint**: User Stories 1 AND 2 both work independently — the dashboard renders correctly and account
deletion (confirm/cancel/fail/double-tap-guard) behaves exactly per quickstart.md Story 2.

---

## Phase 5: User Story 3 - Signing out and managing your profile (Priority: P2)

**Goal**: The profile header (avatar, name, email), inline name editing, the biometric toggle (hidden on
incapable devices), and "Sair" all work from the same screen.

**Independent Test**: Edit the display name and confirm it persists after reopening the app; flip the
biometric toggle and confirm it saves (or reverts on failure); tap "Sair" and confirm the session ends
(quickstart.md Story 3).

### Tests for User Story 3

- [X] T045 [P] [US3] Test for `AccountProfileRepositoryImpl` in
  `test/features/settings/data/account_profile_repository_impl_test.dart` covering
  contracts/account-profile-repository.md's scenario table: `readCachedDisplayName()` returns the cached
  value or `null`; `updateDisplayName(name)` — 200 with `displayName` 1–80 chars → `Right(name)` with the
  **response's** `data.displayName` (not the caller's input string) written to the local cache; Dio timeout
  → `Left(NetworkTimeoutFailure)`, cache unchanged; no connection → `Left(NetworkOfflineFailure)`, cache
  unchanged; 200 with `displayName` missing from the response → `Left(ValidationFailure)`, cache unchanged;
  401 `AUTH_EXPIRED` + successful silent refresh → retried call's own result; 401 `AUTH_EXPIRED` + failed
  silent refresh → `Left(AuthExpiredFailure)`, cache unchanged; `clearCachedDisplayName()` deletes the one
  Keychain key
- [X] T046 [P] [US3] Test for `AuthRepositoryImpl.logout()` in
  `test/features/auth/data/auth_repository_impl_test.dart` (extends the existing test file) covering: 200
  response (any `ok` value) → `Right(unit)`; confirms `SecureTokenStorage`/`SessionRepository.clear()` is
  **not** called by this method itself (contracts/account-session-actions.md)
- [X] T047 [P] [US3] Test for `SaveSettingsBiometricPreferenceUseCase` in
  `test/features/settings/domain/usecases/save_settings_biometric_preference_usecase_test.dart` against
  `mocktail` fakes of `BiometricsPreferenceRepository`/`VaultRepository`, covering
  contracts/biometric-preference-settings-extension.md's scenario table #3/#4/#5: `save()` → `Right` calls
  `setBiometricPreferenceLocally` and returns `Right(null)`; `save()` → `Left` returns the failure untouched
  and does **not** call `setBiometricPreferenceLocally`
- [X] T048 [US3] Bloc tests for `NameEditStarted`/`NameDraftChanged`/`NameEditCancelled`/`NameEditSubmitted`,
  `BiometricToggleChanged`, and `SignOutRequested` in
  `test/features/settings/presentation/bloc/settings_bloc_test.dart` (shared file, extended) covering: empty
  or >80-char `nameDraft` submit → `nameEditFailureMessage` set, stays `editing`, **no** repository call
  (FR-011); valid submit succeeding → `displayName` updates, `nameEditStatus → viewing`; valid submit
  failing → stays `editing` with `nameDraft` intact, retryable message (FR-012); toggle flip succeeding →
  `biometricEnabled` reflects the new value, mirror updated; toggle flip failing → `biometricEnabled` reverts
  to the pre-flip value, `biometricFailureMessage` set (FR-014); `SignOutRequested` → `logout()`,
  `SessionRepository.clear()`, `AccountProfileRepository.clearCachedDisplayName()` all called regardless of
  `logout()`'s own result, then `signedOutDestination` resolved via `hasPinConfigured()`; a second
  `SignOutRequested` while `isSigningOut == true` triggers no second `logout()` call (FR-022); a name-save
  failure and a toggle-flip failure that are each specifically `Left(AuthExpiredFailure)` (after a failed
  silent refresh) additionally emit exactly one event on `settingsBloc.reauthRequired`
  (contracts/account-profile-repository.md #6, contracts/biometric-preference-settings-extension.md #5)

### Implementation for User Story 3

- [X] T049 [P] [US3] Create `AccountSettingsRemoteDataSource.updateDisplayName()` in
  `lib/features/settings/data/account_settings_remote_data_source.dart` sending `PATCH
  account-settings-update` with body `{"displayName": name}` only (never `persona`, FR-015), returning the
  decoded `data.displayName` from the response
- [X] T050 [P] [US3] Create `AccountProfileLocalCache` in
  `lib/features/settings/data/account_profile_local_cache.dart` (Keychain-backed via
  `flutter_secure_storage`, one key `settingsDisplayName`, same pattern as `VaultSecureStorage`): `Future<
  String?> read()`, `Future<void> write(String name)`, `Future<void> clear()`
- [X] T051 [US3] Implement `AccountProfileRepositoryImpl` in
  `lib/features/settings/data/account_profile_repository_impl.dart` implementing
  `AccountProfileRepository`: `readCachedDisplayName()` delegates to `AccountProfileLocalCache.read()`;
  `updateDisplayName(name)` calls `AccountSettingsRemoteDataSource.updateDisplayName()`, and on `Right`
  writes the **response's own** `data.displayName` to `AccountProfileLocalCache.write()` before returning
  `Right` (contracts/account-profile-repository.md — "defensive against the backend ever normalizing the
  value"), applying the retry-once-on-`AuthExpiredFailure` shape; `clearCachedDisplayName()` delegates to
  `AccountProfileLocalCache.clear()` (depends on T008, T049, T050)
- [X] T052 Implement `logout()` on `AuthRemoteDataSource`/`AuthRepositoryImpl` — **already completed in
  Phase 2 (T012/T013)**; this entry exists only to record that no further `auth/` work remains for US3
- [X] T053 [US3] Add `NameEditStarted`, `NameDraftChanged(String value)`, `NameEditCancelled`,
  `NameEditSubmitted`, `BiometricToggleChanged(bool value)`, and `SignOutRequested` events to
  `lib/features/settings/presentation/bloc/settings_event.dart` (depends on T027)
- [X] T054 [US3] In `SettingsBloc`: extend the `SettingsOpened` handler to also load the profile
  (`SessionRepository`'s cached `Account.email` + `AccountProfileRepository.readCachedDisplayName()`,
  falling back to `AccountProfile.defaultDisplayNameFromEmail(email)` when the cache is empty) and the
  biometric state (`VaultRepository.checkBiometricCapability()` → `biometricToggleVisible = (capability ==
  BiometricCapability.available)`; `biometricEnabled` read from `isBiometricPreferenceEnabled()` only when
  visible, else `false` — contracts/biometric-preference-settings-extension.md); handle
  `NameEditStarted` (`nameEditStatus → editing`, `nameDraft` seeded from current `displayName`),
  `NameDraftChanged` (updates `nameDraft` only), `NameEditCancelled` (`nameEditStatus → viewing`, `nameDraft`
  discarded), `NameEditSubmitted` (validate via `AccountProfile.isValidDisplayName` first — on failure, set
  `nameEditFailureMessage`, stay `editing`, no repository call per FR-011; on pass, call
  `AccountProfileRepository.updateDisplayName`; `Right` → `displayName` updates, `nameEditStatus → viewing`;
  `Left` → stay `editing` with `nameDraft` intact, retryable message per FR-012); handle
  `BiometricToggleChanged` (optimistically flip `biometricEnabled`, call
  `SaveSettingsBiometricPreferenceUseCase`; `Left` → revert + `biometricFailureMessage`); handle
  `SignOutRequested` per contracts/account-session-actions.md's exact sequence — guard on `isSigningOut`
  (FR-022), set it `true`, `await authRepository.logout()` (result discarded), `await
  sessionRepository.clear()`, `await accountProfileRepository.clearCachedDisplayName()`, resolve
  `signedOutDestination` via `hasPinConfigured()` (depends on T010, T029, T051, T053)
- [X] T055 [P] [US3] Create `lib/features/settings/presentation/widgets/profile_header.dart`: 52px
  (`DesignTokens.sizeAvatarSettings`) initials avatar (`AccountProfile(...).initials`), the current
  `displayName` with an inline pencil-to-check control (pencil dispatches `NameEditStarted`, becomes a check
  icon in `editing`/`saving` states that dispatches `NameEditSubmitted`), a `TextField` bound to `nameDraft`
  (dispatching `NameDraftChanged` `onChanged`) shown only while editing, inline validation/failure message
  display (`nameEditFailureMessage`), and the read-only `email` text with no edit affordance beside it
  (FR-009)
- [X] T056 [P] [US3] Create `lib/features/settings/presentation/widgets/biometric_toggle_row.dart`: renders
  nothing when `biometricToggleVisible == false` (FR-013's "hidden entirely" rule — not a disabled row); a
  `Switch` bound to `biometricEnabled` dispatching `BiometricToggleChanged` on change, showing
  `biometricFailureMessage` inline when set
- [X] T057 [US3] In `settings_page.dart`: add `ProfileHeader` and `BiometricToggleRow` to the page body (below
  the dashboard section built in T033), and a "Sair" action (`TextButton`/`ListTile`) dispatching
  `SignOutRequested`; wire the `reauthRequired` subscription in `initState()` forwarding to
  `context.read<SessionBloc>().add(const AuthExpiredDetected())` (contracts/settings-bloc.md); make
  `SettingsPageState` `RouteAware`, subscribing to `chatRouteObserver` in `didChangeDependencies()` and
  dispatching `const SettingsOpened()` from `didPopNext()` (research.md R15), unsubscribing in `dispose()`
  (depends on T033, T054, T055, T056)
- [X] T058 [US3] Extend `_AppDrawerState` in `lib/features/home/presentation/widgets/app_drawer.dart`
  (contracts/app-drawer-display-name-extension.md): delete `_displayNameFromEmail`/`_initialsFromEmail`/
  `_emailNameWords`; resolve the displayed name via `getIt<AccountProfileRepository>()
  .readCachedDisplayName()` falling back to `AccountProfile.defaultDisplayNameFromEmail(email)` when the
  cached value is `null`; change the avatar's `Text` child to use
  `AccountProfile(displayName: displayName ?? '?', email: ...).initials` instead of the deleted
  `_initialsFromEmail(email)` call (depends on T006, T008, T051)
- [X] T059 [US3] Add the following `DI` registrations to `lib/core/di/service_locator.dart`:
  `AccountSettingsRemoteDataSource` (lazy singleton, depends on `ApiClient`), `AccountProfileLocalCache`
  (lazy singleton), `AccountProfileRepository` (lazy singleton, `AccountProfileRepositoryImpl`),
  `SaveSettingsBiometricPreferenceUseCase` (lazy singleton, depends on
  `BiometricsPreferenceRepository`/`VaultRepository`); update the `SettingsBloc` factory registration (from
  T035/T044) to also pass `accountProfileRepository`, `authRepository: getIt<AuthRepository>()`,
  `sessionRepository: getIt<SessionRepository>()`,
  `saveSettingsBiometricPreferenceUseCase: getIt<SaveSettingsBiometricPreferenceUseCase>()`,
  `vaultRepository: getIt<VaultRepository>()` (depends on T049, T050, T051, T010, T035)

**Checkpoint**: All three user stories are independently functional — profile editing, biometric toggle, and
sign-out all work per quickstart.md Story 3, on top of the already-working dashboard (US1) and account
deletion (US2).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final structural cleanup, the placeholder-page deletion, and the project-wide coverage/manual-
validation gates named in plan.md's Constitution Check.

- [X] T060 Delete `lib/features/settings/presentation/pages/settings_placeholder_page.dart` (its one
  reference, `app_router.dart`'s route builder, was already repointed in T034)
- [X] T061 [P] Confirm `test/architecture/domain_purity_test.dart` still passes with `features/settings/domain/`
  importing only `equatable`/`fpdart`/`core/network/failure.dart` (no `package:flutter`, no
  `settings/data/` class) — re-run after all phases, not just the Phase-2 check in T022
- [X] T062 [P] Confirm `test/architecture/no_bloc_imports_bloc_test.dart` still passes with `SettingsBloc`'s
  final dependency surface — zero imports of any other feature's `presentation/bloc/` path
- [X] T063 Run `fvm flutter test --coverage` and confirm `lib/features/settings/domain/**` (plus the touched
  portions of `lib/features/auth/domain/`, `lib/features/entries/domain/`, `lib/features/chat/domain/`) meets
  the existing `lib/**/domain/**` lcov filter's ≥80% threshold (RNF07)
- [ ] T064 Execute quickstart.md's full manual walkthrough (Stories 1–3 plus Edge Cases) against a running
  backend on an iOS simulator/device, including the session-expiry-mid-screen edge case and the double-tap
  guards for "Apagar tudo"/"Sair" (FR-022)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup. Blocks all three user story phases — every story's
  `SettingsBloc` work depends on the entities/repository interfaces/usecase/extensions defined here.
- **User Story 1 (Phase 3)**: Depends on Phase 2. Also creates the shared `settings_event.dart`/
  `settings_state.dart`/`settings_bloc.dart`/`settings_page.dart` files that Phases 4 and 5 extend in place.
- **User Story 2 (Phase 4)**: Depends on Phase 2 and on Phase 3's creation of `settings_bloc.dart`/
  `settings_page.dart` (it extends those files rather than creating new ones) — cannot start in true
  parallel with Phase 3 on those shared files, though its own new files (T038, T039, T042) can be built
  ahead of time.
- **User Story 3 (Phase 5)**: Same shared-file dependency on Phase 3 as Phase 4; independent of Phase 4's
  own new files otherwise.
- **Polish (Phase 6)**: Depends on Phases 3, 4, and 5 all being complete.

### User Story Dependencies

- **US1**: No dependency on US2/US3's own logic — the dashboard section is fully self-contained once Phase
  2 is done.
- **US2**: No functional dependency on US1 beyond sharing `settings_bloc.dart`/`settings_page.dart` as files
  (the delete flow reads no dashboard state).
- **US3**: No functional dependency on US1/US2 beyond the same shared files; profile/biometric/sign-out
  logic is independent of both.

### Within Each User Story

- Tests before implementation where both exist for the same unit of work.
- Data sources before repository impls; repository impls before bloc handlers; bloc handlers before widgets
  that dispatch their events; widgets before the page that assembles them; DI registration last (needs the
  concrete classes to exist).

### Parallel Opportunities

- All Phase 2 entity tasks (T003–T006) are `[P]` — different files, no interdependency beyond T004 extending
  the same file T003 creates (sequential within that one file, parallel with T005/T006).
- All Phase 2 repository-interface tasks (T007–T009) are `[P]`.
- The three existing-feature extension tracks (`auth`: T011→T012→T013; `entries`: T014/T015→T016; `chat`:
  T017/T018→T019) are mutually `[P]` as tracks, sequential within each track.
- T020/T021 (foundational tests) are `[P]`.
- Within US1: T023/T024 (tests, same file but independent scenario groups — write together), T025 alongside
  T027/T028 are `[P]`; T030/T031/T032 (three independent widget files) are `[P]`.
- Within US2: T036/T037 are `[P]`; T042 is `[P]` with the bloc-handler work (T041).
- Within US3: T045/T046/T047 are `[P]`; T049/T050 are `[P]`; T055/T056 are `[P]`.

---

## Parallel Example: Phase 2 Foundational

```bash
# Launch independent entity/repository-interface creation together:
Task: "Create DashboardSourceCounts/AggregateBucket/DashboardTotals in dashboard_aggregate.dart"
Task: "Create DashboardNarrative in dashboard_narrative.dart"
Task: "Create AccountProfile in account_profile.dart"
Task: "Create DashboardRepository interface"
Task: "Create AccountProfileRepository interface"
Task: "Create AccountDeletionRepository interface"

# Launch the three independent existing-feature-extension tracks together:
Task: "auth: add logout() to AuthRepository interface"
Task: "entries: add clear() to EntriesLocalCache"
Task: "chat: add clear() to ChatLocalCache"
```

## Parallel Example: User Story 1

```bash
Task: "Test DashboardRepositoryImpl.fetchAggregate() scenarios"
Task: "Test DashboardRepositoryImpl.fetchNarrative() scenarios"

Task: "Create DashboardBarChart widget"
Task: "Create DashboardCard widget"
Task: "Create NarrativeView widget"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks everything).
3. Complete Phase 3: User Story 1.
4. **STOP and VALIDATE**: Run quickstart.md Story 1's five numbered checks against accounts A–D.
5. Settings now shows a correct, real dashboard in place of the placeholder — a demoable increment even
   before account deletion or profile editing exist.

### Incremental Delivery

1. Setup + Foundational → shared foundation ready.
2. Add User Story 1 → validate independently → the dashboard is live (MVP).
3. Add User Story 2 → validate independently → "Apagar conta" is live, RNF05's compliance gate satisfied.
4. Add User Story 3 → validate independently → profile editing, biometrics, and "Sair" complete the screen.
5. Phase 6 polish (placeholder deletion, architecture re-checks, coverage, full quickstart) closes the unit.

### Parallel Team Strategy

With multiple developers, once Phase 2 is done: one developer takes US1 (and creates the shared bloc/page
files), while a second prepares US2's and a third prepares US3's own new files (data sources, repository
impls, widgets) ahead of time — the only serialization point is each one's final bloc-handler/page-wiring
task (T041/T043, T054/T057), which must land after Phase 3's T029/T033 exist.

---

## Notes

- [P] tasks = different files, no dependencies.
- [Story] label maps task to US1/US2/US3 for traceability; Foundational/Setup/Polish tasks carry none.
- `settings_event.dart`, `settings_state.dart`, `settings_bloc.dart`, and `settings_page.dart` are each
  created once (Phase 3) and extended in place by Phases 4 and 5 — not recreated.
- Verify tests fail before implementing, where tests are written first.
- Commit after each task or logical group.
- Stop at any checkpoint to validate a story independently.
- Avoid: vague tasks, same-file conflicts within a single phase's `[P]` group, cross-story dependencies that
  would break independent testability.
