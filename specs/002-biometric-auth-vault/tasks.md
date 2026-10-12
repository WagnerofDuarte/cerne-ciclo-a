---

description: "Task list for P-RF03 — Biometric authentication vault"
---

# Tasks: P-RF03 — Biometric authentication vault

**Input**: Design documents from `/specs/002-biometric-auth-vault/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. plan.md's Testing section and quickstart.md's "Automated checks" explicitly name
the domain tests this unit's RNF07 coverage gate depends on (`EvaluateBackgroundResumeUseCase`,
`DetermineVaultEntryUseCase`, `VerifyPinUseCase`/`SavePinUseCase`, `BiometricsPreferenceRepositoryImpl`'s
3 failure scenarios), so test tasks are generated alongside implementation, `bloc_test`/`mocktail`
style, matching F000's existing test files exactly.

**Organization**: Tasks are grouped by user story (US1–US4, spec.md priorities P1/P1/P2/P3). Per
research.md R4, all four stories share one route/page/bloc (`AppRoutes.vault` / `VaultPage` /
`VaultBloc`) by deliberate design — "independent" here means each story's acceptance scenarios can
be exercised and automated-tested on their own once Foundational is done, not that each story gets
its own screen.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on an incomplete task)
- **[Story]**: US1 (biometric unlock), US2 (biometric-failure → PIN fallback), US3 (first-time PIN
  setup), US4 (recover via full login)

## Path Conventions

Single Flutter project (F000's existing `lib/`, `test/`) — see plan.md Project Structure. All new
files live under `lib/features/vault/` and `test/features/vault/`; four files touch existing F000
code at documented one-line extension points.

---

## Phase 1: Setup

**Purpose**: Dependencies and the one new route constant every later task needs.

- [X] T001 Add `local_auth` and `crypto` to `pubspec.yaml` dependencies (research.md R1, R2), then run `fvm flutter pub get`
- [X] T002 [P] Add `NSFaceIDUsageDescription` (a one-line usage string) to `ios/Runner/Info.plist` — required before any `local_auth` call, including a check, can be made on-device or in the Simulator (research.md R1)
- [X] T003 [P] Add `static const String vault = '/vault';` to `AppRoutes` in `lib/core/routing/app_routes.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared repository/usecase/bloc/page plumbing every one of the four user stories
reads or extends. No story's acceptance scenario can be exercised, manually or in a test, until
this phase is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 [P] Create `VaultEntryMode` enum (`pinSetupRequired`, `unlockBiometricFirst`, `unlockPinOnly`) in `lib/features/vault/domain/entities/vault_entry_mode.dart` (data-model.md Vault Lock State)
- [X] T005 [P] Create `BiometricCapability` enum (`available`, `noHardware`, `notEnrolled`, `osDisabled`) in `lib/features/vault/domain/entities/biometric_capability.dart` (data-model.md Biometric Capability)
- [X] T006 Create `VaultRepository` abstract interface in `lib/features/vault/domain/repositories/vault_repository.dart` — the exact method set from contracts/vault-repository.md (`hasPinConfigured`, `savePin`, `verifyPin`, `checkBiometricCapability`, `attemptBiometricAuth`, `isBiometricPreferenceEnabled`, `setBiometricPreferenceLocally`, `recordBackgrounded`, `consumeBackgroundedAt`, `markUnlocked`, `lastUnlockedAt`), including the `BiometricAuthOutcome` enum (`success`, `failed`, `cancelled`, `notAvailable`) it returns; no `local_auth` or `flutter_secure_storage` type may appear in this file (RNF06) — depends on T004, T005
- [X] T007 [P] Create `BiometricsPreferenceRepository` abstract interface in `lib/features/vault/domain/repositories/biometrics_preference_repository.dart` — single method `Future<Either<Failure, void>> save(bool enabled)` (contracts/biometrics-preference-repository.md)
- [X] T008 Create `DetermineVaultEntryUseCase` in `lib/features/vault/domain/usecases/determine_vault_entry_usecase.dart`, implementing exactly the branching in contracts/vault-repository.md (`!hasPinConfigured()` → `pinSetupRequired`; else `capability == available && preferred` → `unlockBiometricFirst`; else `unlockPinOnly`) — depends on T006
- [X] T009 [P] Write `DetermineVaultEntryUseCase` tests in `test/features/vault/domain/usecases/determine_vault_entry_usecase_test.dart` against a fake `VaultRepository`, covering all four input combinations per quickstart.md: no PIN; PIN + biometric available + preferred; PIN + biometric available + not preferred; PIN + biometric unavailable — depends on T008
- [X] T010 [P] Add `sizeKeypadTapTarget` token (value `72`, a `double`, dp) to `lib/core/design_tokens.dart` — the circular tap target for each of the keypad's 12 keys, per research.md R7; no other value this unit needs is new
- [X] T011 Create `VaultSecureStorage` in `lib/features/vault/data/vault_secure_storage.dart` — Keychain-backed via `flutter_secure_storage`, two keys: PIN hash and local biometrics-preference mirror. `savePin`/PIN comparison MUST store and compare only `sha256(pin)` (hex string), never the raw digit string (research.md R2); the PIN value accepted MUST be "exactly 4 digits, each `0`–`9`, no partial/shorter value ever written or compared" (data-model.md Device PIN validation rule) — validate this shape before hashing
- [X] T012 [P] Create `LocalAuthBiometricDataSource` in `lib/features/vault/data/local_auth_biometric_data_source.dart` — thin wrapper over `local_auth`'s `LocalAuthentication`, calling `authenticate(biometricOnly: true)` (research.md R1); the only file in this unit allowed to import `local_auth` types
- [X] T013 Create `VaultRepositoryImpl` implementing `VaultRepository` in `lib/features/vault/data/vault_repository_impl.dart` — maps `LocalAuthBiometricDataSource`/`local_auth` results into `BiometricCapability`/`BiometricAuthOutcome` before returning (RNF06); `lastUnlockedAt`/`backgroundedAt` held in-memory only, never persisted (data-model.md Vault Lock State) — depends on T006, T011, T012
- [X] T014 [P] Write `VaultRepositoryImpl` tests in `test/features/vault/data/vault_repository_impl_test.dart` (mocktail, mocking `VaultSecureStorage`/`LocalAuthBiometricDataSource`) covering: PIN hash round-trip (`savePin` then `verifyPin` with the same/different 4-digit value), each `BiometricCapability` mapping, `recordBackgrounded`/`consumeBackgroundedAt` clearing semantics (one resume evaluates the gap only once), `markUnlocked`/`lastUnlockedAt` — depends on T013
- [X] T015 Create `BiometricsPreferenceRemoteDataSource` in `lib/features/vault/data/account/biometrics_preference_remote_data_source.dart` — `update({required bool biometricEnabled})` calling `ApiClient.call('account-settings-update', method: 'PATCH', body: {'biometricEnabled': biometricEnabled})` exactly as in contracts/biometrics-preference-repository.md
- [X] T016 Create `BiometricsPreferenceRepositoryImpl` implementing `BiometricsPreferenceRepository` in `lib/features/vault/data/account/biometrics_preference_repository_impl.dart` — `save(enabled)` delegates to the remote data source and maps `Right` to `Right(unit)` via `.map((_) {})`, discarding the decoded body (contracts/biometrics-preference-repository.md: "there is no reason to decode and carry the full updated-account payload") — depends on T007, T015
- [X] T017 [P] Write `BiometricsPreferenceRepositoryImpl` tests in `test/features/vault/data/account/biometrics_preference_repository_impl_test.dart` (mocktail, mocking `ApiClient`, matching `auth_repository_impl_test.dart`'s pattern) covering the 4 scenarios from contracts/biometrics-preference-repository.md: `Right({...})` → `Right(unit)`; `Left(NetworkTimeoutFailure)` passes through unchanged; `Left(NetworkOfflineFailure)` passes through unchanged; `Left(ValidationFailure)` (malformed response) passes through unchanged — depends on T016
- [X] T018 Register this unit's dependencies in `lib/core/di/service_locator.dart`: `VaultSecureStorage`, `LocalAuthBiometricDataSource`, `VaultRepository` as `registerLazySingleton` (one instance for the app's process lifetime, per contracts/vault-repository.md), `BiometricsPreferenceRemoteDataSource`, `BiometricsPreferenceRepository`, `DetermineVaultEntryUseCase`, and `VaultBloc` as `registerFactory` (matching `AuthBloc`'s registration shape) — depends on T006, T007, T008, T013, T016
- [X] T019 Create `VaultState` in `lib/features/vault/presentation/bloc/vault_state.dart` — sub-states covering every branch this unit's single bloc must represent: initial/loading, PIN setup (create step, confirm step with mismatch error), biometric prompting, PIN entry (with the optional "Não foi possível reconhecer — digite seu PIN" error banner and a 4-digit progress-dot count), unlocked
- [X] T020 Create `VaultEvent` in `lib/features/vault/presentation/bloc/vault_event.dart` — `VaultOpened`, `BiometricAuthRequested`, `PinDigitEntered`, `PinBackspacePressed`, `PinSubmitted`, `BiometricOptInToggled`, `UseEmailPasswordRequested`
- [X] T021 Create `VaultBloc` in `lib/features/vault/presentation/bloc/vault_bloc.dart` with its constructor (usecases injected) and the `VaultOpened` handler that calls `DetermineVaultEntryUseCase` once per open and emits the matching initial sub-state (pinSetupRequired / biometric-prompting / PIN-entry) — depends on T008, T019, T020
- [X] T022 Create `VaultMode` enum (`gatekeeper`, `relock`) and `VaultPage` skeleton in `lib/features/vault/presentation/pages/vault_page.dart` — `const VaultPage({required this.mode, super.key})`, `BlocBuilder<VaultBloc, VaultState>` switching on sub-state (bodies filled in by later story tasks); `mode` decides `context.go(AppRoutes.home)` (gatekeeper) vs. `Navigator.pop()` (relock) on the eventual unlocked transition, per data-model.md State transitions — depends on T021
- [X] T023 [P] Create shared `PinKeypad` widget in `lib/features/vault/presentation/widgets/pin_keypad.dart` — 3×4 numeric keypad with backspace and 4 progress dots (FR-005), each key sized `DesignTokens.sizeKeypadTapTarget`, no visual value inlined outside `design_tokens.dart` (Principle IV) — depends on T010
- [X] T024 Add `GoRoute(path: AppRoutes.vault, builder: ...)` wrapping `VaultPage(mode: VaultMode.gatekeeper)` in a `BlocProvider<VaultBloc>` in `lib/core/routing/app_router.dart`, matching the existing `AppRoutes.login` route's shape — depends on T003, T022

**Checkpoint**: Foundation ready — `AppRoutes.vault` resolves to an (empty-bodied) `VaultPage` backed by a real `VaultBloc`/`VaultRepository`/`BiometricsPreferenceRepository`. User story implementation can now begin.

---

## Phase 3: User Story 1 - Unlocking the app with Face ID / Touch ID (Priority: P1) 🎯 MVP

**Goal**: Cold launch or a background resume ≥5 minutes shows the biometric prompt before any data
is visible; a successful scan proceeds into the app's existing session routing; a resume <5 minutes
requires nothing and restores the exact prior state.

**Independent Test**: Launch on a device with biometrics enrolled and the vault already configured;
confirm the biometric prompt appears before any journal/chat content, and a successful scan
proceeds into session routing (Home/Chat or login).

### Tests for User Story 1

- [X] T025 [P] [US1] Write `EvaluateBackgroundResumeUseCase` tests in `test/features/vault/domain/usecases/evaluate_background_resume_usecase_test.dart`: `backgroundedAt: null` → `false`; gap of `Duration(minutes: 4, seconds: 59)` → `false`; gap of exactly `Duration(minutes: 5)` → `true` — the exact boundary contracts/vault-lifecycle.md specifies, enforcing FR-009's "fixed value with no user-facing setting to change it"

### Implementation for User Story 1

- [X] T026 [P] [US1] Create `EvaluateBackgroundResumeUseCase` in `lib/features/vault/domain/usecases/evaluate_background_resume_usecase.dart` — pure function of two `DateTime`s and the one `static const backgroundTimeout = Duration(minutes: 5)` constant (contracts/vault-lifecycle.md); no settings read, no `package:flutter` import
- [X] T027 [US1] In `VaultBloc` (`lib/features/vault/presentation/bloc/vault_bloc.dart`), handle `unlockBiometricFirst` entry: auto-trigger `attemptBiometricAuth()`; on `success`, call `repo.markUnlocked(DateTime.now())` and emit the unlocked state — depends on T021
- [X] T028 [US1] Build the biometric-prompting UI state in `VaultPage` (`lib/features/vault/presentation/pages/vault_page.dart`): fingerprint circle icon (`Icons.fingerprint`, research.md R7), "Toque para desbloquear" manual-retry affordance dispatching `BiometricAuthRequested`, and on the unlocked transition call `context.go(AppRoutes.home)` for `VaultMode.gatekeeper` — depends on T022, T027
- [X] T029 [US1] Create `VaultLifecycleObserver` (`WidgetsBindingObserver`) in `lib/features/vault/presentation/widgets/vault_lifecycle_observer.dart`, implemented exactly per contracts/vault-lifecycle.md: on `paused`, `repo.recordBackgrounded(DateTime.now())`; on `resumed`, consume `backgroundedAt`, evaluate via `EvaluateBackgroundResumeUseCase`, and if `shouldRelock && repo.lastUnlockedAt != null`, push `VaultPage(mode: VaultMode.relock)` onto `rootNavigatorKey` via `MaterialPageRoute` — depends on T022, T026
- [X] T030 [US1] Wrap `MaterialApp.router`'s `builder` child with `VaultLifecycleObserver` in `lib/main.dart`, alongside the existing session-expired `BlocListener` (same `CerneApp.build` spot) — depends on T029
- [X] T031 [US1] In `lib/features/splash/presentation/pages/splash_page.dart`, change the `SessionStatusAuthenticated()` branch from `context.push(AppRoutes.home)` to `context.push(AppRoutes.vault)` — depends on T024
- [X] T032 [US1] Write `VaultBloc` tests in `test/features/vault/presentation/bloc/vault_bloc_test.dart` (`bloc_test`) for `VaultOpened` → `unlockBiometricFirst` → biometric `success` → unlocked — depends on T027
- [X] T033 [US1] Write a widget test for `VaultLifecycleObserver` in `test/features/vault/presentation/widgets/vault_lifecycle_observer_test.dart`, driving `AppLifecycleState.paused`/`.resumed` via `tester.binding.handleAppLifecycleStateChanged(...)` (contracts/vault-lifecycle.md), asserting a relock push occurs at a ≥5-minute gap with `lastUnlockedAt != null`, and no push occurs under 5 minutes or when `lastUnlockedAt == null` — depends on T029

**Checkpoint**: User Story 1 is independently functional and testable — cold-launch biometric gate and the 5-minute background relock both work end to end.

---

## Phase 4: User Story 2 - Biometric failure falls back to PIN (Priority: P1)

**Goal**: A failed, cancelled, or unrecognized biometric attempt immediately offers PIN entry with
the exact fallback message, never locking the user out; a correct PIN still unlocks.

**Independent Test**: Force a biometric failure; confirm the PIN screen appears with the error
message, then confirm a correct PIN still unlocks the app.

### Tests for User Story 2

- [X] T034 [P] [US2] Write `VerifyPinUseCase` tests in `test/features/vault/domain/usecases/verify_pin_usecase_test.dart` against a fake `VaultRepository`: correct PIN → `true`; incorrect PIN → `false`

### Implementation for User Story 2

- [X] T035 [P] [US2] Create `VerifyPinUseCase` in `lib/features/vault/domain/usecases/verify_pin_usecase.dart` — thin delegation to `repo.verifyPin(pin)`
- [X] T036 [US2] In `VaultBloc`, handle `attemptBiometricAuth()` outcomes `failed`/`cancelled`/`notAvailable` (all three routed identically per contracts/vault-repository.md: FR-004 doesn't distinguish "not recognized" from "user tapped away" from "biometrics became unavailable mid-attempt") by emitting the PIN-entry state with the error banner text "Não foi possível reconhecer — digite seu PIN" (FR-004); handle `PinDigitEntered`/`PinBackspacePressed`/`PinSubmitted` via `VerifyPinUseCase`; on a correct PIN, call `repo.markUnlocked(DateTime.now())` and emit the unlocked state (data-model.md State transitions: "correct PIN → markUnlocked() → context.go(AppRoutes.home)") — this is the only unlock path for a user whose biometric preference is off, so skipping it here leaves `lastUnlockedAt` null and silently defeats `VaultLifecycleObserver`'s relock guard (contracts/vault-lifecycle.md) for every PIN-only user; on an incorrect PIN, clear the entered digits and keep the error state with no attempt limit (Edge Cases: "never produce a hard lockout") — depends on T021, T035
- [X] T037 [US2] In `VaultPage`, build the PIN-entry UI state using the shared `PinKeypad` (lib/features/vault/presentation/widgets/pin_keypad.dart): 4-digit progress dots, the biometric-failure error banner when present, digits cleared and redisplayed empty after an incorrect submission — depends on T022, T023, T036
- [X] T038 [US2] Extend `VaultBloc` tests in `test/features/vault/presentation/bloc/vault_bloc_test.dart`: biometric `failed`/`cancelled`/`notAvailable` → PIN-entry state with the exact error message; correct PIN → unlocked AND `repo.markUnlocked` was called (verify via the fake/mock `VaultRepository`); incorrect PIN → digits cleared, error state retained, a second correct attempt afterward still succeeds (no lockout) — depends on T036

**Checkpoint**: User Stories 1 AND 2 both work independently — a failed scan never strands the user.

---

## Phase 5: User Story 3 - Setting up the PIN for the first time (Priority: P2)

**Goal**: The very first successful login/sign-up on a device with no PIN leads straight into
create-then-confirm PIN setup, with an optional biometrics opt-in, before Home/Chat is reachable; a
mismatched confirmation is rejected without saving; a mid-setup kill resumes setup on relaunch.

**Independent Test**: Sign up fresh on a device with no PIN configured; confirm the create-PIN
screen appears before Home/Chat; a matching confirmation proceeds, a mismatched one does not.

### Tests for User Story 3

- [X] T039 [P] [US3] Write `SavePinUseCase` tests in `test/features/vault/domain/usecases/save_pin_usecase_test.dart` against a fake `VaultRepository`, verifying it delegates to `repo.savePin(pin)`
- [X] T040 [P] [US3] Write `SaveBiometricsPreferenceUseCase` tests in `test/features/vault/domain/usecases/save_biometrics_preference_usecase_test.dart` against fake `VaultRepository`/`BiometricsPreferenceRepository`: the local mirror is written synchronously *before* the network call fires (research.md R6); a `Left` result from `BiometricsPreferenceRepository.save` is discarded and does not throw or propagate — the usecase always completes

### Implementation for User Story 3

- [X] T041 [P] [US3] Create `SavePinUseCase` in `lib/features/vault/domain/usecases/save_pin_usecase.dart` — thin delegation to `repo.savePin(pin)`; the 4-digit value it's given must already satisfy "exactly 4 digits, each `0`–`9`" (data-model.md Device PIN validation rule) — the bloc enforces this before calling, this usecase does not re-validate
- [X] T042 [US3] Create `SaveBiometricsPreferenceUseCase` in `lib/features/vault/domain/usecases/save_biometrics_preference_usecase.dart` implementing exactly the 3-step write path from data-model.md Biometrics Preference: (1) `repo.setBiometricPreferenceLocally(enabled)` synchronously; (2) `await biometricsPreferenceRepository.save(enabled)`, discarding the `Either<Failure, T>` result either way; (3) return/complete regardless of step 2's outcome (FR-014, Clarifications: "proceed locally and retry in the background") — depends on T006, T007
- [X] T043 [US3] In `VaultBloc`, handle `pinSetupRequired` entry: create-PIN step holds the first 4-digit entry only in bloc memory (never written to storage yet — data-model.md); confirm step does a pure string-equality check — on match, call `SavePinUseCase` then, if `checkBiometricCapability() == available`, emit a biometric opt-in step, else proceed directly to the complete/unlocked transition (same transition T044 reaches after an opt-in choice — call `repo.markUnlocked(DateTime.now())` then emit the unlocked state); on mismatch, emit a clear mismatch message and return to the create-PIN step with nothing saved (FR-012) — depends on T021, T041, T042
- [X] T044 [US3] In `VaultBloc`, handle `BiometricOptInToggled` by calling `SaveBiometricsPreferenceUseCase`, then call `repo.markUnlocked(DateTime.now())` and transition to the unlocked/complete state regardless of `SaveBiometricsPreferenceUseCase`'s outcome, proceeding to Home/Chat (FR-013, FR-014) — the `markUnlocked()` call here (and in T043's no-biometric-available branch) is required so `VaultLifecycleObserver`'s `repo.lastUnlockedAt != null` guard (contracts/vault-lifecycle.md) is already satisfied the first time a new user backgrounds the app after setup; without it, FR-007/SC-001 silently never trigger for a brand-new device's first background/resume cycle — depends on T043
- [X] T045 [US3] Build the PIN-setup UI states in `VaultPage` — create-PIN step, confirm-PIN step with mismatch message, and (when biometric capability is available) the biometrics opt-in prompt — reusing the shared `PinKeypad`; on gatekeeper-mode completion, `context.go(AppRoutes.home)` — depends on T022, T023, T044
- [X] T046 [US3] In `lib/features/auth/presentation/pages/login_signup_page.dart`, change the non-reauth `AuthStatus.authenticated` branch from `context.push(AppRoutes.home)` to `context.push(AppRoutes.vault)` — depends on T024
- [X] T047 [US3] Extend `VaultBloc` tests in `test/features/vault/presentation/bloc/vault_bloc_test.dart`: `pinSetupRequired` → matching create/confirm → PIN saved, biometric opt-in available → `SaveBiometricsPreferenceUseCase` invoked → unlocked/complete AND `repo.markUnlocked` was called; matching create/confirm with no biometric capability available → skips the opt-in step → unlocked/complete AND `repo.markUnlocked` was called (T043's else-branch); mismatched confirm → mismatch message, create step re-entered, `savePin` never called; a `pinSetupRequired` re-open before confirmation completes (process killed mid-setup) re-enters the create step rather than any unlocked/Home state, since `hasPinConfigured()` is still `false` (Edge Cases) — depends on T043, T044

**Checkpoint**: All of Stories 1–3 are independently functional — the full vault core loop (setup → unlock → fallback) works end to end.

---

## Phase 6: User Story 4 - Recovering access via full login (Priority: P3)

**Goal**: A visible "usar e-mail e senha" link on the vault screen leads to the existing
email/password login, regardless of whether the vault is showing the biometric or PIN state.

**Independent Test**: Tap "usar e-mail e senha" from the vault screen; confirm it leads to the
existing login screen; submitting valid credentials proceeds into the app.

### Implementation for User Story 4

- [X] T048 [US4] Add a visible "usar e-mail e senha" text link to both the biometric-prompting and PIN-entry UI states in `VaultPage`, dispatching `UseEmailPasswordRequested` (FR-006) — depends on T028, T037
- [X] T049 [US4] In `VaultBloc`, handle `UseEmailPasswordRequested` by triggering `context.push(AppRoutes.login)` from `VaultPage` (no bloc state change needed beyond the navigation side effect) — depends on T048
- [X] T050 [US4] Write a widget test in `test/features/vault/presentation/pages/vault_page_test.dart` confirming the "usar e-mail e senha" link is present and triggers a push to `AppRoutes.login` from both the biometric-prompting and PIN-entry states — depends on T049

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: The constitution/quickstart gates that span every story above.

- [X] T051 [P] Run `fvm flutter analyze` and resolve any `always_use_package_imports`/lint findings under `lib/features/vault/`
- [X] T052 [P] Run `test/architecture/domain_purity_test.dart` and confirm it still reports 0 violations with `lib/features/vault/domain/` included (RNF06)
- [X] T053 Run `fvm flutter test --coverage`, extract `lib/**/domain/**` via `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info`, and confirm ≥80% coverage with `lib/features/vault/domain/` included (RNF07)
- [ ] T054 Execute quickstart.md's manual verification on the iOS Simulator for Stories 1–4 and its edge cases: no-hardware/not-enrolled/OS-disabled-between-sessions shows PIN directly with no error; the exact 5-minute boundary; app killed mid-setup resumes setup; app killed while backgrounded is treated as cold launch; offline during the biometrics-preference write still completes setup and reaches Home/Chat

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup (T003 for the route constant) — BLOCKS all user stories.
- **User Stories (Phase 3–6)**: All depend on Foundational completion.
  - US1 and US2 (both P1) should be done first — US2's "biometric fails → PIN" handler extends the
    same `VaultBloc` branch US1's biometric-success handler lives in (T027/T036 both touch
    `vault_bloc.dart`), so doing them in sequence avoids rework, even though each is independently
    testable once done.
  - US3 (P2) extends the same bloc/page with the `pinSetupRequired` branch — independent of US1/US2's
    code paths (different `VaultEntryMode` branch) but shares the file.
  - US4 (P3) only adds a link + navigation handler on top of UI states US1/US2 already built (T028, T037).
- **Polish (Phase 7)**: Depends on all four stories being complete.

### Within Each User Story

- Tests before/alongside implementation (written to fail first, per the template's convention).
- Domain usecases before bloc wiring; bloc wiring before the page UI that reads it.
- Story complete (bloc + page + test) before moving to the next priority.

### Parallel Opportunities

- T002, T003 (Setup) in parallel.
- T004, T005 (entities), T010 (design token), T007 (second repository interface) in parallel within Foundational.
- T009, T014, T017 (test files) can be written in parallel with each other once their respective implementation task lands.
- T025/T026 (US1 usecase + its test) in parallel with T034/T035 (US2 usecase + its test) — different files, both depend only on Foundational.
- T039/T040/T041 (US3 usecases + tests) in parallel with each other.

---

## Parallel Example: Foundational Phase

```bash
# Launch independent entity/token files together:
Task: "Create VaultEntryMode enum in lib/features/vault/domain/entities/vault_entry_mode.dart"
Task: "Create BiometricCapability enum in lib/features/vault/domain/entities/biometric_capability.dart"
Task: "Add sizeKeypadTapTarget token to lib/core/design_tokens.dart"
Task: "Create BiometricsPreferenceRepository interface in lib/features/vault/domain/repositories/biometrics_preference_repository.dart"
```

## Parallel Example: User Story 1 vs. User Story 2 usecases

```bash
Task: "Create EvaluateBackgroundResumeUseCase in lib/features/vault/domain/usecases/evaluate_background_resume_usecase.dart"
Task: "Write EvaluateBackgroundResumeUseCase tests in test/features/vault/domain/usecases/evaluate_background_resume_usecase_test.dart"
Task: "Create VerifyPinUseCase in lib/features/vault/domain/usecases/verify_pin_usecase.dart"
Task: "Write VerifyPinUseCase tests in test/features/vault/domain/usecases/verify_pin_usecase_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
3. Complete Phase 3: User Story 1.
4. **STOP and VALIDATE**: cold launch shows the biometric prompt before data; a successful scan
   proceeds; background ≥5 min re-prompts; background <5 min does not. Note that without User
   Story 3, this MVP slice has no PIN ever configured on a fresh device — validate it on a device
   where a PIN already exists (or treat US1+US3 as the realistic minimum demoable slice).

### Incremental Delivery

1. Setup + Foundational → foundation ready (vault route exists, resolves to an empty page).
2. Add US1 → biometric gate works (needs a pre-existing PIN to reach `unlockBiometricFirst`).
3. Add US2 → a failed scan no longer strands the user.
4. Add US3 → a fresh device can actually reach the vault for the first time (PIN now gets created) — this closes the loop US1/US2 needed a PIN for.
5. Add US4 → the "usar e-mail e senha" safety valve.
6. Polish → RNF06/07 gates + quickstart's full manual pass.

Note the real dependency the priorities don't show on their own: **US3 produces the PIN that US1
and US2 require to exist.** Implementing in spec order (US1 → US2 → US3 → US4) is fine for
*writing* the code (Foundational already stubs `hasPinConfigured()`), but *manually demoing* US1/US2
end-to-end needs either a PIN seeded directly via `VaultRepository` in a test, or US3 done first.

---

## Notes

- `vault_bloc.dart`, `vault_event.dart`, `vault_state.dart`, and `vault_page.dart` are each touched
  by multiple story phases (T021/T027/T036/T043/T044 for the bloc; T022/T028/T037/T045/T048 for the
  page) — this is the deliberate single-screen/single-bloc shape research.md R4 chose, not a
  same-file conflict to avoid.
- Every repository method this unit adds that is *not* network-backed (`VaultRepository`'s methods)
  intentionally returns plain types, not `Either<Failure, T>` — research.md R5. Only
  `BiometricsPreferenceRepository.save` does, and only its 3 failure-scenario tests (T017) count
  toward RNF09's 15/15.
- No task in this list touches `docs/input/`, `docs/input/backend/api/openapi.yaml`, `.env`, or
  `lib/features/session/presentation/widgets/session_expired_overlay.dart` — all three are
  explicitly out of scope (FR-018, spec.md Assumptions).
