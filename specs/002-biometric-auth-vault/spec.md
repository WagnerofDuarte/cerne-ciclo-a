# Feature Specification: P-RF03 — Biometric authentication vault

**Feature Branch**: `002-biometric-auth-vault` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-11

**Status**: Draft

**Input**: User description: "P-RF03 — Biometric authentication vault: Protect access to the user's data with a Face ID / Touch ID / PIN barrier, validated on the device, per docs/input/requirements.md section 1 (RF03) and section 10 (parameters), matching the prototype states 'Tela 0.1 — Biometria', 'Tela 0.1b — PIN inicial', 'Tela 0.1c — PIN após falha'. No biometric endpoint exists on the backend; the biometrics preference is stored via PATCH /account/settings, and the session is renewed with POST /auth/refresh or POST /auth/login after passing the barrier. Depends on F000 (session, login). Do not implement features of later units, extension features, or change the backend."

## Clarifications

### Session 2026-10-11

- Q: During first-time PIN setup, if the user opts into Face ID/Touch ID and the `PATCH /account/settings` call to save `biometricEnabled` fails (timeout, no connection, etc.), should that block the user from reaching Home/Chat, or should the app proceed locally and let the write resolve/retry in the background? → A: Proceed locally and retry in the background — the local PIN and the on-device biometric toggle already work regardless of backend reachability; first-time setup does not block on this write succeeding, consistent with the local-first philosophy of FR-002 and FR-015 (resolved by technical judgment per user direction, applying Constitution Principle I).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unlocking the app with Face ID / Touch ID (Priority: P1)

A returning user who has already set up the vault opens the app (cold launch) or brings it back from the background after a long pause. Before anything from their journal or chat becomes visible, they are asked to confirm their identity with Face ID or Touch ID. On success, the app proceeds exactly as it would have without the vault.

**Why this priority**: This is the barrier itself — the entire reason the unit exists. Without it, no access protection exists at all.

**Independent Test**: Can be fully tested by launching the app on a device with biometrics enrolled and the vault already configured, confirming the biometric prompt appears before any data is visible, and confirming a successful scan proceeds into the app's normal session routing.

**Acceptance Scenarios**:

1. **Given** a device with a PIN already configured and Face ID/Touch ID enabled, **When** the app is cold-launched, **Then** the biometric prompt appears before any journal or chat content is shown, and a successful scan proceeds to the app's existing session routing (Home/Chat or login, depending on session validity).
2. **Given** the app was sent to the background and brought back after 5 minutes or more, **When** it resumes, **Then** the biometric prompt appears again before the previous screen becomes visible or interactive.
3. **Given** the app was sent to the background and brought back in under 5 minutes, **When** it resumes, **Then** no authentication is required and the user sees exactly the screen and state they left.

---

### User Story 2 - Biometric failure falls back to PIN (Priority: P1)

A user's fingerprint or face is not recognized (bad lighting, wet finger, a scan error). Rather than being stuck, they are immediately offered their PIN as an alternative and can still get into the app.

**Why this priority**: Explicit acceptance criterion in the requirement — a failed biometric read must never lock the user out, since biometric sensors fail routinely under normal conditions.

**Independent Test**: Can be fully tested by forcing a biometric failure (denied, cancelled, or not recognized) and confirming the PIN screen appears with an error message, then confirming a correct PIN still unlocks the app.

**Acceptance Scenarios**:

1. **Given** the biometric prompt is shown, **When** the scan fails or is not recognized, **Then** the PIN entry screen appears showing the error message "Não foi possível reconhecer — digite seu PIN", without any other interruption.
2. **Given** the PIN screen shown after a biometric failure, **When** the user enters the correct 4-digit PIN, **Then** the app unlocks and proceeds normally.
3. **Given** the PIN screen shown after a biometric failure, **When** the user enters an incorrect PIN, **Then** the error state remains, the entered digits are cleared, and the user can try again with no limit that locks them out of the app entirely.

---

### User Story 3 - Setting up the PIN for the first time (Priority: P2)

Right after a user's very first successful login or sign-up on a device, before they can use the app, they are asked to choose a 4-digit PIN and confirm it. This PIN becomes the fallback that always works, whether or not biometrics are set up.

**Why this priority**: Every later unlock (Story 1 and 2) depends on a PIN already existing; without this step the vault has nothing to fall back to.

**Independent Test**: Can be fully tested by signing up or logging in for the first time on a device with no PIN configured, confirming the create-PIN screen appears before Home/Chat, and confirming a matching confirmation proceeds while a mismatched one does not.

**Acceptance Scenarios**:

1. **Given** a user has just completed their first successful login or sign-up on a device with no PIN configured yet, **When** that happens, **Then** they are asked to enter a new 4-digit PIN and then re-enter it to confirm, before reaching Home/Chat.
2. **Given** the PIN confirmation step, **When** the re-entered PIN matches the first entry, **Then** the PIN is saved on the device and the user proceeds to Home/Chat.
3. **Given** the PIN confirmation step, **When** the re-entered PIN does not match, **Then** the user sees a clear message and is returned to entering a new PIN, without the mismatched PIN being saved.
4. **Given** the device supports Face ID or Touch ID, **When** PIN setup completes, **Then** the user is offered the option to also enable biometric unlock, and their choice is saved as their biometrics preference.

---

### User Story 4 - Recovering access via full login (Priority: P3)

A user who cannot pass biometrics or does not remember their PIN taps a visible link on the vault screen and is taken to the regular email/password login, regaining access that way instead of being stuck.

**Why this priority**: A safety valve for the barrier itself; it depends on the vault screen (Story 1) existing, and reuses login machinery that F000 already built, so it carries the least new risk of the four stories.

**Independent Test**: Can be fully tested by tapping "usar e-mail e senha" from the vault screen and confirming it leads to the existing login screen, where submitting valid credentials proceeds into the app.

**Acceptance Scenarios**:

1. **Given** the vault screen (biometric or PIN) is shown, **When** the user taps "usar e-mail e senha", **Then** they are taken to the existing login screen.
2. **Given** a user who reached login this way, **When** they submit valid credentials, **Then** they proceed into the app the same way a first-time login would.

---

### Edge Cases

- A device has no biometric hardware, or no fingerprint/face enrolled at the OS level: the vault shows the PIN screen directly as the only method, without attempting or showing a fingerprint prompt first.
- The app process is killed by the operating system while backgrounded (not merely suspended): the next launch is treated as a cold launch and always shows the vault, regardless of how little time has passed.
- A user disables biometrics at the OS level (outside the app) between sessions: the next vault appearance falls back to PIN entry directly, with no error shown for the missing biometric capability.
- The background timer sits exactly at the 5-minute boundary: fewer than 5 minutes elapsed never re-prompts; 5 minutes or more always does.
- The app is killed mid-way through first-time PIN setup (Story 3) before confirmation completes: relaunching resumes the PIN setup flow rather than leaving the user in an unusable, PIN-less state.
- Repeated incorrect PIN entries: never produce a hard lockout of the app; the user can always retry or fall back to "usar e-mail e senha".
- The `PATCH /account/settings` call that saves the biometrics preference during first-time setup fails (timeout, no connection, malformed response): PIN setup still completes and the user still reaches Home/Chat; the write is not retried synchronously as part of the setup flow.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST require the user to pass a local authentication check — Face ID, Touch ID, or PIN — before showing any of the user's journal, chat, or account data, on every cold launch and on every resume from the background, whenever a PIN has already been configured on the device.
- **FR-002**: The system MUST perform this authentication entirely on-device; no biometric data and no PIN value may be sent to, or validated by, the backend.
- **FR-003**: When biometrics are enabled and available on the device, the system MUST attempt Face ID/Touch ID first; when biometrics are unavailable (no hardware, nothing enrolled, or disabled), the system MUST present PIN entry as the method shown, without attempting a biometric prompt.
- **FR-004**: When a biometric attempt fails or is not recognized, the system MUST immediately offer PIN entry as an alternative, together with the error message "Não foi possível reconhecer — digite seu PIN", and MUST NOT lock the user out of attempting authentication again.
- **FR-005**: The PIN entry MUST use a 4-digit code entered on a numeric keypad with backspace, showing progress across 4 dots as digits are entered.
- **FR-006**: The vault screen MUST offer a visible link ("usar e-mail e senha") that leads to the existing email/password login screen, for cases where neither biometrics nor the PIN can be used.
- **FR-007**: When the app is sent to the background and brought back after 5 minutes or more have elapsed, the system MUST require the authentication barrier again before the previously visible screen becomes visible or interactive.
- **FR-008**: When the app is sent to the background and brought back in under 5 minutes, the system MUST NOT require re-authentication, and MUST resume exactly the screen and state the user left.
- **FR-009**: The 5-minute background timeout MUST be a fixed value with no user-facing setting to change it.
- **FR-010**: When the barrier is triggered after a background timeout, the system MUST preserve the state of the screen underneath it and restore that exact state once authentication succeeds.
- **FR-011**: The first time a user completes a successful login or sign-up on a device with no PIN configured, the system MUST require the user to create a 4-digit PIN and re-enter it to confirm, before any further screen is reachable.
- **FR-012**: If the confirmation PIN does not match the first entry, the system MUST reject it with a clear message and let the user set a new PIN, without saving the mismatched value.
- **FR-013**: On a device where biometrics are available, the system MUST let the user optionally enable Face ID/Touch ID unlock as part of first-time PIN setup, and MUST persist that choice as the account's biometrics preference through the backend.
- **FR-014**: Persisting the biometrics preference MUST reuse the single typed-failure network call path already established by the foundation unit, not a separate or ad hoc HTTP call. If that call fails (timeout, no connection, malformed response), the failure MUST NOT block PIN setup from completing or the user from reaching Home/Chat — the local PIN and the on-device biometric toggle already govern unlocking regardless of backend reachability, and the preference write is left to resolve or retry through the existing failure-handling path.
- **FR-015**: Passing the local barrier MUST NOT by itself constitute backend authentication; the app MUST continue to rely on the session machinery already established (silent renewal, or a full login if the session can no longer be renewed).
- **FR-016**: This unit MUST NOT implement the functional behavior of any later-delivered requirement (RF01, RF02, RF04 through RF10), including building the Settings screen; any biometrics control beyond first-time setup is out of scope.
- **FR-017**: This unit MUST NOT implement any extension feature (manual tags, action plans, persona selection).
- **FR-018**: This unit MUST NOT modify the backend, its contract, or its configuration in any way.

### Key Entities

- **Device PIN**: A 4-digit secret stored only on the device, created once during first-time setup and checked locally on every subsequent unlock attempt; never transmitted to or validated by the backend.
- **Vault Lock State**: Whether the current app session is currently locked or unlocked, and the timestamp of the last time it was unlocked — used to decide whether a resume from the background falls under or over the 5-minute threshold.
- **Biometrics Preference**: An account-level flag (`biometricEnabled`) indicating whether Face ID/Touch ID is the user's enrolled unlock method; read and written through the backend's account-settings endpoint, but never the thing that performs the actual biometric check.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of cold launches and background resumes of 5 minutes or more show the authentication barrier before any user data becomes visible.
- **SC-002**: 100% of resumes from the background under 5 minutes skip authentication and restore the exact prior screen state.
- **SC-003**: A user whose biometric attempt fails can always reach their data via PIN in the same session — 0 cases where a biometric failure alone ends in the user being unable to proceed.
- **SC-004**: A new user completes first-time PIN setup (create + confirm) successfully in a single guided flow, with no path that leaves the device without a usable PIN.
- **SC-005**: Across a full lock/unlock cycle triggered by a background timeout, the screen state underneath (scroll position, visible content) is unchanged in every observed case.

## Assumptions

- The prototype extract shows no screen dedicated to first-time PIN creation, distinct from "PIN inicial" (first entry) and "PIN após falha" (entry after a failure). This unit reuses the same 4-digit keypad component for a create-then-confirm flow the first time a device has no PIN, since no separate enrollment screen is documented.
- A dedicated toggle to change the biometrics preference later (outside of first-time setup) belongs to the Settings screen built by the RF09 unit; this unit implements the account-settings read/write path for `biometricEnabled` but not that screen's UI.
- The vault only engages once a PIN has been configured on the device. A device with no PIN yet (first-ever app use before any account exists) is unaffected by this unit and continues straight to F000's existing login/sign-up flow; PIN setup is triggered immediately after that flow's first success (Story 3).
- "Usar e-mail e senha" reuses F000's existing login screen unmodified; this unit adds only the navigation link to reach it from the vault.
- The "Sessão expirada" overlay built by F000 for a genuinely expired backend session is unaffected by this unit and continues to route to the login screen as F000 built it; routing it back through the vault instead is left to the unit that owns live in-session behavior (RF07), consistent with not implementing later units' functionality.
- No maximum-attempt lockout is implemented for PIN entry; repeated incorrect attempts show an inline error and allow retrying indefinitely, with "usar e-mail e senha" always available as a fallback.
- Device biometric availability (hardware present, something enrolled, not disabled) is read from the platform's own biometrics API; this unit does not reimplement that detection.
- The Face ID/Touch ID prompt is triggered automatically as soon as the vault screen with biometrics enabled appears (standard platform behavior), not only after a tap; the fingerprint circle and "Toque para desbloquear" act as a manual retry affordance for when the OS prompt was dismissed or cancelled, consistent with User Story 1's requirement that the prompt appear before any data is shown on cold launch.
- When a user disables biometrics at the OS level between sessions (see Edge Cases), this unit does not call the backend to flip `biometricEnabled` to false; the account-level preference is only ever written during first-time setup (FR-013) in this unit, and keeping it in sync with later out-of-band OS changes is left to the Settings screen built by the RF09 unit, consistent with the existing assumption that a dedicated toggle belongs there.
