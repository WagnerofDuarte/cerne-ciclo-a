# Research: P-RF03 — Biometric authentication vault

F000's research.md explicitly left "biometrics" open for "the units that need them (RF03, RF09)."
This file resolves that, plus every other free choice and silent spot this unit's spec surfaces.

## R1 — Biometrics package

- **Decision**: `local_auth` (the official `flutter.dev`-maintained plugin), called with
  `authenticate(biometricOnly: true)`.
- **Rationale**: FR-004 requires that a failed/unavailable biometric attempt fall through to the
  app's **own** 4-digit PIN, never to the iOS device passcode. `local_auth`'s `biometricOnly: true`
  option is honored on iOS (it pins the underlying `LAPolicy` to
  `LAPolicyDeviceOwnerAuthenticationWithBiometrics`, which has no device-passcode fallback built
  in) — exactly the primitive FR-004 needs. `local_auth` also exposes `canCheckBiometrics` and
  `isDeviceSupported()` ahead of calling `authenticate`, which FR-003 and the Edge Cases ("no
  hardware," "nothing enrolled," "disabled at the OS level") need to distinguish from an in-progress
  failed attempt. It is the only Flutter-ecosystem plugin maintained by the Flutter team itself for
  this exact purpose, consistent with picking boring, well-supported dependencies for a stack the
  constitution otherwise keeps deliberately small.
- **Alternatives considered**: Rolling a native iOS `LAContext` call through a hand-written
  platform channel — rejected, `local_auth` already wraps exactly this with no extra capability
  gained from going lower-level, for meaningfully more code to own and test. Third-party biometrics
  wrappers (e.g. ones that bundle PIN-entry UI too) — rejected, this unit already owns PIN entry per
  FR-005/the prototype's exact keypad spec, and a bundled UI would fight Principle IV (design-token
  fidelity) rather than help.
- **Native project note**: `local_auth`'s iOS backend requires `NSFaceIDUsageDescription` in
  `ios/Runner/Info.plist` (a one-line string the App Store requires before Face ID can even be
  attempted) — the only native project file this unit touches, and a hard requirement of the
  package rather than a product decision. No Android work exists in this project (iOS-only,
  Principle II).

## R2 — PIN storage

- **Decision**: Store `sha256(pin)` (hex string) via a new `VaultSecureStorage` key, never the raw
  4-digit value. Verification re-hashes the entered PIN and compares digests.
- **Rationale**: `flutter_secure_storage` is already Keychain-backed (R5 of F000's research.md),
  so storing the raw PIN would not be *readable* in plaintext at rest either — but hashing is the
  standard defense-in-depth for any credential-shaped value regardless of the storage layer
  underneath, and it is a one-function addition (`crypto`'s `sha256`) with no behavioral
  downside: the PIN is never displayed back to the user, so there is no legitimate need to ever
  recover the raw value, only to compare it. This mirrors how the backend itself never stores or
  sees passwords in the clear.
- **Alternatives considered**: Storing the raw PIN string — rejected as an avoidable weakening for
  zero functional gain. A salted hash (per-install random salt, also stored) — rejected as
  over-engineering: the threat a salt defends against is an attacker who has compromised *many*
  users' hash stores at once and wants to precompute one rainbow table across all of them; here,
  each hash lives alone inside that one device's own encrypted Keychain entry for that one user, so
  a salt adds code and a second stored value without changing what an attacker who already has
  Keychain access could do.

## R3 — Where the 5-minute relock timer lives

- **Decision**: One root-level `StatefulWidget` (`VaultLifecycleObserver`), installed once in
  `main.dart`'s `CerneApp.builder` (the same spot F000 installs the session-expired
  `BlocListener`), implementing `WidgetsBindingObserver`. On `AppLifecycleState.paused` it calls
  into the long-lived `VaultRepository` singleton to record "now"; on `.resumed` it asks a pure
  domain usecase (`EvaluateBackgroundResumeUseCase`) whether that gap was ≥ 5 minutes, and if so
  pushes `VaultPage(mode: relock)` via the existing `rootNavigatorKey` — the same root navigator
  `session_expired_overlay.dart` already pushes onto.
- **Rationale**: FR-007/FR-008/FR-010 and User Story 1's background-resume scenarios are a
  cross-cutting concern that has nothing to do with *which* screen happens to be on top — exactly
  the shape F000's own `SessionBloc` + root `BlocListener` pattern was built for (research.md R3
  there). Reusing `rootNavigatorKey` and plain `push` (never `go`/replace) is what makes "the screen
  underneath keeps its exact state" (FR-010) true by construction, not by a second bespoke
  mechanism — the same guarantee `session_expired_overlay.dart` already relies on for its own
  overlay.
- **Why not persist the last-unlock timestamp to disk**: the only case that would matter for is the
  OS killing the process while backgrounded — but that case is *already* handled for free: a killed
  process means the next launch is a cold launch, which always re-enters `SplashPage` → the
  `AppRoutes.vault` gatekeeper path regardless of elapsed time (Edge Cases: "the next launch is
  treated as a cold launch and always shows the vault"). An in-memory timestamp on a singleton
  repository is therefore sufficient; persisting it would add a disk write on every background
  transition for a case that can't be reached.
- **Alternatives considered**: A second root-level `Bloc` dedicated to lock state — rejected as an
  unnecessary extra moving part; the logic needed (record a timestamp, compare it, decide whether
  to push one specific, already-existing route) does not need its own event/state machine distinct
  from the domain usecase plus a thin observer widget. A `Timer.periodic` ticking down from 5
  minutes while foregrounded — rejected: FR-007/FR-008 only care about elapsed *background* time,
  not foreground idle time (that is RF08's unrelated 2-minute inactivity trigger), so a running
  foreground timer would be solving a problem this requirement doesn't have.

## R4 — The single-screen vault (gatekeeper vs. relock, setup vs. unlock)

- **Decision**: One route (`AppRoutes.vault`), one page (`VaultPage`), one screen-scoped
  `VaultBloc`, branching internally on two independent axes: (a) **mode** — `gatekeeper` (reached
  from `SplashPage` or `LoginSignupPage`, resolves by going to `AppRoutes.home` on success) vs.
  `relock` (reached from `VaultLifecycleObserver`, resolves by popping back to the preserved screen
  underneath); (b) **entry decision** — `pinSetupRequired` vs. `locked(biometricFirst | pinOnly)`,
  computed once by `DetermineVaultEntryUseCase` when the page opens.
- **Rationale**: prototype-extract.md's own implementation note #1 flags that "32 states" collapse
  into fewer real screens with internal state, naming this exact family (Biometria / PIN inicial /
  PIN após falha) as a candidate. The spec's own Assumptions go further and fold first-time PIN
  creation into the same keypad component rather than inventing a fourth undocumented screen. A
  `relock` entry can never need the `pinSetupRequired` branch (a relock is only ever triggered after
  the app was already unlocked once this process, which requires a PIN to already exist) — so the
  same `DetermineVaultEntryUseCase` naturally degrades to just the unlock branch for that mode
  without needing a second decision function.
- **Alternatives considered**: Four separate routes (one per prototype state name) — rejected,
  directly contradicts the prototype's own implementation note and would duplicate the keypad
  widget and its 350 ms-after-4th-digit transition behavior four times instead of once.

## R5 — RNF09 scoping for this unit's local-only operations

- **Decision**: `Either<Failure, T>` is used only where this unit actually talks to the network —
  `BiometricsPreferenceRepository`. `VaultRepository` (PIN verification, biometric hardware
  queries, the in-memory relock timestamp) returns plain `bool`/`DateTime?`/domain-enum values, not
  `Either<Failure, T>`.
- **Rationale**: RNF09's `Failure` hierarchy (`core/network/failure.dart`) is explicitly the
  backend's own closed 13-code taxonomy (F000 research.md R6) — `AUTH_EXPIRED`,
  `NETWORK_TIMEOUT`, and so on are all things *a server response* can say. A missing fingerprint
  sensor or a wrong PIN digest is not a server outcome and has no corresponding code; forcing it
  through `Either<Failure, T>` would mean either inventing fake codes for purely local conditions
  (polluting a taxonomy the spec calls "closed") or always returning a code that doesn't really fit.
  Constitution Principle I directs implementers to make the reasonable call where the inputs are
  silent, and RNF09's own wording ("every repository") is about the network-error-handling pattern
  the requirement is named for — not a blanket ban on any repository ever returning something else
  for a condition that isn't a network failure.
- **Alternatives considered**: Modeling PIN/biometric outcomes as `Either<Failure, T>` with new
  `Failure` subtypes (e.g. `BiometricUnavailableFailure`) — rejected: it would grow the "closed"
  taxonomy with codes the backend's `error-taxonomy.md` doesn't define and that no later unit's
  network code would ever need to pattern-match on, diluting the one place (`failure.dart`) F000
  deliberately kept scoped to the backend's own 13 codes (F000 research.md R6).

## R6 — `biometricEnabled` write semantics (building on the Clarifications session)

- **Decision**: `SaveBiometricsPreferenceUseCase` writes the local mirror flag
  (`VaultRepository.setBiometricPreferenceLocally`) synchronously, then fires the
  `BiometricsPreferenceRepository.save()` network call and discards its `Either` result — no retry
  loop, no error banner, no blocking of the PIN-setup-complete transition to Home/Chat.
- **Rationale**: This is the literal mechanics of the Clarifications session's resolution
  ("proceed locally and retry in the background... first-time setup does not block on this write
  succeeding") plus the matching Edge Case ("the write is not retried synchronously as part of the
  setup flow"). The *local* mirror is what every later vault unlock actually reads to decide
  biometric-first vs. PIN-only (FR-003) — the backend's copy of `biometricEnabled` is a durable
  record for whichever later unit (RF09's Settings screen) needs to display or change it, not the
  value this unit's own unlock logic depends on at runtime.
- **What "retry through the existing failure-handling path" means here**: concretely, nothing new
  is built for it in this unit — the failed write simply isn't retried by RF03 at all. If the user
  later opens Settings (RF09) and that screen reads the account record, any mismatch between the
  local mirror and the stale backend value is that unit's reconciliation problem, not this one's;
  RF03 does not introduce a background sync queue, which would be speculative machinery for a case
  the spec explicitly says not to block on.
- **Alternatives considered**: A `WorkManager`/background-retry-queue style mechanism — rejected as
  out of proportion to a single boolean field and explicitly not what the Clarifications answer
  asked for.

## R7 — New design tokens this unit needs

- **Decision**: Add exactly one new token, `sizeKeypadTapTarget` (72 dp — a 4×-grid value,
  consistent with the existing `spacing*` scale, sized for a comfortable thumb target per the
  prototype's 390×844 frame), to `design_tokens.dart`. Everything else the vault screens need
  (error-band red, primary buttons, body/title text styles, spacing, radii) already exists from
  F000.
- **Rationale**: prototype-extract.md §3 does not give the PIN keypad an explicit pixel size (only
  "3×4 numeric keypad with backspace"), so this is the one silent spot Principle I's "reasonable
  technical decision" applies to visually — and per Principle IV it must still be a named constant
  in `design_tokens.dart`, not an inline literal in `pin_keypad.dart`.
- **Icons**: continuing F000's already-established precedent of using Flutter's built-in
  `Icons.*` (Material) rather than the prototype's specified Phosphor set (F000 used `Icons.send`,
  `Icons.lock` — see `home_chat_shell_page.dart`, `session_expired_overlay.dart`) — this unit uses
  `Icons.fingerprint` (Biometria's fingerprint circle), `Icons.backspace` (keypad backspace), and
  `Icons.lock_outline` (PIN screen header), introducing no new icon package.
