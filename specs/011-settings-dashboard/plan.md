# Implementation Plan: P-RF09 — Temporal summaries / dashboard

**Branch**: `011-settings-dashboard` (spec directory only — no git branch exists; none of this repo's
extension hooks are configured, per spec.md's own header)

**Date**: 2026-10-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-settings-dashboard/spec.md`, `docs/input/requirements.md`
§1 (RF09), §4 (RNF05), §6.6–6.7 (`dashboard-aggregate-get`/`dashboard-narrative-get`/`account-settings-update`/
`account-delete`), §6.1 (`auth-logout`), §8 (data model reference), §9 (stack), §13; `docs/input/backend/api/
openapi.yaml`'s `/dashboard/*`, `/account*`, `/auth/logout` schemas; `docs/input/backend/README.md`'s
function-name mapping; `docs/input/backend/error-taxonomy.md`; `docs/input/prototype/prototype-extract.md`
§2.6, §6; and `.specify/memory/constitution.md`. Depends on F000 (session, login, routing) and RF01 (entries
exist to aggregate), both already implemented. This is the unit that replaces `SettingsPlaceholderPage` (the
route `AppRoutes.settings` already points at a static "Ainda não disponível." placeholder) with the real
screen, and that finally wires in the real display name `app_drawer.dart`'s own stand-in email-derivation
comment has been waiting for since F000.

## Summary

The Settings screen (`AppRoutes.settings`, currently `SettingsPlaceholderPage`) becomes a real, four-concern
screen backed by one screen-scoped `SettingsBloc`: (1) an evolution dashboard — `GET /dashboard/aggregate` and
`GET /dashboard/narrative` as two independent calls, the aggregate's ten-bar chart built by a new pure
derivation (`DashboardAggregate.tenBars()`, research.md R2) and rendered with plain `Container`-based bars
(no new charting dependency, research.md R3); (2) an editable profile header (52px initials avatar, inline
pencil-to-check name editing via `PATCH /account/settings`, read-only email) backed by a new, narrow
`AccountProfileRepository` whose confirmed writes persist into a new `AccountProfileLocalCache`
(`features/settings/data/`, Keychain-backed) — the one local mirror this unit adds, since no earlier unit
ever wrote `displayName`; (3) a biometrics toggle that is hidden entirely on a device with no usable
capability and otherwise reuses RF03's own `BiometricsPreferenceRepository`/`VaultRepository` as-is behind a
new, settings-owned, await-then-revert usecase (research.md R6) rather than RF03's deliberately
fire-and-forget one; (4) "Sair" (extends the existing `AuthRepository` with one new method, `logout()`) and
"Apagar conta" (a new `AccountDeletionRepository`, `DELETE /account`), both ending in the same
clear-local-state-and-navigate sequence spec.md's own Assumptions resolve to the existing vault/login routes
(research.md R10) — deletion alone additionally wipes `EntriesLocalCache`/`ChatLocalCache` (both extended in
place with a new `clear()` method) since "any other locally held user data" (FR-019) is a strictly wider
clear than logout's own FR-016 wording. `app_drawer.dart` is extended in place to read the same cached display
name (research.md R13), and `SettingsPage` becomes `RouteAware` on the already-existing `chatRouteObserver` so
re-authenticating mid-screen re-requests fresh data rather than only preserving stale state (research.md R15).

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from every prior
unit.

**Primary Dependencies**: None added. Reuses the full existing stack — `flutter_bloc`, `fpdart`, `get_it`,
`equatable`, `dio` (via `ApiClient`, no new method needed — every call here is a plain JSON `call()`, the same
shape `BiometricsPreferenceRemoteDataSource` already uses), `flutter_secure_storage` (via a new
`AccountProfileLocalCache`, same pattern as `VaultSecureStorage`/`EntriesLocalCache`), `local_auth` (indirectly,
through the unmodified `VaultRepository`), `go_router` (no new route — `AppRoutes.settings` already exists;
only its builder changes); dev-only `mocktail`, `bloc_test`. Research.md R3 explicitly rejects adding a
charting package — the 10-bar chart is plain `Container`s.

**Storage**: One new on-device key, `AccountProfileLocalCache`'s single `settingsDisplayName` Keychain entry
(research.md R5/R7) — the only new local persistence this unit introduces. `DashboardAggregate`/
`DashboardNarrative` are explicitly never persisted (FR-008 — "recomputed fresh... never served from a result
cached from a previous visit"), unlike `EntriesLocalCache`/`ChatLocalCache`'s own cross-restart caches.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via `fvm flutter test
--coverage`, same `lib/**/domain/**` lcov filter (RNF07), now additionally exercising
`DashboardAggregate.tenBars()`'s pure bucketing (research.md R2 — the single richest piece of new domain
logic this unit adds, mirroring `DateRangeFilter`/`SyncBadgeState`'s existing pure-derivation test shape),
`AccountProfile.isValidDisplayName`/`.initials`/`.defaultDisplayNameFromEmail`, and
`SaveSettingsBiometricPreferenceUseCase`'s await-then-mirror-or-revert branches (contracts/
biometric-preference-settings-extension.md) against `mocktail` fakes of `BiometricsPreferenceRepository`/
`VaultRepository` — no new fakes needed for `local_auth`/`flutter_secure_storage` themselves, since neither is
touched directly by anything new.

**Target Platform**: iOS, portrait only — unchanged. No native project file touched; no new package needs an
iOS install step.

**Project Type**: Same single Flutter mobile app. One new feature folder, `lib/features/settings/`
(domain/data/presentation, Principle V) replacing the one-file `SettingsPlaceholderPage` (deleted); three
existing files extended in place — `lib/features/auth/domain/repositories/auth_repository.dart` (+
`data`/`impl`, + `logout()`), `lib/features/entries/domain/repositories/entries_repository.dart` (+ `impl`, +
`clearLocalData()`), `lib/features/chat/domain/repositories/chat_repository.dart` (+ `impl`, +
`clearLocalData()`) — plus their respective local caches (`EntriesLocalCache`/`ChatLocalCache`) each gaining a
new `clear()` method; `lib/features/home/presentation/widgets/app_drawer.dart` (display-name read, research.md
R13); `lib/core/routing/app_router.dart` (`AppRoutes.settings`'s builder); `lib/core/design_tokens.dart` (5 new
tokens, research.md R14); `lib/core/di/service_locator.dart`. No backend/server code, no change to
`docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 unchanged. The optimistic UI flips this unit adds — the biometric toggle's
immediate visual change before its network write resolves, and the name field's immediate return to display
mode is deliberately *not* optimistic (it waits for the `Right`, since a wrong optimistic name could be shown
then silently reverted, worse than a brief wait) — reflect within 100ms where used; every network call in
this unit's flow (dashboard load, name save, toggle save, sign-out, deletion) already has a loading indicator
by construction (`dashboardStatus == loading`, `nameEditStatus == saving`, `biometricSaving`, `isSigningOut`,
`isDeletingAccount` each drive one), satisfying the >300ms affordance requirement.

**Constraints**:
- No period-switching UI control (FR-002) — the dashboard always requests the fixed `period=all`.
- No AI persona selector or any other extension feature (FR-015) — `account-settings-update`'s `persona`
  field is never sent by this unit's requests and never read from its responses.
- No functionality belonging to a unit later than RF09 in the build order, and no backend/contract/config
  change (FR-024) — every endpoint this unit calls is one `docs/input/backend/api/openapi.yaml` already
  documents, called exactly as documented (contracts/*.md's own request-shape listings).
- Clean Architecture, 3 layers per feature (Principle V) — `settings/domain/` imports only `equatable`/
  `fpdart`/`core/network/failure.dart`; `SettingsBloc` depends on `settings/domain/` repositories/usecases plus
  two other features' already-domain-layer interfaces (`vault/domain/`'s `BiometricsPreferenceRepository`/
  `VaultRepository`, `auth/domain/`'s `AuthRepository`, `session/domain/`'s `SessionRepository`,
  `entries/domain/`'s `EntriesRepository`, `chat/domain/`'s `ChatRepository`) — never any other feature's
  `presentation/bloc/` (enforced by `test/architecture/no_bloc_imports_bloc_test.dart`, unmodified, which
  already scans every `presentation/bloc/` path recursively).
- FR-022's concurrency guard is satisfied by `SettingsState`'s own `isSigningOut`/`isDeletingAccount` booleans
  (research.md R12), not a shared/persisted flag — the same shape `ExportBloc`'s own tap-guard already uses.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — the 5 genuinely
  new values this unit needs (data-model.md's token table, research.md R14) are added there, not inlined.

**Scale/Scope**: 1 new feature folder (`settings/`) with 4 domain entities + 1 pure bucketing extension, 3
repository interfaces + 1 reused usecase pattern (1 new settings-owned usecase), 3 data classes (2 remote data
sources + 1 local cache) + 3 repository impls, 1 bloc (+events/states), ~7 new presentation widgets; 3
existing features' interfaces each extended by exactly one method (+ impl); 2 existing local caches each
gaining a `clear()` method; 1 existing widget (`app_drawer.dart`) extended in place; 1 deleted file
(`settings_placeholder_page.dart`); 5 new `DesignTokens` values; ~14 new DI registrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only. Every technical-judgment decision this plan makes (R1–R16, research.md) is built directly on spec.md's own FRs/Clarifications/Assumptions/Edge-Cases wording — the data-flow split (R1), the bucketing arithmetic (R2), the no-new-dependency chart (R3), the flat composite state shape (R4), the per-field caching split (R5), the biometric await-revert usecase (R6), the narrow display-name repository (R7), the logout/deletion homing (R8), the clear-scope split (R9), the post-action destination (R10), the reauth-stream wiring (R11), the concurrency guards (R12), the extracted email-derivation (R13), the 5 new tokens (R14), the `RouteAware` post-reauth refresh (R15) — none reopens a resolved Clarification. |
| II. Fixed Technology Stack | PASS | No change to `flutter_bloc`/`fpdart`/`get_it`/Clean Architecture. Zero new dependencies (research.md R3) — the first unit in the delivery order to need no pubspec addition at all. |
| III. Backend Boundary | PASS | Only already-contracted functions called (`dashboard-aggregate-get`, `dashboard-narrative-get`, `account-settings-update`, `account-delete`, `auth-logout` — `docs/input/backend/README.md`'s own path→function table); no AI provider called directly (the narrative's Claude Haiku 4.5 generation stays entirely server-side, consumed only as the already-generated `text` field). `account-delete`'s `confirmation: "DELETE"` value is supplied by the app itself, never collected from the user as free text — no new surface for a credential/secret to leak through. |
| IV. Design Token Discipline & Visual Fidelity | PASS | 5 new `DesignTokens` values (research.md R14/data-model.md), each traceable to either the prototype's own stated dimension (`sizeAvatarSettings = 52`, prototype-extract.md §6) or a reasonable, narrowly-scoped new value where the prototype's token panel is silent on chart geometry — never an inline literal in a widget file. UI text — "Comece a registrar para ver sua evolução aqui," "Ainda é cedo pra ver um padrão — volte em alguns dias.," "Apagar sua conta?," "Apagar tudo," "Cancelar," "Sair," "Apagar conta" — is exactly as spec.md's own FR/Acceptance-Scenario wording and prototype-extract.md §2.6 state it, in Portuguese; the one new copy this unit must author itself (the "narrativa indisponível" message's exact sentence, since the prototype names the state but not its literal string) is written in Portuguese consistent with the rest of the screen's register. |
| V. Clean Architecture Folder Convention | PASS | `settings/domain/` imports only `equatable`/`fpdart`/`core/network/failure.dart` — confirmed against `domain_purity_test.dart` (unmodified, scans recursively). `SettingsBloc`'s dependency surface is exactly the repository/usecase interfaces listed in Technical Context's own Constraints entry — no other feature's `presentation/bloc/` import (confirmed against `no_bloc_imports_bloc_test.dart`, unmodified). |
| RNF01 (latency) | PASS | See Technical Context's own Performance Goals entry — every network call in this unit's flow already shows a loading indicator by construction; the two deliberately-optimistic flips (biometric toggle) reflect in well under 100ms, the two deliberately-non-optimistic ones (name save, sign-out/deletion's final navigation) wait for a confirmed result by design, not by omission. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF09 | Backend-side; this unit sends no new PII-bearing content (a display name and a boolean are the only new request bodies) and introduces no new on-device retention beyond the one Keychain key already covered under Storage above. |
| RNF05 (hard delete) | PASS | This is the unit RNF05 names explicitly — `DELETE /account` is exposed from Settings exactly as required, gated behind the prototype's own two-button confirmation dialog (FR-017/FR-018), with the app-side local-data clear (research.md R9) going beyond the backend's own cascade to also remove every on-device trace this app itself holds. |
| RNF06 (layer violations) | PASS | No `settings/domain/` file imports Flutter or a `settings/data/` class; `SettingsBloc` imports no other feature's `presentation/bloc/` path — both mechanically re-confirmed by the two unmodified architecture tests after this unit's files exist (Post-Design section below). |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `DashboardAggregate.tenBars()` is a pure, total function over `(buckets, today)` with zero I/O (research.md R2) — as directly testable as `DateRangeFilter`/`SyncBadgeState`; `AccountProfile`'s three pure helpers and `SaveSettingsBiometricPreferenceUseCase`'s branches are equally testable against `mocktail` fakes, same shape as every prior unit's own domain coverage. |
| RNF08 (visual fidelity) | PASS | Every state matches prototype-extract.md §2.6's own four named dashboard variations plus the confirmation dialog's own described layout — no approximated layout or invented component beyond what spec.md/the prototype already name (the "narrativa indisponível" message's exact wording is the one genuinely new copy, same as RF05's own one new "erroCompleto" string had to be). |
| RNF09 (Either + 15/15 error scenarios) | PASS (gate carried into tasks) | Two new write endpoints (`account-delete`, `auth-logout`) and one extended existing one (`account-settings-update`'s `displayName` body shape, already RF03-counted) each get full timeout/malformed/no-connection coverage per contracts/*.md's own scenario tables (research.md R16) — this plan does not assert a specific final project-wide fraction, consistent with every prior unit's own hedging on that number. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/011-settings-dashboard/
├── plan.md                                          # This file
├── research.md                                      # Phase 0 output
├── data-model.md                                     # Phase 1 output
├── quickstart.md                                     # Phase 1 output
├── contracts/                                        # Phase 1 output
│   ├── dashboard-repository.md
│   ├── account-profile-repository.md
│   ├── biometric-preference-settings-extension.md
│   ├── account-deletion-repository.md
│   ├── account-session-actions.md
│   ├── settings-bloc.md
│   └── app-drawer-display-name-extension.md
└── tasks.md                                          # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
└── lib/
    ├── core/
    │   ├── design_tokens.dart                          # + 5 new values (research.md R14)
    │   ├── routing/
    │   │   └── app_router.dart                         # AppRoutes.settings builder → real SettingsPage
    │   └── di/
    │       └── service_locator.dart                    # + Settings registrations
    └── features/
        ├── auth/
        │   ├── domain/repositories/auth_repository.dart     # + logout()
        │   ├── data/auth_remote_data_source.dart             # + logout()
        │   └── data/auth_repository_impl.dart                 # + logout()
        ├── entries/
        │   ├── domain/repositories/entries_repository.dart  # + clearLocalData()
        │   ├── data/entries_local_cache.dart                  # + clear()
        │   └── data/entries_repository_impl.dart               # + clearLocalData()
        ├── chat/
        │   ├── domain/repositories/chat_repository.dart      # + clearLocalData()
        │   ├── data/chat_local_cache.dart                       # + clear()
        │   └── data/chat_repository_impl.dart                    # + clearLocalData()
        ├── home/presentation/widgets/app_drawer.dart          # display-name read (research.md R13)
        ├── vault/                                              # UNMODIFIED — reused as-is (research.md R6)
        └── settings/
            ├── domain/
            │   ├── entities/
            │   │   ├── account_profile.dart                  # NEW — AccountProfile + its 3 pure helpers
            │   │   ├── dashboard_aggregate.dart              # NEW — AggregateBucket, DashboardSourceCounts,
            │   │   │                                         #   DashboardTotals, DashboardAggregate, tenBars()
            │   │   └── dashboard_narrative.dart              # NEW
            │   ├── repositories/
            │   │   ├── dashboard_repository.dart             # NEW
            │   │   ├── account_profile_repository.dart        # NEW
            │   │   └── account_deletion_repository.dart        # NEW
            │   └── usecases/
            │       └── save_settings_biometric_preference_usecase.dart  # NEW (research.md R6)
            ├── data/
            │   ├── dashboard_remote_data_source.dart
            │   ├── dashboard_repository_impl.dart
            │   ├── account_settings_remote_data_source.dart   # PATCH account-settings-update {displayName}
            │   ├── account_profile_local_cache.dart             # NEW on-device key (research.md R5)
            │   ├── account_profile_repository_impl.dart
            │   ├── account_deletion_remote_data_source.dart
            │   └── account_deletion_repository_impl.dart
            └── presentation/
                ├── bloc/
                │   └── settings_event.dart / settings_state.dart / settings_bloc.dart   # NEW
                ├── pages/
                │   └── settings_page.dart                     # NEW — replaces settings_placeholder_page.dart
                └── widgets/
                    ├── dashboard_card.dart                      # switches empty/single/multi/error/narrative
                    ├── dashboard_bar_chart.dart                 # the 10-bar widget (research.md R3)
                    ├── narrative_view.dart
                    ├── profile_header.dart                      # avatar + inline name edit + email
                    ├── biometric_toggle_row.dart
                    └── delete_account_dialog.dart
```
`lib/features/settings/presentation/pages/settings_placeholder_page.dart` is deleted — its one reference
(`app_router.dart`'s `AppRoutes.settings` route) is repointed at `SettingsPage`, the same "promote the
placeholder to the real screen" step `RecordsPlaceholderPage`→`RecordsPage` already went through earlier in
the delivery order.

**Structure Decision**: One new feature folder, `settings/`, following the exact three-layer convention every
prior unit already established. `vault/` is deliberately left untouched (research.md R6) — Settings is a new
*caller* of its existing repositories, not a modifier of them, which keeps RF03's own already-shipped,
already-tested first-time-setup flow risk-free. `auth/`/`entries/`/`chat/` are each extended by exactly one
new method on an already-existing interface, the same "extend an earlier unit's file in place" precedent
RF05 already set on `records_page.dart` — each addition is additive (a new method), never a signature change
to an existing one, so no caller of the pre-existing methods needs to change.

## Complexity Tracking

| Addition | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A second, settings-owned biometric-save usecase (`SaveSettingsBiometricPreferenceUseCase`, research.md R6) alongside RF03's existing fire-and-forget one | FR-014 requires revert-on-failure; RF03's `SaveBiometricsPreferenceUseCase` deliberately never reports failure back to its caller — the two requirements are contradictory for the same repository call | Changing RF03's existing usecase's contract to support both modes (a flag/callback) — rejected: risks the already-shipped first-time-setup flow for a concern (Settings' revert UX) that first-time setup itself never needed |
| A new, settings-owned `AccountProfileLocalCache` rather than extending `VaultSecureStorage` with a `displayName` key | `displayName` has nothing to do with the vault/PIN domain `VaultSecureStorage` exists for; bolting an unrelated field onto it would blur that class's single responsibility for no benefit, since nothing about name caching needs anything `VaultSecureStorage` already provides | Adding a `displayName` key directly to `VaultSecureStorage` — rejected: couples two unrelated concerns (device-unlock secrets vs. a display preference) in one storage class, the same kind of bolt-on RF03's own `BiometricsPreferenceRepository` comment explicitly warns against ("rather than a general-purpose account-settings repository") |
| `EntriesLocalCache`/`ChatLocalCache` each gaining a `clear()` method | FR-019's "any other locally held user data" has no existing mechanism to satisfy — neither class has ever needed to forget everything it knows before this unit | Leaving stale entries/chat history on-device after a hard account delete — rejected outright by RNF05/FR-019's own wording, not a style choice |

*No entry needed beyond these three — the chart's no-new-dependency choice (R3) and the zero-new-Failure
-subtype outcome (every error code RF09's endpoints can return already exists in `failure.dart`) are each a
reduction in complexity, not an addition requiring justification.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `settings/domain/entities/*.dart` and `settings/domain/repositories/*.dart` were re-checked against their
  actual planned imports: `equatable`, `fpdart` (`Either`/`Unit`), `core/network/failure.dart` only — no
  `package:flutter`, no `settings/data/` class. `domain_purity_test.dart` needs no change to keep covering
  this folder; it already scans every `domain/` path recursively.
- `SettingsBloc`'s dependency surface was re-checked against data-model.md's own repository/usecase list: six
  repository/usecase types, all from `domain/` folders (`settings/`, `vault/`, `auth/`, `session/`,
  `entries/`, `chat/`), zero `presentation/bloc/` imports from any other feature. `no_bloc_imports_bloc_test.dart`
  needs no change either, for the same reason.
- Re-checked that `AuthRepositoryImpl.logout()` does not call `SecureTokenStorage`/`SessionRepository.clear()`
  itself (contracts/account-session-actions.md) — keeping that repository's existing "writes, never deletes"
  shape intact, with the clearing sequence living only in `SettingsBloc`.
- Re-checked that `VaultSecureStorage`'s two existing keys (PIN hash, biometrics-preference mirror) appear in
  no new file's planned write path — `research.md R9`/R10's "deliberately untouched" claim confirmed against
  the actual contracts/account-session-actions.md and contracts/account-deletion-repository.md listings, not
  just asserted.
- Re-checked `DashboardAggregate.tenBars()`'s planned signature: `(List<AggregateBucket>, {DateTime? today})`
  → `List<int>`, zero constructor dependencies, zero I/O — confirmed pure in data-model.md's own listing, the
  one piece of new domain logic RNF07 most needs to hit ≥80% on.
- Re-checked that no change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native
  iOS project file, or calls an AI provider directly — Principle III remains intact; the narrative's `text`
  field is read and displayed verbatim, never post-processed or evaluated by this app.
- Re-checked `app_drawer.dart`'s planned extension (contracts/app-drawer-display-name-extension.md) against
  Principle V: it depends on `AccountProfileRepository` (a `settings/domain/` interface, resolved via
  `get_it`) and `AccountProfile`'s static helper, never on `AccountProfileLocalCache` (`settings/data/`)
  directly — the same "presentation depends on another feature's domain interface" shape `ChatBloc`'s own
  import of `entries/domain/usecases/create_entry_usecase.dart` already establishes, not a new, unprecedented
  presentation-reaches-into-another-feature's-data shape.

No new violations. Gate remains PASS.
