---

description: "Task list for P-F000 — Foundation"
---

# Tasks: P-F000 — Foundation

**Input**: Design documents from `/specs/001-foundation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (http-client.md,
failure-taxonomy.md, auth-repository.md, session-repository.md), quickstart.md — all present.

**Tests**: Included. `plan.md`'s Constitution Check marks RNF07 (domain coverage ≥80%) as
"PASS (gate carried into tasks)" and RNF09 requires 15/15 write-endpoint failure scenarios covered
by `mocktail`; `quickstart.md`'s Automated checks run `flutter test --coverage` against a
`lib/**/domain/**` lcov filter. Domain-layer unit tests (`mocktail`) and bloc tests (`bloc_test`)
are therefore generated per story; User Story 4 (pure navigation/presentation, no domain code) has
none, matching the domain-only scope of the gate.

**Organization**: Tasks are grouped by user story (P1–P5 from spec.md) to enable independent
implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on an incomplete task)
- **[Story]**: US1–US5, mapping to spec.md's five user stories
- Exact file paths are given per plan.md's Project Structure

## Path Conventions

Single Flutter app at the repo root: `lib/`, `test/` (plan.md Project Structure; no
`backend/`/`api/` tree — the backend is frozen and consumed only through `docs/input/backend/`).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the Flutter project itself; nothing in `lib/` exists yet in this repo.

- [X] T001 Run `fvm install 3.47.5` (if not already the cached default) and `fvm use 3.47.5` at the
  repo root, writing `.fvmrc`; then `fvm flutter create .` to scaffold the Flutter project in place
  (iOS platform only — remove/ignore the android/, web/, etc. platform folders `flutter create`
  generates, per plan.md Target Platform: "iOS, portrait orientation only") (research.md R1)
- [X] T002 Add to `pubspec.yaml` dependencies: `flutter_bloc`, `fpdart`, `dio`, `go_router`,
  `get_it`, `flutter_secure_storage`, `equatable`, `flutter_dotenv` (the last is this task's own
  reasonable choice for loading the repo-root `.env`'s `FUNCTIONS_BASE_URL`/`SUPABASE_ANON_KEY`,
  per Constitution Principle I — the stack list leaves env loading unfixed); dev dependencies:
  `mocktail`, `bloc_test` (plan.md Technical Context, Constitution Principle II)
- [X] T003 [P] Configure `analysis_options.yaml` with the standard Flutter lint set plus
  `avoid_relative_lib_imports`/import-ordering rules that make a `package:flutter` or `data/` import
  inside any `domain/` folder a visible lint failure (supports RNF06's "0 layer violations" gate,
  checked at Polish phase by `flutter analyze`)
- [X] T004 [P] Obtain and vendor the Fraunces, Karla, and IBM Plex Mono font files under
  `assets/fonts/`, and declare them under `flutter: fonts:` in `pubspec.yaml` with the weights used
  by `design_tokens.dart` (600 for Fraunces, 400/500/700 for Karla, 500 for IBM Plex Mono) — bundled
  as local assets, not `google_fonts`, per research.md R9

**Checkpoint**: `fvm flutter pub get` succeeds; project scaffold exists.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The design-token source, the `Either<Failure, T>` network stack, secure storage,
routing skeleton, and DI wiring that every user story below depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 [P] Create `lib/core/design_tokens.dart`: 14 panel colors (`colorPrimary #1F3D34`,
  `colorPrimaryPressed #16281F`, `colorOnPrimary #F5F1E8`, `colorAccent #C98A3E`,
  `colorOnAccent #241C0D`, `colorSecondary #7C8B6F`, `colorSurfaceBg #F2EFE7`,
  `colorSurfaceElevated #FBF9F4`, `colorBorder #E1DACB`, `colorTextPrimary #241F19`,
  `colorTextSecondary #6B6255`, `colorError #B3402A`, `colorSuccess #4C6B4F`,
  `colorWarningSync #C98A3E`, `colorInfoOffline #5C7A93`) plus `colorChatBubbleUser #D9DFD3` (used
  by this unit's Home/Chat shell); 8 `TextStyle` constants exactly as prototype-extract.md §3 states
  (`textDisplayLg` Fraunces 600·32/38, `textHeadlineMd` Fraunces 600·24/30, `textTitleLg` Karla
  700·20/26, `textTitleSm` Karla 700·16/22, `textBodyLg` Karla 400·16/24, `textBodyMd` Karla
  400·14/20, `textLabelMd` Karla 500·13/18, `textMonoCaption` IBM Plex Mono 500·12/16·letter-spacing
  0.2); spacing (`spacingXs` 4, `spacingSm` 8, `spacingMd` 16, `spacingLg` 24, `spacingXl` 32,
  `spacing2xl` 48, all `double` dp); radii (`radiusSm` 8, `radiusMd` 16, `radiusLg` 24, `radiusFull`
  999, all `double` dp); `elevation1`/`elevation2` as `BoxShadow`/`List<BoxShadow>` matching
  `0 1px 3px rgba(36,31,25,.08)` and `0 4px 16px rgba(36,31,25,.14)` — all as `static const` (data-model.md
  Design Tokens, RNF08/Principle IV: zero visual values hardcoded anywhere else)
- [X] T006 [P] Create `lib/core/theme.dart` building a single `ThemeData` solely from
  `design_tokens.dart` constants (color scheme, text theme, input/button themes) — no literal
  color/size value in this file either (depends on T005)
- [X] T007 [P] Create `lib/core/network/failure.dart`: `sealed class Failure extends Equatable` with
  `message`/`requestId` fields and the 13 closed-taxonomy subtypes, each with its fixed `code` and
  `retryable` pair exactly per contracts/failure-taxonomy.md (`AuthExpiredFailure`/`AUTH_EXPIRED`/
  false, `AuthInvalidFailure`/`AUTH_INVALID`/false, `NetworkTimeoutFailure`/`NETWORK_TIMEOUT`/true,
  `NetworkOfflineFailure`/`NETWORK_OFFLINE`/true, `ValidationFailure`/`VALIDATION_ERROR`/false,
  `PiiCheckFailedFailure`/`PII_CHECK_FAILED`/true, `EmbeddingFailedFailure`/`EMBEDDING_FAILED`/true,
  `AiGenerationTimeoutFailure`/`AI_GENERATION_TIMEOUT`/true, `NotFoundFailure`/`NOT_FOUND`/false,
  `RateLimitedFailure`/`RATE_LIMITED`/true, `ExportEmptyPeriodFailure`/`EXPORT_EMPTY_PERIOD`/false,
  `PayloadTooLargeFailure`/`PAYLOAD_TOO_LARGE`/false, `OcrNoTextFailure`/`OCR_NO_TEXT`/false); no
  `package:flutter` import (RNF06 — this file lives in the domain boundary)
- [X] T008 Create `lib/core/network/error_mapper.dart` with
  `ErrorMapper.fromResponse(Map<String, dynamic> body)` performing the exhaustive `code` → `Failure`
  subtype switch; an unrecognized `code` MUST NOT throw — map it to a defensive `ValidationFailure`
  instead (contracts/failure-taxonomy.md; FR-003 "never an unhandled crash") (depends on T007)
- [X] T009 [P] Create `lib/core/storage/secure_token_storage.dart` wrapping
  `flutter_secure_storage` with read/write/delete for `accessToken`, `refreshToken`, `expiresAt`
  (int, unix seconds), `tokenType` — iOS Keychain-backed, never plaintext (data-model.md Session;
  research.md R5)
- [X] T010 Create `lib/core/network/api_client.dart`'s `ApiClient` class and `AuthMode` enum exactly
  per contracts/http-client.md: `call(String function, {required String method, body, pathSegments,
  authMode = AuthMode.userSession})`; URL = `{FUNCTIONS_BASE_URL}/<function>/<pathSegments...>` read
  from `.env` via `flutter_dotenv` (never the OpenAPI REST-notation path — Principle III, FR-005);
  every call carries `apikey: <SUPABASE_ANON_KEY>`; `Authorization` is `Bearer <SUPABASE_ANON_KEY>`
  for `AuthMode.anonKey` or `Bearer <stored accessToken>` (from `SecureTokenStorage`) for
  `AuthMode.userSession`; success → `Right(data)` (the response envelope's `data` object, `meta`
  discarded); non-2xx with `{code,message,retryable,requestId}` body → `ErrorMapper.fromResponse(...)`
  → `Left(Failure)`; a dio connection-error/no-response condition → `Left(NetworkOfflineFailure(...))`
  directly, without a parse attempt; a dio timeout → `Left(NetworkTimeoutFailure(...))`; every dio
  exception is caught here — this boundary never throws (depends on T007, T008, T009)
- [X] T011 [P] Create `lib/features/auth/domain/entities/account.dart`: `Account` with `id` (String,
  uuid) and `email` (String) fields, `Equatable` — password is never a field on this entity
  (data-model.md Account)
- [X] T012 [P] Create `lib/features/session/domain/entities/session.dart`: `Session` with
  `accessToken` (String), `refreshToken` (String), `expiresAt` (int, unix seconds), `tokenType`
  (String), `account` (`Account`) — `Equatable` (data-model.md Session) (depends on T011)
- [X] T013 [P] Create `lib/features/session/domain/entities/session_status.dart`: sealed
  `SessionStatus` with variants `checking`, `authenticated(Session)`, `expiredRenewable`,
  `unauthenticated` (data-model.md Derived state — `SessionStatus`) (depends on T012)
- [X] T014 Create `lib/core/routing/app_router.dart` (a `go_router` `GoRouter` with a root
  `navigatorKey` exposed for the session-expired overlay to raise a dialog over any screen) and
  `lib/core/routing/app_routes.dart` (named route constants: splash, login, home, records,
  settings); screen-to-screen navigation from the side menu uses `context.push`, never `go`/replace
  (research.md R3 — required so Flutter never disposes the covered screen's `State`, per FR-011/
  User Story 4 and FR-013/FR-014/User Story 5)
- [X] T015 Create `lib/core/di/service_locator.dart` registering, as singletons: `Dio`, `ApiClient`,
  `SecureTokenStorage` via `get_it` (manual registration, no code generation — research.md R4)
  (depends on T009, T010)
- [X] T016 Create `lib/main.dart`: load `.env` via `flutter_dotenv` before `runApp`, lock the app to
  portrait orientation (`SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown])` per plan.md Target Platform), call the service-locator setup
  from T015, and run `MaterialApp.router` with the `ThemeData` from T006 and the `GoRouter` from
  T014 (depends on T006, T014, T015)

**Checkpoint**: Foundation ready — `ApiClient`, `Failure`, secure storage, routing, DI, and the
design-token/theme source all exist; user story implementation can now begin in priority order.

---

## Phase 3: User Story 1 - Returning user logs in (Priority: P1) 🎯 MVP

**Goal**: A user with an existing account enters email/password on the login screen and reaches
Home/Chat.

**Independent Test**: Submit valid credentials on the login screen and confirm the app lands on
Home/Chat; delivers a working, demonstrable access path on its own.

### Tests for User Story 1 ⚠️

> Write these first; confirm they fail before the implementation tasks below make them pass.

- [X] T017 [P] [US1] Unit test `LoginUseCase` (mocktail `AuthRepository` double): delegates to
  `repository.login(...)` and returns its `Either` unchanged, for both `Right(Session)` and every
  `Left(Failure)` branch — `test/features/auth/domain/usecases/login_usecase_test.dart`
- [X] T018 [P] [US1] Unit test `AuthRepositoryImpl.login` (mocktail `ApiClient` + `SecureTokenStorage`
  doubles): `Right(data)` from `ApiClient` is parsed into `Session`/`Account` and persisted via
  `SecureTokenStorage` *before* the method returns `Right(session)`; `Left(Failure)` from
  `ApiClient` passes through unchanged with no storage write —
  `test/features/auth/data/auth_repository_impl_test.dart`
- [X] T019 [P] [US1] Unit test `AuthRemoteDataSource.login`: calls
  `apiClient.call('auth-login', method: 'POST', body: {'email': ..., 'password': ...}, authMode:
  AuthMode.anonKey)`; covers `NetworkTimeoutFailure`, a malformed/unparseable success body,
  `NetworkOfflineFailure` (3 of RNF09's 15 write-endpoint failure scenarios), and `ValidationFailure`
  (backend rejects the submission as malformed — Edge Cases: "shown and handled distinctly from a
  timeout or offline condition") — `test/features/auth/data/auth_remote_data_source_test.dart`
- [X] T020 [P] [US1] `bloc_test` for `AuthBloc`'s login flow: submit → loading state → authenticated
  state (valid credentials); submit → `AuthInvalidFailure` state (wrong credentials, non-crashing,
  stays retryable); submit with no network → `NetworkOfflineFailure` state, retryable; a second
  `LoginSubmitted` event dispatched while state is already `AuthLoading` is ignored — no second
  network call is made, preventing a backgrounded-resume double-submit from creating a duplicate
  session (Edge Cases) — `test/features/auth/presentation/bloc/auth_bloc_test.dart`

### Implementation for User Story 1

- [X] T021 [P] [US1] Create `lib/features/auth/domain/repositories/auth_repository.dart`:
  `abstract class AuthRepository { Future<Either<Failure, Session>> signUp({required String email,
  required String password}); Future<Either<Failure, Session>> login({required String email,
  required String password}); }` (contracts/auth-repository.md) (depends on T007, T012)
- [X] T022 [US1] Create `lib/features/auth/domain/usecases/login_usecase.dart`: thin pass-through
  `LoginUseCase(AuthRepository)` calling `repository.login(...)` (contracts/auth-repository.md "Use
  cases wrapping this repository") (depends on T021)
- [X] T023 [US1] Create `lib/features/auth/data/auth_remote_data_source.dart`'s `login` method:
  calls `ApiClient.call('auth-login', method: 'POST', body: {'email': email, 'password': password},
  authMode: AuthMode.anonKey)` and parses the `session`/`user` objects into `Session`/`Account`
  (depends on T010, T011, T012)
- [X] T024 [US1] Create `lib/features/auth/data/auth_repository_impl.dart`'s `login` method:
  delegates to the remote data source; on `Right(session)`, calls
  `SecureTokenStorage` to persist `accessToken`/`refreshToken`/`expiresAt`/`tokenType` before
  returning `Right(session)` (depends on T023, T009, T021)
- [X] T025 [US1] Create `lib/features/auth/presentation/bloc/auth_bloc.dart`: states
  `AuthInitial`, `AuthLoading`, `AuthAuthenticated(Session)`, `AuthFailure(Failure)`; a
  `LoginSubmitted(email, password)` event invoking `LoginUseCase`; guards against a concurrent
  submit — e.g. ignore `LoginSubmitted`/`SignUpSubmitted` events while the current state is already
  `AuthLoading` (or use a `droppable()` event transformer) — satisfying the Edge Case "backgrounded
  mid-submission never produces a duplicate account or session" (depends on T022)
- [X] T026 [US1] Create `lib/features/auth/presentation/pages/login_signup_page.dart` in login mode:
  title "Bem-vindo de volta", fields "E-mail"/"Senha", CTA "Entrar"; blocks the network call and
  shows an inline validation message for an empty field (Edge Cases: "no network call made");
  renders `AuthFailure`'s message distinctly for `AuthInvalidFailure` vs. `ValidationFailure` vs.
  `RateLimitedFailure` vs. `NetworkTimeoutFailure`/`NetworkOfflineFailure` (retryable —
  FR-004/FR-015); any other `Failure` subtype falls back to its raw `message` with a generic retry
  affordance keyed off `retryable`, so FR-015 holds for the full taxonomy without one branch per
  code; shows a loading indicator once the call exceeds 300 ms (RNF01) — built entirely from
  `design_tokens.dart`/`theme.dart` (depends on T025, T005, T006)
- [X] T027 [US1] Register `AuthRepository` (→`AuthRepositoryImpl`), `AuthRemoteDataSource`,
  `LoginUseCase`, and `AuthBloc` (factory) in `service_locator.dart` (depends on T015, T021–T025)
- [X] T028 [US1] Create `lib/features/home/presentation/pages/home_chat_shell_page.dart`: fixed
  dark-green header (☰ icon, present but inert in this story; "Cerne" wordmark) and an empty
  conversation area, plus a composer bar that is rendered but fully disabled — text field
  non-editable, send button non-interactive, no fake messages (FR-016; research.md R10) (depends on
  T005, T006)
- [X] T029 [US1] Wire `app_router.dart`'s login route so that on `AuthBloc`'s `AuthAuthenticated`
  state the app `context.push`es to the Home/Chat route (depends on T014, T025, T028)

**Checkpoint**: User Story 1 is fully functional and testable independently — login → Home/Chat.

---

## Phase 4: User Story 2 - New user creates an account (Priority: P2)

**Goal**: A person without an account toggles to sign-up mode on the same screen, submits a new
email/password, and reaches Home/Chat as a newly created user.

**Independent Test**: Toggle to "Criar conta", submit a new email/password pair, and confirm an
account is created and the app lands on Home/Chat.

### Tests for User Story 2 ⚠️

- [X] T030 [P] [US2] Unit test `SignUpUseCase` (mocktail `AuthRepository` double), mirroring T017 for
  `signUp` — `test/features/auth/domain/usecases/sign_up_usecase_test.dart`
- [X] T031 [US2] Add `signUp` cases to `AuthRemoteDataSource` tests: calls `apiClient.call(
  'auth-signup', method: 'POST', body: {'email': ..., 'password': ...}, authMode:
  AuthMode.anonKey)`; covers `NetworkTimeoutFailure`, a malformed success body, and
  `NetworkOfflineFailure` (3 more of RNF09's 15 scenarios — 6/15 after this story), and
  `ValidationFailure` (backend rejects the submission as malformed — Edge Cases, mirroring T019) —
  `test/features/auth/data/auth_remote_data_source_test.dart` (same file as T019)
- [X] T032 [US2] Add `signUp` cases to `AuthRepositoryImpl` tests: success persists `Session` the
  same way as `login`; `Left(AuthInvalidFailure)` for an already-registered email passes through
  unchanged — `test/features/auth/data/auth_repository_impl_test.dart` (same file as T018)
- [X] T033 [US2] Add to `AuthBloc` bloc_test: a `ToggleModeRequested` event flips `AuthFormMode`
  between `login`/`signUp` with no network call; `SignUpSubmitted` → loading → authenticated for a
  new email; → `AuthInvalidFailure` state for an already-registered email; a second
  `SignUpSubmitted` event dispatched while state is already `AuthLoading` is ignored — no duplicate
  account creation (Edge Cases, mirroring T020) — `test/features/auth/presentation/bloc/auth_bloc_test.dart`
  (same file as T020)

### Implementation for User Story 2

- [X] T034 [US2] Add the `signUp` method to `auth_remote_data_source.dart` (same request shape as
  T023, function `auth-signup`) (same file as T023)
- [X] T035 [US2] Add the `signUp` method to `auth_repository_impl.dart` (same persistence step as
  T024's `login`) (same file as T024)
- [X] T036 [P] [US2] Create `lib/features/auth/domain/usecases/sign_up_usecase.dart`: thin
  pass-through `SignUpUseCase(AuthRepository)` (depends on T021)
- [X] T037 [US2] Extend `auth_bloc.dart`: add `AuthFormMode` (`login | signUp`, default `login`,
  reset to `login` each time the screen is (re-)entered — data-model.md Presentation-only state) to
  the bloc's state, a `ToggleModeRequested` event, and a `SignUpSubmitted(email, password)` event
  invoking `SignUpUseCase` (same file as T025; depends on T036)
- [X] T038 [US2] Extend `login_signup_page.dart`: the toggle link switches title "Bem-vindo de
  volta"/"Crie sua conta" and CTA "Entrar"/"Criar conta" in place (same screen, no navigation —
  FR-008); renders a clear, non-crashing error for an already-registered email, form stays editable;
  the same `AuthInvalidFailure`/`ValidationFailure`/`RateLimitedFailure`/`NetworkTimeoutFailure`/
  `NetworkOfflineFailure` distinction and generic fallback from T026 apply in sign-up mode (same
  file as T026)

**Checkpoint**: User Stories 1 AND 2 both work independently — login and sign-up both reach
Home/Chat.

---

## Phase 5: User Story 3 - App launches and routes by session state (Priority: P3)

**Goal**: On every launch, show a splash state, check for a usable session (renewing it first if
merely expired), and route to Home/Chat or the login screen — never stuck on splash.

**Independent Test**: Launch under three stored-session conditions (valid, expired-but-refreshable,
none) and confirm the correct landing screen each time.

### Tests for User Story 3 ⚠️

- [X] T039 [P] [US3] Unit test `CheckSessionUseCase` (mocktail `SessionRepository` double), exactly
  per contracts/session-repository.md's pseudocode: `hasStoredSession() == false` →
  `SessionStatus.unauthenticated`, no `checkSession()` call made; `checkSession()` → `Right` →
  `authenticated`; `checkSession()` → `Left(AuthExpiredFailure)` → calls `refresh()` → `Right` →
  `authenticated` / `Left` → calls `clear()` then → `unauthenticated`; `checkSession()` →
  `Left(NetworkTimeoutFailure)`/`Left(NetworkOfflineFailure)` → a network-error status, not a route
  change (research.md R7) — `test/features/session/domain/usecases/check_session_usecase_test.dart`
- [X] T040 [P] [US3] Unit test `SessionRepositoryImpl` (mocktail `SessionRemoteDataSource` +
  `SecureTokenStorage` doubles): `checkSession`/`refresh` pass through the data source's `Either`;
  `refresh`'s `Right` persists the new `Session` internally before returning; `persist`/`clear`
  delegate to `SecureTokenStorage`; `hasStoredSession` is true iff a `refreshToken` is stored —
  `test/features/session/data/session_repository_impl_test.dart`
- [X] T041 [P] [US3] Unit test `SessionRemoteDataSource`: `checkSession` calls `apiClient.call(
  'auth-session', method: 'GET', authMode: AuthMode.userSession)`; `refresh` calls `apiClient.call(
  'auth-refresh', method: 'POST', body: {'refreshToken': storedRefreshToken}, authMode:
  AuthMode.anonKey)`, covering `NetworkTimeoutFailure`, a malformed success body, and
  `NetworkOfflineFailure` for `refresh` (it is a write endpoint — 3 more of RNF09's 15 scenarios,
  9/15 total across F000's 3 write auth calls) — `test/features/session/data/session_remote_data_source_test.dart`
- [X] T042 [P] [US3] `bloc_test` for `SessionBloc`: an app-start event drives `checking` →
  `authenticated` (routes Home/Chat) / `unauthenticated` (routes Login) / a network-error state that
  keeps the splash screen with a retry affordance and makes no route change (R7) —
  `test/features/session/presentation/bloc/session_bloc_test.dart`

### Implementation for User Story 3

- [X] T043 [P] [US3] Create `lib/features/session/domain/repositories/session_repository.dart`:
  `abstract class SessionRepository { Future<Either<Failure, Session>> checkSession();
  Future<Either<Failure, Session>> refresh(); Future<void> persist(Session session); Future<void>
  clear(); Future<bool> hasStoredSession(); }` (contracts/session-repository.md) (depends on T007,
  T012)
- [X] T044 [US3] Create `lib/features/session/domain/usecases/check_session_usecase.dart`
  implementing the orchestration exactly as contracts/session-repository.md's `CheckSessionUseCase`
  pseudocode: no stored session → `unauthenticated`; `checkSession()` `AuthExpiredFailure` →
  `_tryRefresh()`; any other failure → a network-error `SessionStatus` (R7); `_tryRefresh()` failure
  → `clear()` then `unauthenticated` (depends on T043, T013)
- [X] T045 [US3] Create `lib/features/session/data/session_remote_data_source.dart`'s
  `checkSession`/`refresh` methods per the request shapes above (depends on T010)
- [X] T046 [US3] Create `lib/features/session/data/session_repository_impl.dart` implementing all 5
  `SessionRepository` methods; `refresh()`'s `Right` branch calls `persist()` internally before
  returning (depends on T045, T009, T043)
- [X] T047 [US3] Create `lib/features/session/presentation/bloc/session_bloc.dart`: an app-start
  event invokes `CheckSessionUseCase` and emits `checking`/`authenticated`/`unauthenticated`/a
  network-error `SessionStatus` (depends on T044)
- [X] T048 [US3] Create `lib/features/splash/presentation/pages/splash_page.dart`: wordmark "Cerne"
  centered on `colorPrimary`, loading dots; dispatches the app-start event to `SessionBloc` and
  listens for its state to route to Home/Chat or Login — on a network-error state, shows a visible
  retry action instead of routing away, and never leaves the user stuck (R7; FR-010; Edge Cases)
  (depends on T047, T005, T006)
- [X] T049 [US3] Register `SessionRepository` (→`SessionRepositoryImpl`), `SessionRemoteDataSource`,
  `CheckSessionUseCase`, and `SessionBloc` (factory) in `service_locator.dart` (depends on T015,
  T043–T047)
- [X] T050 [US3] Wire `app_router.dart`'s initial route to `SplashPage`, with the splash itself
  deciding the next destination: a valid stored session routes straight to Home/Chat with no
  credential re-entry; an expired-but-refreshable session silently calls `refresh()` and routes to
  Home/Chat with no prompt; no stored session routes to Login (depends on T014, T048)

**Checkpoint**: User Stories 1–3 all work — launch routing, login, and sign-up are fully
independent and composable.

---

## Phase 6: User Story 4 - Navigating between the main screens (Priority: P4)

**Goal**: From Home/Chat, open the side menu and reach Meus Registros or Configurações
(placeholders today) and back, without losing Home/Chat's state.

**Independent Test**: Open the side menu from Home/Chat, visit each destination, and return,
confirming Home/Chat's state is unchanged.

*No domain code is introduced by this story (pure navigation/presentation), so no test tasks are
generated — RNF07's coverage gate is domain-layer-only.*

### Implementation for User Story 4

- [X] T051 [P] [US4] Create `lib/features/records/presentation/pages/records_placeholder_page.dart`:
  "Meus Registros" header, a static "ainda não disponível"-style empty-state message, no
  entity/list data fetched (FR-012; data-model.md Placeholder Destination) (depends on T005, T006)
- [X] T052 [P] [US4] Create `lib/features/settings/presentation/pages/settings_placeholder_page.dart`:
  "Configurações" header, the same static placeholder pattern as T051 (FR-012) (depends on T005,
  T006)
- [X] T053 [US4] Create `lib/features/home/presentation/widgets/app_drawer.dart`: a plain
  `Drawer` widget (not a route) listing "Meus Registros" and "Configurações", each navigating via
  `context.push` to its placeholder route (research.md R3) (depends on T005, T006)
- [X] T054 [US4] Wire `home_chat_shell_page.dart`'s ☰ icon to open the `AppDrawer` via
  `Scaffold.drawer`; opening the drawer visibly scrims the current screen without resetting any of
  Home/Chat's state (e.g. scroll position) (same file as T028; depends on T053)
- [X] T055 [US4] Add `/records` and `/settings` routes (`context.push` targets) to
  `app_router.dart`/`app_routes.dart` (depends on T014, T051, T052)

**Checkpoint**: All main screens are reachable from the side menu and Home/Chat's state survives
round trips to either placeholder.

---

## Phase 7: User Story 5 - Session expires during active use (Priority: P5)

**Goal**: While a user is active on a screen, the backend session expires; an overlay explains this
and offers re-authentication, after which the user returns to exactly where they were.

**Independent Test**: Force a session-expired response while a screen is in a known state, confirm
the overlay appears over it unchanged, and confirm re-authentication restores that exact state.

### Tests for User Story 5 ⚠️

- [X] T056 [US5] Add to `SessionBloc` bloc_test: an `AuthExpiredDetected` event (raised by any
  authenticated call elsewhere in the app) triggers a silent `refresh()` first; `Right` → stays
  `authenticated`, no overlay-triggering state emitted; `Left` → emits `expiredRenewable` (the
  overlay's trigger state); a second `AuthExpiredDetected` arriving while already `expiredRenewable`
  re-emits `expiredRenewable` rather than proceeding with the stale session (Edge Cases) —
  `test/features/session/presentation/bloc/session_bloc_test.dart` (same file as T042)

### Implementation for User Story 5

- [X] T057 [US5] Extend `session_bloc.dart` with the `AuthExpiredDetected` handling described in
  T056 (same file as T047)
- [X] T058 [US5] Create `lib/features/session/presentation/widgets/session_expired_overlay.dart`: a
  non-dismissible `showDialog` raised through the root `navigatorKey` (T014) whenever `SessionBloc`
  emits `expiredRenewable` — centered card over a light scrim, lock icon, title "Sessão expirada",
  explanatory text, button "Entrar novamente" (research.md R3; prototype-extract.md §2.2) (depends
  on T014, T047, T005, T006)
- [X] T059 [US5] Wire "Entrar novamente" to `context.push` (never `go`/replace) the Login screen on
  top of the current one, so the underlying screen's `State` is never disposed; on a successful
  `AuthBloc` login, pop back to it, dismissing the overlay with the underlying screen's state (e.g.
  scroll position) restored exactly (FR-013/FR-014; User Story 5) (depends on T058, T025/T037, T014)
- [X] T060 [US5] Hook the overlay into the app root — a `BlocListener`/`BlocBuilder` around
  `MaterialApp.router`'s `builder` in `main.dart` watching `SessionBloc` globally, so `expiredRenewable`
  shows the overlay regardless of which screen is currently active (same file as T016) (depends on
  T058)

**Checkpoint**: All five user stories are independently functional — the Foundation unit is
complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Gate verification across all five stories (quickstart.md Automated checks / Expected
outcome).

- [X] T061 [P] Run `fvm flutter analyze` — 0 issues, and confirm by inspection that no file under
  any `domain/` folder imports `package:flutter` or a class from its feature's `data/` layer (RNF06)
- [X] T062 [P] Run `fvm flutter test --coverage`, extract the `lib/**/domain/**` lcov subset, and
  confirm ≥80% coverage (RNF07); add any missing domain-layer test case needed to close the gap
- [X] T063 Cross-check that all 9 of F000's write-endpoint failure scenarios are covered by
  `mocktail` tests (signup/login/refresh × timeout/malformed-response/no-connection — T019, T031,
  T041), toward RNF09's full 15/15 target across the whole delivery order
- [X] T064 [P] Spot-check every screen this unit ships (Splash, Login/Sign-up, Home/Chat, Meus
  Registros placeholder, Configurações placeholder, Sessão expirada overlay) for any color,
  typography, spacing, or radius value not traced to `design_tokens.dart` (RNF08/Principle IV; not
  yet an automated lint in this unit, per quickstart.md)
- [X] T065 Run quickstart.md's 5 manual/integration validation scenarios end-to-end on an iOS
  simulator/device, confirming every spec.md Acceptance Scenario they map to

---

## Phase 9: Convergence

- [X] T066 Add a mechanical, automatically-run check (e.g. a `flutter test` that walks `lib/**/domain/**`
  and fails if any file imports `package:flutter` or a class from its feature's `data/` layer, or an
  equivalent script wired into the same `flutter analyze`/CI step quickstart.md already documents) so
  RNF06's "zero layer violations" gate is enforced mechanically rather than only by manual code review —
  `analysis_options.yaml`'s `always_use_package_imports`/`directives_ordering` lints (added in T003) only
  normalize import syntax and do not fail on a domain file importing Flutter or a data/ class per
  Constitution Principle V / RNF06 (partial)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Stories (Phase 3–7)**: All depend on Foundational completion.
  - US1 (P1) has no dependency on another story.
  - US2 (P2) extends US1's `auth_remote_data_source.dart`/`auth_repository_impl.dart`/`auth_bloc.dart`/
    `login_signup_page.dart` in place — do US1 first.
  - US3 (P3) is independent of US1/US2's files but its splash routes to the Home/Chat page US1
    creates (T028) — do US1 first for a meaningful manual test, though US3's own tasks touch no
    US1/US2 files.
  - US4 (P4) extends US1's `home_chat_shell_page.dart` (T028) — do US1 first.
  - US5 (P5) extends US3's `session_bloc.dart` (T047) and needs US1/US2's login screen as the
    re-authentication destination — do US1 and US3 first.
- **Polish (Phase 8)**: Depends on all five user stories being complete.

### Within Each User Story

- Tests are written first and MUST fail before their matching implementation task.
- Domain entities/interfaces before use cases; use cases before blocs; blocs before pages.
- Data-layer classes (`*_remote_data_source.dart`, `*_repository_impl.dart`) before the
  `service_locator.dart` registration task that wires them in.

### Parallel Opportunities

- All Setup tasks marked [P] (T003, T004) can run in parallel once T001/T002 finish.
- Within Foundational, T005, T007, T009, T011 (and the chain T012→T013) can run in parallel; T006,
  T008, T010 each wait only on their own listed dependency.
- Within each story's test block, tasks against distinct new files are marked [P]; tasks that extend
  a file an earlier story's task already created (e.g. T031/T032/T033, T034/T035/T037/T038) are not
  marked [P] and run after that earlier task.
- US4's tasks (T051–T055) can start as soon as Foundational and US1 (for `home_chat_shell_page.dart`)
  are done, in parallel with US2/US3 work by a different contributor.

---

## Parallel Example: User Story 1

```bash
# Tests for User Story 1 (distinct files, run together):
Task: "Unit test LoginUseCase in test/features/auth/domain/usecases/login_usecase_test.dart"
Task: "Unit test AuthRepositoryImpl.login in test/features/auth/data/auth_repository_impl_test.dart"
Task: "Unit test AuthRemoteDataSource.login in test/features/auth/data/auth_remote_data_source_test.dart"
Task: "bloc_test for AuthBloc login flow in test/features/auth/presentation/bloc/auth_bloc_test.dart"

# Foundational entities needed by US1, also parallel:
Task: "Create Account entity in lib/features/auth/domain/entities/account.dart"
Task: "Create AuthRepository interface in lib/features/auth/domain/repositories/auth_repository.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (blocks every story).
3. Complete Phase 3: User Story 1 (login → Home/Chat).
4. **STOP and VALIDATE**: run T017–T020's tests, then quickstart.md scenario 1 manually.
5. Demo on a simulator if ready.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 (login) → test independently → demo (MVP).
3. US2 (sign-up) → test independently → demo.
4. US3 (splash/launch routing) → test independently → demo.
5. US4 (side-menu navigation) → test independently → demo.
6. US5 (session-expired overlay) → test independently → demo.
7. Phase 8 (Polish) → confirm RNF06/07/08/09 gates and run quickstart.md in full.

### Parallel Team Strategy

1. Team completes Setup + Foundational together (T001–T016).
2. Once Foundational is done, US1 should be finished first (US2, US4, and US5 all extend files US1
   creates). After US1:
   - Developer A: US2 (sign-up, extends US1's auth files).
   - Developer B: US3 (splash/routing — independent of US1/US2's files).
   - Developer C: US4 (side menu — extends US1's Home/Chat page) once US1's T028 lands.
3. US5 starts once both US1 (login destination) and US3 (`SessionBloc`) exist.

---

## Notes

- [P] tasks touch different files with no incomplete dependency.
- [Story] labels map every Phase 3–7 task to its spec.md user story for traceability.
- RNF09's 15/15 write-endpoint scenario target spans the *entire* delivery order (requirements.md
  §12); this unit's tasks close only the 9 scenarios belonging to its own 3 write endpoints
  (signup, login, refresh) — see T019, T031, T041, and the cross-check at T063.
- Every visual value belongs only in `design_tokens.dart`/`theme.dart` (T005/T006) — no later task
  in this file should introduce a literal color, font, spacing, or radius value elsewhere.
- Commit after each task or logical group; stop at any checkpoint to validate a story
  independently.

---

## Phase 10: Convergence

- [X] T067 Remove the hardcoded visual values found outside `lib/core/design_tokens.dart` —
  `lib/features/splash/presentation/pages/splash_page.dart`'s loading-dot `width`/`height: 8`,
  `lib/features/auth/presentation/pages/login_signup_page.dart`'s loading-spinner
  `height`/`width: 20` and `strokeWidth: 2`, `lib/features/home/presentation/widgets/app_drawer.dart`'s
  `Divider(height: 1)`, and `lib/core/theme.dart`'s focused-border `width: 1.5` — by adding the
  missing size/stroke-width constants to `design_tokens.dart` and referencing them from each site,
  per Constitution Principle IV / FR-002 / RNF08 (contradicts)
- [X] T068 Harden `ApiClient.call` (`lib/core/network/api_client.dart`) so a success envelope whose
  `data` field is present but is not a JSON object is mapped to a `Failure` instead of throwing an
  uncaught `TypeError` past the client boundary (the current `on DioException catch` does not catch
  this, since the cast failure is not a `DioException`); add `test/core/network/api_client_test.dart`
  (named in plan.md's Project Structure but never created) covering this case plus the documented
  URL-construction, header, and `AuthMode` behavior from contracts/http-client.md, per FR-003
  (partial)
- [X] T069 Restrict `ios/Runner/Info.plist`'s `UISupportedInterfaceOrientations` (and its `~ipad`
  variant) to portrait only, removing the `LandscapeLeft`/`LandscapeRight`/`PortraitUpsideDown`
  entries left over from `flutter create`, so the native platform configuration matches plan.md's
  Target Platform decision ("iOS, portrait orientation only") instead of relying solely on
  `SystemChrome.setPreferredOrientations` at the Dart level, per plan: Target Platform (partial)
