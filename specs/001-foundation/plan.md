# Implementation Plan: P-F000 — Foundation

**Branch**: `001-foundation` (spec directory only — no git branch exists; see spec header)

**Date**: 2026-10-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-foundation/spec.md`, `docs/input/requirements.md` §12
(delivery order) and §13 (technical constraints), and `.specify/memory/constitution.md`.

## Summary

F000 is the foundation every later unit (RF03 → RF09) builds on: the Flutter project scaffold and
Clean Architecture folder convention, `lib/core/design_tokens.dart` as the single visual-value
source, a `dio`-based HTTP client whose repositories return `Either<Failure, T>` (fpdart) mapped
from the backend's closed 13-code error taxonomy, the login/sign-up screen (toggle, not two
screens), splash-time session check with silent refresh, base navigation (Home/Chat shell, side
menu/drawer, Meus Registros and Configurações placeholders), and the "Sessão expirada" overlay that
preserves underlying screen state. It consumes exactly 4 of the backend's 23 Edge Functions
(`auth-signup`, `auth-login`, `auth-refresh`, `auth-session`) and implements no RF01–RF10 behavior.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable channel), pinned to the project via
`fvm` (already present on this machine's global fvm cache — see [research.md](./research.md) R1).

**Primary Dependencies**:
- `flutter_bloc` (state management — fixed by constitution)
- `fpdart` (`Either<Failure, T>` — fixed by constitution)
- `dio` (HTTP client — chosen, see R2)
- `go_router` (navigation — chosen, see R3)
- `get_it` (service locator / DI — chosen, see R4)
- `flutter_secure_storage` (on-device token persistence — chosen, see R5)
- `equatable` (value equality for states/entities/failures)
- Dev-only: `mocktail` (fixed by constitution), `bloc_test`

**Storage**: `flutter_secure_storage` only — persists `accessToken`, `refreshToken`, `expiresAt`
between launches (per spec Assumptions). No local database/cache is introduced by F000.

**Testing**: `flutter_test` + `bloc_test` for bloc/presentation logic, `mocktail` for every test
double (data sources, repositories), coverage measured with `fvm flutter test --coverage` and a
`lib/**/domain/**`-scoped lcov filter for the RNF07 gate (≥80%).

**Target Platform**: iOS, portrait orientation only (constitution + requirements §13). No
product-specified minimum iOS deployment target exists in the inputs; the pinned Flutter SDK's
`flutter create` default is kept as-is (see R8) rather than inventing a floor.

**Project Type**: Single Flutter mobile app consuming a frozen, already-documented backend over
HTTPS Edge Functions. No backend/server code is part of this repository.

**Performance Goals**: RNF01 — local actions reflected in the UI in <100 ms; any network call
exceeding 300 ms shows a loading indicator (skeleton/spinner, per prototype's `Skeleton` component).

**Constraints**:
- Clean Architecture, 3 layers (`data/`, `domain/`, `presentation/`) per feature (Principle V).
- Every repository returns `Either<Failure, T>` (Principle II, RNF09).
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV, RNF08).
- Domain layer imports neither `package:flutter` nor any `data/` class (Principle V, RNF06).
- No change to the backend, its contract, or its configuration (Principle III, FR-017).
- No direct AI-provider calls from the app (Principle III).
- Real request paths only — `{FUNCTIONS_BASE_URL}/<x-cerne-function>`, never the OpenAPI REST path
  (Principle III, FR-005).
- `.env` carries exactly `FUNCTIONS_BASE_URL` and `SUPABASE_ANON_KEY`, never committed.
- No RF01–RF10 functional behavior; any such control exists only as an inert placeholder (FR-016).

**Scale/Scope**: 5 screens (Splash, Login/Sign-up toggle, Home/Chat shell, Meus Registros
placeholder, Configurações placeholder) + 1 modal overlay (Sessão expirada) + 1 navigation drawer;
consumes 4 of the backend's 23 operations; 0 persisted business data of its own (tokens only).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this
section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only; all open decisions resolved in research.md rather than left blocking. |
| II. Fixed Technology Stack | PASS | `flutter_bloc`, `fpdart` `Either`, `mocktail` adopted as-is. `whisper_ggml` is out of scope for F000 (no audio capture exists yet) — not a violation, simply not yet introduced. |
| III. Backend Boundary | PASS | Only `auth-signup`/`auth-login`/`auth-refresh`/`auth-session` called, via `{FUNCTIONS_BASE_URL}/<function>`; `apikey` header on every call; `Authorization: Bearer <anon key>` for signup/login/refresh, `Bearer <access token>` for `auth-session`. `.env` already gitignored, untouched by this plan. |
| IV. Design Token Discipline & Visual Fidelity | PASS | `design_tokens.dart` is a Phase 1 output; see data-model.md and R9. |
| V. Clean Architecture Folder Convention | PASS | See Project Structure below; domain layer kept Flutter- and data-free. |
| RNF01 (latency) | PASS | Loading indicator required >300 ms on the 4 auth calls and the splash session check. |
| RNF02/03/04 (PII, retention, RLS) | N/A to F000 | Backend-side; no app logic introduced or required. |
| RNF05 (hard delete) | N/A to F000 | Belongs to the Settings/RF09 unit; Configurações is an inert placeholder here. |
| RNF06 (layer violations) | PASS | Enforced structurally by folder convention; domain entities/usecases/repositories contain no Flutter or data imports. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | Applies to `session` and `auth` domain layers delivered here. |
| RNF08 (visual fidelity) | PASS | All 5 screens sourced from `design_tokens.dart`; see data-model.md. |
| RNF09 (Either + 15/15 error scenarios) | PARTIAL BY DESIGN, not a violation | RNF09's full target is 5 write endpoints × 3 failures, reached incrementally across the whole delivery order (requirements.md §12). F000 contributes the `Either` pattern itself (used by every later repository) plus full timeout/malformed/offline coverage for its own 3 write-ish auth calls (signup, login, refresh — `auth-session` is a read). No Complexity Tracking entry needed: this is the staged rollout the delivery order already anticipates, not a deviation. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/001-foundation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── http-client.md
│   ├── failure-taxonomy.md
│   ├── auth-repository.md
│   └── session-repository.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

No Flutter project exists yet in this repository (no `pubspec.yaml`/`lib/` found) — F000 creates it.

```text
cerne-ciclo-a/                      # repo root (unchanged: docs/, .specify/, specs/, .env)
├── .fvmrc                          # pins Flutter 3.47.5 / Dart 3.13.4
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── design_tokens.dart          # single source of colors, typography, spacing, radii
│   │   ├── network/
│   │   │   ├── api_client.dart         # dio wrapper: base URL + apikey + bearer injection
│   │   │   ├── failure.dart            # sealed Failure hierarchy, all 13 error codes
│   │   │   └── error_mapper.dart       # {code,message,retryable,requestId} -> Failure
│   │   ├── storage/
│   │   │   └── secure_token_storage.dart
│   │   ├── routing/
│   │   │   ├── app_router.dart         # go_router config + root navigatorKey
│   │   │   └── app_routes.dart
│   │   └── di/
│   │       └── service_locator.dart    # get_it registrations
│   └── features/
│       ├── splash/
│       │   └── presentation/
│       │       └── pages/splash_page.dart
│       ├── session/
│       │   ├── data/
│       │   │   ├── session_remote_data_source.dart   # GET auth-session
│       │   │   └── session_repository_impl.dart
│       │   ├── domain/
│       │   │   ├── entities/session_status.dart
│       │   │   ├── repositories/session_repository.dart
│       │   │   └── usecases/check_session_usecase.dart
│       │   └── presentation/
│       │       ├── bloc/session_bloc.dart            # splash routing + expired-session trigger
│       │       └── widgets/session_expired_overlay.dart
│       ├── auth/
│       │   ├── data/
│       │   │   ├── auth_remote_data_source.dart       # auth-signup, auth-login, auth-refresh
│       │   │   └── auth_repository_impl.dart
│       │   ├── domain/
│       │   │   ├── entities/account.dart
│       │   │   ├── repositories/auth_repository.dart
│       │   │   └── usecases/{sign_up,login}_usecase.dart
│       │   └── presentation/
│       │       ├── bloc/auth_bloc.dart
│       │       └── pages/login_signup_page.dart
│       ├── home/
│       │   └── presentation/
│       │       ├── pages/home_chat_shell_page.dart    # inert composer, per FR-016
│       │       └── widgets/app_drawer.dart
│       ├── records/
│       │   └── presentation/pages/records_placeholder_page.dart
│       └── settings/
│           └── presentation/pages/settings_placeholder_page.dart
└── test/
    ├── core/network/...
    └── features/{session,auth}/domain/...             # RNF07 gate lives here
```

**Structure Decision**: Single Flutter mobile app at the repo root (`lib/`, `test/`), following the
constitution's fixed `core/` + `features/<feature>/{data,domain,presentation}` convention exactly.
`docs/`, `.specify/`, and `specs/` are untouched. No `backend/`/`api/` tree is created — the backend
is frozen and consumed only through `docs/input/backend/`.

## Complexity Tracking

*No entries — no principle was violated or bent; every "free" choice (routing, HTTP client, DI,
secure storage) is justified in research.md within the constitution's explicitly open decisions.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `design_tokens.dart`'s shape (data-model.md §Design Tokens) holds every color/type/spacing/radius
  value as a `static const`; no screen or widget in the structure above has a reason to define one
  locally — RNF08/Principle IV remain satisfied by construction.
- `Failure` (contracts/failure-taxonomy.md) covers all 13 backend codes, not just the ones F000's
  4 endpoints can return today — every later unit's repository reuses this type without redefining
  it, keeping RNF09's `Either<Failure, T>` pattern identical across the whole app.
- `AuthRepository` and `SessionRepository` (contracts/auth-repository.md,
  contracts/session-repository.md) depend only on domain entities (`Account`, `SessionStatus`,
  `Failure`) — no Flutter, no `data/` import — confirming RNF06/Principle V before any code exists.
- No change surfaced that touches `docs/input/backend/api/openapi.yaml`, the `.env` shape, or any
  AI provider — Principle III remains intact.

No new violations. Gate remains PASS.
