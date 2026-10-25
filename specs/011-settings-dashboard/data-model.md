# Data Model: P-RF09 — Temporal summaries / dashboard

Phase 1 output. Field names are this unit's own typed wrapper around `docs/input/backend/api/openapi.yaml`'s
`/dashboard/*`/`/account*`/`/auth/logout` schemas (research.md R1/R6/R7/R8/R9) — where this document and the
contract ever disagree, the contract prevails (Constitution Principle I).

## Domain entities (`lib/features/settings/domain/entities/`)

### `AggregateBucket`
| Field | Type | Notes |
|---|---|---|
| `date` | `DateTime` | Parsed from the backend's `YYYY-MM-DD` string, date-only (no time component kept). |
| `count` | `int` | ≥ 0. |
| `sources` | `DashboardSourceCounts` | `{manual, audio, photo, chat}`, each `int` ≥ 0 — carried for completeness; this unit's chart only ever renders `count` (no per-source stacking/legend in scope). |

### `DashboardTotals`
`{count: int, sources: DashboardSourceCounts}` — the account-wide total for the requested period.

### `DashboardAggregate`
`{buckets: List<AggregateBucket>, totals: DashboardTotals}`. One pure extension method:
- `List<int> tenBars({DateTime? today})` → `research.md R2`'s `tenBars` function, `today` defaulting to
  `DateTime.now()` but overridable for deterministic tests.

### `DashboardNarrative`
`{text: String, generatedAt: DateTime}` — `generatedAt` is parsed but never displayed (spec.md: the
narrative's own content/quality is out of scope); kept only because the response always carries it and
dropping a required field silently would be a worse modeling choice than keeping it unused.

### `AccountProfile`
| Field | Type | Notes |
|---|---|---|
| `displayName` | `String` | 1–80 chars once set; the screen's single source of truth for both the name field and avatar initials. |
| `email` | `String` | Read-only in this unit (FR-009); sourced from `SessionRepository`'s already-resolved `Account.email`, never from a Settings-owned call. |

Static/instance helpers (research.md R13):
- `static String defaultDisplayNameFromEmail(String email)` — splits the email's local part on `._-`,
  title-cases each word, joins with a space (`"wagner.duarte@x.com"` → `"Wagner Duarte"`); `email` itself if
  the local part is empty.
- `String get initials` — 1–2 uppercase letters from `displayName`'s whitespace-split words (first letter of
  the first word, plus first letter of the second word if one exists); `"?"` if `displayName` is empty.
- `static bool isValidDisplayName(String value)` — `value.trim().isNotEmpty && value.trim().length <= 80`
  (FR-011) — pure, used by both the bloc (to block a bad submit client-side) and its own unit test.

## Repository interfaces (`lib/features/settings/domain/repositories/`)

### `DashboardRepository`
```dart
Future<Either<Failure, DashboardAggregate>> fetchAggregate();
Future<Either<Failure, DashboardNarrative>> fetchNarrative();
```
Both internally fixed to `period=all` (no parameter exposed, FR-002). Both retry exactly once via
`SessionRepository.refresh()` on `AuthExpiredFailure` (same shape as `EntriesRepositoryImpl`); a second
`AuthExpiredFailure` after that retry is returned as-is and triggers `SettingsBloc.reauthRequired`.

### `AccountProfileRepository`
```dart
Future<String?> readCachedDisplayName();                     // local-only, no network
Future<Either<Failure, String>> updateDisplayName(String name); // PATCH account-settings-update
Future<void> clearCachedDisplayName();                         // used by both Sair and Apagar conta
```
`updateDisplayName` persists the confirmed name into `AccountProfileLocalCache` before returning `Right` —
the local cache and "last confirmed backend value" are the same write, never two.

### `AccountDeletionRepository`
```dart
Future<Either<Failure, Unit>> deleteAccount(); // DELETE /account, confirmation: "DELETE" supplied internally
```

### Reused, unmodified, from other features (research.md R6/R8/R9)
- `BiometricsPreferenceRepository.save(bool)` (`vault/domain/`) — the network write.
- `VaultRepository.isBiometricPreferenceEnabled()` / `.setBiometricPreferenceLocally(bool)` /
  `.checkBiometricCapability()` / `.hasPinConfigured()` (`vault/domain/`) — local mirror + capability +
  post-logout destination.
- `AuthRepository.logout()` (`auth/domain/`, new method on an existing interface) — `POST /auth/logout`.
- `SessionRepository.clear()` (`session/domain/`) — wipes `SecureTokenStorage`.
- `EntriesRepository.clearLocalData()` / `ChatRepository.clearLocalData()` (new methods on existing
  interfaces) — wipe each feature's in-memory mirror + call its local cache's new `clear()`.

## Use cases (`lib/features/settings/domain/usecases/`)

### `SaveSettingsBiometricPreferenceUseCase`
`Future<Either<Failure, void>> call(bool enabled)` — research.md R6's await-then-mirror-or-revert sequence.
Depends on `BiometricsPreferenceRepository` + `VaultRepository` (both `vault/domain/`).

No other usecase classes are introduced — `DashboardRepository`/`AccountProfileRepository`/
`AccountDeletionRepository`'s methods are each already a single, narrow operation (the same "repository method
is usecase-shaped" choice `ExportBloc`/`ChatBloc` already make for most of their own calls); `SettingsBloc`
calls them directly.

## `SettingsState` (`lib/features/settings/presentation/bloc/settings_state.dart`, research.md R4)

One `Equatable` class, `copyWith` with the `RecordsLoaded`-style `_unset` sentinel for every nullable field
that must be explicitly clearable to `null`.

| Field | Type | Default | Notes |
|---|---|---|---|
| `dashboardStatus` | `DashboardStatus` enum: `loading, loaded, loadFailure` | `loading` | |
| `aggregate` | `DashboardAggregate?` | `null` | Set once `dashboardStatus == loaded`. |
| `dashboardFailure` | `Failure?` | `null` | Set once `dashboardStatus == loadFailure`; retryable per FR-007. |
| `narrativeStatus` | `NarrativeStatus` enum: `notRequested, loading, loaded, unavailable` | `notRequested` | `notRequested` for the zero/one-entry cases (FR-003/004); never transitions once there (FR-006's distinctness). |
| `narrativeText` | `String?` | `null` | Set once `narrativeStatus == loaded`. |
| `displayName` | `String` | `''` (loading placeholder) | The name actually shown — cached/edited value or the email-derived default once email is known. |
| `email` | `String` | `''` | From `SessionRepository`; read-only display. |
| `nameEditStatus` | `NameEditStatus` enum: `viewing, editing, saving, error` | `viewing` | |
| `nameDraft` | `String` | `''` | The in-progress edit field's text — preserved across a failed save (FR-012). |
| `nameEditFailureMessage` | `String?` | `null` | Validation (FR-011) or network (FR-012) message; cleared on re-entering edit mode. |
| `biometricToggleVisible` | `bool` | `false` | `true` only when `VaultRepository.checkBiometricCapability() == available` (FR-013's "hidden entirely" rule). |
| `biometricEnabled` | `bool` | `false` | Mirrors `VaultRepository.isBiometricPreferenceEnabled()` until a confirmed toggle changes it. |
| `biometricSaving` | `bool` | `false` | |
| `biometricFailureMessage` | `String?` | `null` | Set on a reverted save (FR-014); cleared on the next toggle attempt. |
| `isSigningOut` | `bool` | `false` | FR-022 guard. |
| `isDeletingAccount` | `bool` | `false` | FR-022 guard. |
| `deleteDialogOpen` | `bool` | `false` | Presentation-only flag the page uses to show/hide the confirmation dialog (FR-017/FR-021) — no backend call is implied by this alone. |
| `deleteFailureMessage` | `String?` | `null` | FR-020; shown inside the still-open dialog. |
| `signedOut` | `bool` | `false` | A one-shot signal — `SettingsPage`'s `BlocListener` navigates to `AppRoutes.login` on `true` and the bloc never emits `false` again after. Superseded a `SettingsDestination?` (`vault`/`login`) field per research.md R10's correction note — login is now the only possible destination. |
| `accountDeleted` | `bool` | `false` | Same shape as above, for the deletion success path — kept as a separate field from `signedOut` only so a listener can tell which flow completed if ever needed for analytics/logging; both drive identical navigation. |

## Widgets and the tokens they consume (RNF08 — zero hardcoded values)

| Widget | New tokens used | Reused tokens |
|---|---|---|
| `ProfileHeader` (avatar + name + email) | `sizeAvatarSettings` (52) | `colorPrimary`, `colorOnPrimary`, `textTitleSm`, `textBodyMd`, `colorTextSecondary`, `spacingLg/Md` |
| `DashboardBarChart` (populated/one-bar states) | `sizeChartBarMaxHeight`, `sizeChartBarWidth`, `sizeChartBarGap` | `colorAccent` (ochre bars) |
| `DashboardEmptyState` (zero entries) | `colorChartPlaceholder` | `textBodyMd`, `colorTextSecondary` |
| `NarrativeView` (loaded / unavailable) | — | `textBodyMd`, `colorTextSecondary`, `colorError` |
| `BiometricToggleRow` | — | `textBodyLg`, `Switch` theme colors already derived from `AppTheme.theme` |
| `DeleteAccountDialog` | — | `colorError`, `textTitleLg`, `textBodyMd`, `radiusLg`, `elevation2` (same "confirmation dialog" component the session-expired overlay already uses) |

New `DesignTokens` additions (research.md R14), appended to the existing Sizes/Colors sections, values only:
`sizeAvatarSettings = 52`, `sizeChartBarMaxHeight = 120`, `sizeChartBarWidth = 20`, `sizeChartBarGap = 6`,
`colorChartPlaceholder = Color(0xFFE1DACB)` (= `colorBorder`'s own value, reused under a semantically distinct
name since the token panel's "placeholder chart icon" use is conceptually different from "dividers, borders"
even though the color is the same).
