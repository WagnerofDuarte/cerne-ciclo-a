# Quickstart: P-RF03 — Biometric authentication vault

How to validate this unit end-to-end once implemented, mapped to spec.md's four user stories. This
is a run guide, not an implementation spec — interfaces are in `contracts/`, state/entities in
`data-model.md`.

## Prerequisites

- F000 already implemented and passing (`specs/001-foundation/`) — RF03 builds directly on its
  `SessionBloc`/`AuthBloc`/`ApiClient`/`SecureTokenStorage`/routing.
- `fvm flutter pub get` after `local_auth` and `crypto` are added to `pubspec.yaml`.
- `ios/Runner/Info.plist` contains `NSFaceIDUsageDescription` (research.md R1) — without it, any
  call into `local_auth` on a real device or the Simulator crashes immediately, not just returns
  "unavailable."
- A `.env` with valid `FUNCTIONS_BASE_URL`/`SUPABASE_ANON_KEY` — only exercised by the one
  `account-settings-update` call (Story 3's optional biometrics opt-in); everything else in this
  unit works with no backend reachable at all (FR-002).

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint (always_use_package_imports)
fvm flutter test --coverage
# RNF07 gate — same lcov filter F000 uses, now including lib/features/vault/domain
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html   # inspect % manually, or script a threshold check
```

Key domain tests this unit's coverage depends on (contracts/vault-repository.md,
contracts/vault-lifecycle.md):
- `EvaluateBackgroundResumeUseCase`: exact-boundary cases (4:59 → false, 5:00 → true), `null`
  `backgroundedAt` → false.
- `DetermineVaultEntryUseCase`: all four input combinations (no PIN; PIN + biometric available +
  preferred; PIN + biometric available + not preferred; PIN + biometric unavailable).
- `VerifyPinUseCase`/`SavePinUseCase` against a fake `VaultRepository`.
- `BiometricsPreferenceRepositoryImpl`: the 3 failure scenarios in
  contracts/biometrics-preference-repository.md.

## Manual verification (device/Simulator — `local_auth` has no platform channel under `flutter_test`)

The iOS Simulator supports Face ID without real hardware: **Features → Face ID → Enrolled**, then
**Features → Face ID → Matching Face** / **Non-matching Face** to simulate a pass/fail scan on
demand.

### Story 1 — Unlock with Face ID/Touch ID (P1)

1. Enroll Face ID in the Simulator; complete sign-up once (Story 3 flow below) with the biometric
   opt-in accepted.
2. Force-quit and relaunch the app (cold launch).
3. **Expect**: Splash → vault screen with the fingerprint prompt, before any Home/Chat content
   renders. **Features → Face ID → Matching Face** → app proceeds straight to Home/Chat.
4. Background the app (Simulator: Cmd+Shift+H or Device → Home), wait 5+ minutes (or temporarily
   lower the constant in a local-only debug build to verify the mechanism faster, then revert),
   bring it back. **Expect**: vault screen re-appears over Home/Chat; matching Face ID again
   reveals Home/Chat exactly as left (scroll position, any in-progress state).
5. Repeat the same background/resume but under 5 minutes. **Expect**: no vault screen, Home/Chat
   is immediately interactive.

### Story 2 — Biometric failure falls back to PIN (P1)

1. From the vault screen's fingerprint prompt, **Features → Face ID → Non-matching Face**.
2. **Expect**: PIN keypad appears immediately with "Não foi possível reconhecer — digite seu PIN".
3. Enter the correct 4-digit PIN. **Expect**: unlocks normally.
4. Repeat; enter an incorrect PIN. **Expect**: digits clear, error state remains, no limit —
   retry with the correct PIN still works afterward.

### Story 3 — First-time PIN setup (P2)

1. Delete the app (or clear its Keychain data) to guarantee no PIN/session exists; launch fresh.
2. Sign up with a new email. **Expect**: immediately after signup succeeds, the create-PIN screen
   appears (not Home/Chat) — 4 progress dots, 3×4 keypad.
3. Enter 4 digits; **expect** the confirmation step. Enter a *different* 4 digits. **Expect**: clear
   mismatch message, returned to entering a new PIN, nothing saved yet.
4. Enter and confirm matching PINs. If the Simulator has Face ID enrolled, **expect** a biometrics
   opt-in prompt as part of this same flow; accept it.
5. **Expect**: proceeds to Home/Chat. Confirm in the backend (or a debug log of the request) that
   `PATCH account-settings-update` was called with `{"biometricEnabled": true}`.
6. Force-quit the Simulator mid-way through step 3 (after the first PIN entry, before
   confirmation) and relaunch. **Expect**: the PIN setup flow resumes (not a stuck/PIN-less state,
   not routed to Home/Chat).

### Story 4 — Recover via full login (P3)

1. From the vault screen (biometric or PIN state), tap "usar e-mail e senha".
2. **Expect**: the existing F000 login/sign-up screen opens.
3. Submit valid credentials. **Expect**: proceeds into the app the same way a fresh login would
   (i.e., through the vault gate again if a PIN is already configured on this device — see
   data-model.md's gatekeeper transition for `LoginSignupPage`'s success branch).

### Edge cases worth exercising manually at least once

- Simulator **Features → Face ID → Enrolled** turned back off between launches → vault should show
  the PIN keypad directly on the next open, no fingerprint prompt attempted, no error about missing
  hardware.
- Offline device (Simulator network link conditioner, or airplane mode) during step 4–5 of Story
  3 → PIN setup still completes and reaches Home/Chat; only the backend write silently fails.
