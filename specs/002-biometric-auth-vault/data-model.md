# Data Model: P-RF03 — Biometric authentication vault

Source: spec.md §Key Entities, requirements.md §§1, 6.1, 10, prototype-extract.md §§2.1, 3.
Entities here are either on-device-only domain objects (Device PIN, Vault Lock State) or a local
mirror of one backend field (Biometrics Preference) — this unit introduces no new backend table
and no new local database (just two new secure-storage keys alongside F000's four).

## Device PIN

A 4-digit secret, created once (User Story 3) and checked on every subsequent unlock attempt
(User Stories 1–2). Never transmitted to, or validated by, the backend (FR-002).

| Field | Type | Notes |
|---|---|---|
| `pinHash` | `String` (hex, sha256) | Written by `VaultSecureStorage`; see research.md R2 for why the raw digit string is never the thing stored. |

**Validation rule**: exactly 4 digits, each `0`–`9`, no partial/shorter value ever written or
compared (FR-005). Confirmation during setup is a pure string-equality check between two freshly
entered 4-digit values — the first one is held only in memory (`VaultState`) between entry and
confirmation, never written to storage until it matches (FR-012: "without the mismatched PIN being
saved").

## Vault Lock State

Whether the current app process currently requires authentication before showing data, and when it
was last satisfied — the input to the 5-minute background-resume rule (FR-007–FR-010).

| Field | Type | Notes |
|---|---|---|
| `lastUnlockedAt` | `DateTime?` | In-memory only, held by the `VaultRepository` singleton (one instance for the app's lifetime via `get_it`'s `registerLazySingleton`). `null` until the first successful unlock this process. Never persisted to disk — see research.md R3 for why a killed/relaunched process doesn't need this to survive. |
| `backgroundedAt` | `DateTime?` | Set by `VaultLifecycleObserver` on `AppLifecycleState.paused`; read and cleared on the matching `.resumed`. In-memory only, same lifetime as `lastUnlockedAt`. |

**Derived decision — `VaultEntryMode`** (domain enum/sealed type, computed by
`DetermineVaultEntryUseCase` every time `VaultPage` opens):

```
pinSetupRequired                      # hasPinConfigured() == false
unlockBiometricFirst                  # PIN exists AND biometric capability == available
                                       #   AND the local biometrics-preference mirror == true
unlockPinOnly                         # PIN exists AND (no biometric capability OR preference == false)
```

**State transitions**:

```
[SplashPage, SessionStatusAuthenticated]  or  [LoginSignupPage, AuthStatus.authenticated (non-reauth)]
  context.push(AppRoutes.vault)   # mode: gatekeeper
      VaultPage opens -> DetermineVaultEntryUseCase()
          pinSetupRequired      -> show "Digite seu PIN" (new) -> confirm -> [optional] offer biometrics
                                     -> on complete: markUnlocked() -> context.go(AppRoutes.home)     (Story 3)
          unlockBiometricFirst  -> auto-trigger local_auth prompt
              success                     -> markUnlocked() -> context.go(AppRoutes.home)   (Story 1)
              failed/cancelled/notAvailable -> show "Não foi possível reconhecer — digite seu PIN" + PIN keypad (Story 2;
                                                notAvailable routed identically — e.g. biometric lockout mid-session)
                  correct PIN      -> markUnlocked() -> context.go(AppRoutes.home)
                  incorrect PIN    -> clear digits, keep error banner, no lockout, retry allowed (Story 2, Edge Cases)
          unlockPinOnly          -> show PIN keypad directly, no biometric prompt attempted (Edge Cases: no hardware/not enrolled/OS-disabled)
      at any point: "usar e-mail e senha" -> context.push(AppRoutes.login)          (Story 4)

[VaultLifecycleObserver, AppLifecycleState.resumed, EvaluateBackgroundResumeUseCase() == true]
  rootNavigatorKey.push(VaultPage)   # mode: relock — pushed OVER whatever screen is current
      VaultPage opens -> DetermineVaultEntryUseCase()   # always unlockBiometricFirst or unlockPinOnly — PIN already exists
          success (biometric or PIN)  -> markUnlocked() -> Navigator.pop()   # reveals the preserved screen underneath, state untouched

[VaultLifecycleObserver, AppLifecycleState.resumed, EvaluateBackgroundResumeUseCase() == false]
  no-op — screen underneath was never covered, no re-authentication required   (FR-008)
```

**Fixed rule** (`EvaluateBackgroundResumeUseCase`, FR-009):

```dart
bool call({required DateTime? backgroundedAt, required DateTime resumedAt}) {
  if (backgroundedAt == null) return false;
  return resumedAt.difference(backgroundedAt) >= const Duration(minutes: 5);
}
```

A pure function of two timestamps and one constant — no settings read, no parameter — is itself
the mechanism by which FR-009's "fixed value, not configurable by the user" is enforced.

## Biometrics Preference

An account-level flag indicating whether Face ID/Touch ID is the user's chosen unlock method —
read locally at every vault entry to decide `unlockBiometricFirst` vs. `unlockPinOnly`, and mirrored
to the backend for durability/future display (RF09's Settings screen), per FR-013.

| Field | Type | Notes |
|---|---|---|
| `biometricPreferenceLocal` | `bool` | Written to `VaultSecureStorage` during first-time PIN setup (Story 3, scenario 4) if the user opts in; this is the value `DetermineVaultEntryUseCase` actually reads at runtime — never the backend's copy (research.md R6). Defaults to `false` until set. |
| `biometricEnabled` (remote) | `bool` | The backend's `users.biometric_enabled` field (requirements.md §8), read/written only through `PATCH /account/settings` → `account-settings-update`. This unit only ever **writes** it (fire-and-forget, FR-014); it never reads it back. |

**Write path** (`SaveBiometricsPreferenceUseCase`, FR-013/FR-014):

```
1. VaultRepository.setBiometricPreferenceLocally(enabled)        # synchronous, always succeeds (local write)
2. BiometricsPreferenceRepository.save(enabled)                  # await, discard Either<Failure, T> result
3. proceed to Home/Chat regardless of step 2's outcome            # Clarifications; Edge Cases
```

## Backend Failure (reused, not redefined)

`BiometricsPreferenceRepository.save()` is the only network call this unit makes; it returns
`Either<Failure, T>` using F000's existing `core/network/failure.dart` hierarchy unchanged (no new
`Failure` subtype — research.md R5). The three scenarios covered by this unit's own tests, toward
RNF09's 15-scenario total:

| Scenario | Expected `Failure` | `retryable` |
|---|---|---|
| Request exceeds the timeout | `NetworkTimeoutFailure` | yes |
| No connection at all | `NetworkOfflineFailure` | yes |
| Malformed response body | `ValidationFailure` | no |

None of these three block the PIN-setup-complete transition (R6) — they are observed only by this
unit's own `mocktail` tests of `BiometricsPreferenceRepositoryImpl`, never surfaced to the user.

## Biometric Capability (domain enum, no `local_auth` type crosses into `domain/`)

```
available        # canCheckBiometrics && isDeviceSupported && getAvailableBiometrics().isNotEmpty
noHardware        # isDeviceSupported == false
notEnrolled        # hardware present, nothing enrolled at the OS level
osDisabled        # was available in a previous session, no longer (Edge Cases: OS-level disable between sessions)
```

`LocalAuthBiometricDataSource` (data layer) is the only place that imports `local_auth`'s own
types (`LocalAuthentication`, `AuthenticationOptions`, `BiometricType`); `VaultRepositoryImpl` maps
its result into this enum before it ever reaches `domain/` or `presentation/` (RNF06).

## Presentation-only state (not persisted, not a domain entity)

- **`VaultMode`** (`gatekeeper | relock`) — which of the two entry points opened `VaultPage`;
  decides `go(home)` vs. `pop()` on success (data-model.md State transitions above). Passed as a
  constructor parameter, not stored anywhere.
- **First-entry PIN held during confirmation** — the first 4-digit value typed during first-time
  setup, kept only in `VaultBloc`'s in-memory state until the confirmation entry either matches
  (written to storage) or doesn't (discarded, user restarts entry — FR-012).
- **PIN-entry digit buffer / progress-dot count** — transient widget/bloc state for the keypad,
  reset to empty after every failed attempt (Edge Cases: "the entered digits are cleared").

## Design Tokens (`lib/core/design_tokens.dart`) — additions only

Every color, type style, spacing, and radius the vault screens use already exists from F000
(`colorPrimary`, `colorOnPrimary`, `colorError`, `colorSurfaceBg`, `textHeadlineMd`, `textBodyMd`,
`textTitleSm`, `spacing*`, `radius*`). Three values are new, per research.md R7 and the "Tela 0.1"
fidelity fix:

| Token | Value | Used by |
|---|---|---|
| `sizeKeypadTapTarget` | `72` (double, dp) | `pin_keypad.dart` — the circular tap target for each of the 12 keys (digits 0–9 + backspace + the empty 4th-row-left cell), per the prototype's "3×4 numeric keypad" with no explicit pixel size given. |
| `sizeBiometricIconContainer` | `96` (double, dp) | `vault_page.dart` — the round button around the fingerprint icon on the biometric-prompting screen, matching the prototype's `width:96px;height:96px;border-radius:999px` circle. |
| `sizeBiometricIcon` | `44` (double, dp) | `vault_page.dart` — the fingerprint glyph inside that circle, matching the prototype's `font-size:44px`. |

No other component-level token (spine colors, sync badge, bookmark states, etc.) is needed — those
belong to later units' own screens, same precedent F000's data-model.md already set.
