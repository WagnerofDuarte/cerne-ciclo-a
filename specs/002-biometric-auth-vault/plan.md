# Implementation Plan: P-RF03 — Biometric authentication vault

**Branch**: `002-biometric-auth-vault` (spec directory only — no git branch exists; see spec header)

**Date**: 2026-10-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-biometric-auth-vault/spec.md`,
`docs/input/requirements.md` §1 (RF03), §10 (parameters), §13 (technical constraints), and
`.specify/memory/constitution.md`. Depends on F000 (`specs/001-foundation/`), already implemented.

## Summary

RF03 inserts a device-local Face ID / Touch ID / PIN barrier between F000's existing session
routing and any screen that shows user data. It adds exactly two new decision points to code F000
already ships — the splash screen's `authenticated` branch and the login/sign-up screen's success
branch — redirecting both from `AppRoutes.home` to a new `AppRoutes.vault` gate instead of adding a
parallel navigation scheme. That single screen (`VaultPage`) internally covers three of the
prototype's named states (Biometria, PIN inicial, PIN após falha) plus first-time PIN
creation, branching on whether a PIN is already configured on the device. A second, independent
mechanism — an app-lifecycle observer feeding a fixed 5-minute domain rule — re-pushes the same
screen over whatever is on screen when the app resumes from a long background period, without
disturbing that screen's state underneath (reusing F000's established `push`-only navigation
discipline, research.md R3). Authentication itself never leaves the device: no biometric data and
no PIN value are ever sent to the backend. The one network call this unit introduces —
persisting the `biometricEnabled` preference via the already-frozen `PATCH /account/settings`
— reuses F000's `ApiClient`/`Either<Failure, T>` path and is fire-and-forget by design (Clarifications).

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000, no new pin needed.

**Primary Dependencies** (additions on top of F000's stack):
- `local_auth` — the official Flutter plugin for Face ID/Touch ID; see research.md R1.
- `crypto` — `sha256` hashing of the on-device PIN before it touches secure storage; see research.md R2.
- Reused unchanged from F000: `flutter_bloc`, `fpdart`, `dio` (via `ApiClient`), `get_it`,
  `flutter_secure_storage`, `equatable`, `go_router`; dev-only `mocktail`, `bloc_test`.

**Storage**: `flutter_secure_storage`, extended with two new keys (PIN hash, local biometrics-
preference mirror) via a new `VaultSecureStorage` wrapper parallel to F000's `SecureTokenStorage` —
see data-model.md Device PIN / Biometrics Preference. No SQL/NoSQL local database is introduced.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, identical to F000; coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter for the RNF07 gate. Device
biometric hardware cannot be exercised by `flutter_test` (no `local_auth` platform channel on the
test VM) — see quickstart.md for the manual iOS Simulator verification steps User Stories 1–2 need.

**Target Platform**: iOS, portrait only — unchanged. `local_auth` requires
`NSFaceIDUsageDescription` in `ios/Runner/Info.plist` (new, see research.md R1); no other native
project change.

**Project Type**: Same single Flutter mobile app; this unit adds one new `lib/features/vault/`
feature folder and touches two existing F000 files at their documented extension points (below).
No backend/server code, no change to `docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 — the biometric prompt itself is OS-rendered (not timed against the
<100 ms/300 ms rule); the one network call this unit makes (`account-settings-update`) shows a
loading indicator only if it exceeds 300 ms, but per FR-014/Clarifications its outcome never blocks
navigation, so in practice no user-visible wait is introduced by this unit at all — PIN
creation/verification and the local biometric prompt are the sum of what stands between the user
and Home/Chat, and both are local.

**Constraints**:
- Authentication is validated entirely on-device (FR-002) — no biometric data or PIN value is ever
  sent to, or checked by, the backend; the backend has no biometric-unlock endpoint by design
  (requirements.md §6.1).
- The 5-minute background timeout is fixed, not user-configurable (FR-009, requirements.md §10).
- No RF01/RF02/RF04–RF10 behavior, no Settings screen, no extension feature (FR-016, FR-017).
- No backend/contract/config change (FR-018) — the only call made is to the already-existing
  `account-settings-update` function, with a request body containing only `biometricEnabled`.
- Clean Architecture, 3 layers per feature (Principle V); domain layer stays free of
  `package:flutter` and `local_auth` types — see contracts/vault-repository.md.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — any
  value the vault screens need that isn't already in the token file from F000 is added there, never
  inlined (data-model.md Design Tokens).

**Scale/Scope**: 1 new screen (`VaultPage`, covering Biometria / PIN inicial / PIN após falha / PIN
first-time setup as internal states, per prototype-extract.md's implementation note #1), 1 new
root-level lifecycle observer (no new visible screen — it only decides *when* to push the existing
`VaultPage`), 1 new narrowly-scoped repository (`BiometricsPreferenceRepository`) consuming 1
additional backend operation (`account-settings-update`, `PATCH /account/settings`) beyond F000's
4. Two existing F000 files get a one-line navigation-target change each (`splash_page.dart`,
`login_signup_page.dart`); `session_expired_overlay.dart` and its re-auth flow are explicitly
**not** touched (spec.md Assumptions — that overlay's own vault-routing is RF07's job, not RF03's).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this
section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only; the one open question (PATCH-failure blocking behavior) was already resolved via the Clarifications session in spec.md, not re-opened here. |
| II. Fixed Technology Stack | PASS | `flutter_bloc`/`fpdart`/`mocktail` reused as-is. `local_auth` fills the constitution's explicitly-open "biometrics package" slot (research.md R1). `crypto` is an incidental, non-conflicting addition (research.md R2) — not one of the stack's fixed choices, but introduces nothing that competes with or bends a fixed choice. |
| III. Backend Boundary | PASS | Exactly one new function called: `account-settings-update` (`PATCH /account/settings`), via `{FUNCTIONS_BASE_URL}/<function>`, `Authorization: Bearer <access token>` (user session, per OpenAPI's `bearerAuth`) — reusing `ApiClient` unmodified. No biometric/PIN data ever leaves the device (FR-002); the backend's absence of a biometric-unlock endpoint is honored, not worked around. |
| IV. Design Token Discipline & Visual Fidelity | PASS | Vault screens render from `design_tokens.dart`; any value not already defined there (e.g. the keypad button's tap-target size) is added to that file as part of Phase 1, never inlined — see data-model.md Design Tokens. |
| V. Clean Architecture Folder Convention | PASS | `lib/features/vault/{data,domain,presentation}`; see Project Structure. `VaultRepository`'s domain interface exposes no `local_auth` or `package:flutter` type — contracts/vault-repository.md. |
| RNF01 (latency) | PASS | No network call stands between the user and an unlock decision; the one network call this unit makes is fire-and-forget (FR-014) and never gates navigation. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF03 | No PII is captured or transmitted by this unit; `account-settings-update` is already RLS-protected server-side, unchanged by this unit. |
| RNF05 (hard delete) | N/A to RF03 | Belongs to the Settings/RF09 unit. |
| RNF06 (layer violations) | PASS | `VaultRepository`/usecases import no `package:flutter`, no `local_auth`, no `data/` class — enforced by the same `always_use_package_imports`/`domain_purity_test.dart` convention F000 already set up. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | This unit's domain layer is unusually test-dense for its size: PIN verification, the 5-minute relock rule, and the vault-entry decision (pin-setup vs. unlock, biometric-first vs. PIN-only) are all pure, injectable usecases — see data-model.md and contracts/vault-lifecycle.md. |
| RNF08 (visual fidelity) | PASS | Biometria/PIN inicial/PIN após falha rendered per prototype-extract.md §2.1/§3; see data-model.md. |
| RNF09 (Either + 15/15 error scenarios) | PARTIAL BY DESIGN, not a violation | Consistent with F000's own note: RNF09's 15-scenario target is reached incrementally across the whole delivery order. This unit's only network-backed repository, `BiometricsPreferenceRepository`, returns `Either<Failure, T>` and is covered for timeout/malformed/offline (3/3). `VaultRepository` (PIN check, biometric hardware query, local-only operations) deliberately does **not** return `Either<Failure, T>` — see research.md R5 for why that scoping is the reasonable reading of RNF09, not an exception to it. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/002-biometric-auth-vault/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── vault-repository.md
│   ├── biometrics-preference-repository.md
│   └── vault-lifecycle.md
├── checklists/
│   └── requirements.md   # already present
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

F000's Flutter project already exists (`pubspec.yaml`, `lib/`, `test/`). RF03 adds one feature
folder and touches two existing files at their documented navigation hand-off points.

```text
cerne-ciclo-a/
├── pubspec.yaml                         # + local_auth, + crypto
├── ios/Runner/Info.plist                # + NSFaceIDUsageDescription (research.md R1)
├── lib/
│   ├── core/
│   │   ├── routing/
│   │   │   ├── app_routes.dart              # + AppRoutes.vault
│   │   │   └── app_router.dart              # + GoRoute(AppRoutes.vault)
│   │   └── di/
│   │       └── service_locator.dart         # + vault feature registrations
│   └── features/
│       ├── splash/presentation/pages/splash_page.dart        # authenticated branch: push vault, not home (1 line)
│       ├── auth/presentation/pages/login_signup_page.dart    # non-reauth success: push vault, not home (1 line)
│       ├── session/presentation/widgets/session_expired_overlay.dart   # UNCHANGED — see spec.md Assumptions
│       └── vault/
│           ├── data/
│           │   ├── vault_secure_storage.dart          # pinHash + local biometricPreference, Keychain-backed
│           │   ├── local_auth_biometric_data_source.dart  # thin wrapper over `local_auth`'s LocalAuthentication
│           │   ├── vault_repository_impl.dart
│           │   └── account/
│           │       ├── biometrics_preference_remote_data_source.dart  # PATCH account-settings-update
│           │       └── biometrics_preference_repository_impl.dart
│           ├── domain/
│           │   ├── entities/
│           │   │   ├── vault_entry_mode.dart        # pinSetup | unlockBiometricFirst | unlockPinOnly
│           │   │   └── biometric_capability.dart     # available | noHardware | notEnrolled | osDisabled
│           │   ├── repositories/
│           │   │   ├── vault_repository.dart
│           │   │   └── biometrics_preference_repository.dart
│           │   └── usecases/
│           │       ├── determine_vault_entry_usecase.dart
│           │       ├── verify_pin_usecase.dart
│           │       ├── save_pin_usecase.dart
│           │       ├── evaluate_background_resume_usecase.dart   # the fixed 5-minute rule
│           │       └── save_biometrics_preference_usecase.dart   # local mirror + fire-and-forget backend write
│           └── presentation/
│               ├── bloc/
│               │   ├── vault_bloc.dart          # screen-scoped: setup + unlock sub-states (one screen, one bloc)
│               │   ├── vault_event.dart
│               │   └── vault_state.dart
│               ├── pages/
│               │   └── vault_page.dart          # mode: gatekeeper (splash/login) | relock (background resume)
│               └── widgets/
│                   ├── pin_keypad.dart          # shared 3×4 keypad + 4 progress dots (Component library: PIN keypad)
│                   └── vault_lifecycle_observer.dart  # WidgetsBindingObserver; pushes VaultPage(relock) on resume
└── test/
    └── features/vault/
        ├── domain/usecases/...                  # RNF07 gate lives here
        ├── data/...
        └── presentation/bloc/vault_bloc_test.dart
```

**Structure Decision**: Same single Flutter app F000 established; RF03 is additive
(`features/vault/`) plus two one-line edits to existing F000 navigation call sites, chosen over
duplicating a parallel auth-routing scheme. No new top-level directory, no change to `docs/`,
`.specify/`, or `specs/001-foundation/`.

## Complexity Tracking

*No entries — every choice below is either one of the constitution's explicitly open decisions
("biometrics package") or a narrow, justified addition (`crypto`) that bends no fixed principle.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `VaultRepository`'s abstract methods (contracts/vault-repository.md) take and return only
  domain types (`bool`, `String`, `BiometricCapability`, `DateTime?`) — no `local_auth` class
  (`LocalAuthentication`, `AuthenticationOptions`, `BiometricType`) crosses into `domain/`, and no
  `flutter_secure_storage` type does either. RNF06/Principle V confirmed before any code exists.
- `BiometricsPreferenceRepository` (contracts/biometrics-preference-repository.md) is the only
  repository in this unit that returns `Either<Failure, T>`, reusing F000's `Failure` hierarchy
  and `ApiClient` unmodified — no new error code, no new HTTP client, no change to
  `core/network/`.
- `EvaluateBackgroundResumeUseCase` (contracts/vault-lifecycle.md) hard-codes the 5-minute constant
  once, as a pure function of two `DateTime` values — FR-009's "fixed, not configurable" is
  enforced by there being no parameter or settings read that could change it, not just by
  convention.
- `VaultPage`'s two navigation outcomes (`go(home)` for the gatekeeper entry, `pop()` for the
  relock entry — data-model.md State transitions) were re-checked against research.md R3: both
  preserve the invariant that nothing above `VaultPage` is ever discarded except by an explicit
  `pop`, matching F000's existing session-expired-overlay precedent exactly rather than inventing a
  second navigation discipline.
- No change surfaced that touches `docs/input/backend/api/openapi.yaml`, `.env`, F000's
  `session_expired_overlay.dart`/re-auth path, or any AI provider — Principle III and the spec's
  own Assumptions both remain intact.

No new violations. Gate remains PASS.
