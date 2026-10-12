# Quickstart: validating P-F000 — Foundation

Prerequisites, run commands, and expected outcomes for proving this unit's 5 user stories end to
end. Interface details (headers, URLs, failure types) are in `contracts/`; entity/state details
are in `data-model.md`.

## Prerequisites

- `fvm use 3.47.5` run once at the repo root (installs/links the pinned SDK — see research.md R1).
- `.env` present at the repo root with `FUNCTIONS_BASE_URL` and `SUPABASE_ANON_KEY` (already exists
  in this repo; never commit it).
- `fvm flutter pub get`.
- A real or simulated iOS device/runner (`fvm flutter devices`), since the target platform is iOS.

## Setup

```bash
fvm flutter pub get
fvm flutter run -d <ios-device-or-simulator-id>
```

## Automated checks

```bash
fvm flutter analyze                                   # 0 issues, incl. no flutter imports under domain/ (RNF06)
fvm flutter test --coverage                            # unit + bloc tests (mocktail, bloc_test)
lcov --extract coverage/lcov.info 'lib/*/domain/*' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain_html    # inspect: >= 80% (RNF07)
```

## Manual / integration validation scenarios

Each maps directly to a spec.md Acceptance Scenario.

1. **Login (User Story 1)**
   - Launch with no stored session → login screen.
   - Enter a valid, existing email/password → lands on Home/Chat.
   - Enter a wrong password → inline, non-crashing error, stays on login screen, can retry.
   - Turn off network, submit → retryable connection-error message, no hang/crash.

2. **Sign-up (User Story 2)**
   - From the login screen, tap the toggle link → title/CTA switch to "Criar conta" (same screen,
     no navigation).
   - Submit a brand-new email/password → account created, lands directly on Home/Chat.
   - Submit an already-registered email → clear error, form stays editable, no crash.

3. **Launch routing (User Story 3)** — exercise all three stored-session conditions:
   - Valid session on device → splash, then straight to Home/Chat, no credentials re-entered.
   - No stored session (fresh install, or after a manual token wipe) → splash, then login screen.
   - Expired-but-refreshable session (manually expire the stored `accessToken`, keep a valid
     `refreshToken`) → splash, silent `auth-refresh`, lands on Home/Chat without any prompt.

4. **Base navigation (User Story 4)** — confirms SC-004 (≤2 taps each way)
   - From Home/Chat, tap ☰ (1 tap) → drawer opens, see Meus Registros, Configurações.
   - Tap Meus Registros (2 taps total) → visible; tap ☰ then Home/Chat (≤2 taps) to return →
     chat shell state (e.g., scroll position) unchanged.
   - Repeat for Configurações, confirming ≤2 taps each direction.
   - Opening the drawer itself visibly scrims the current screen without resetting it.

5. **Session-expired overlay (User Story 5)**
   - Get to a known state on a screen (e.g., scroll Home/Chat partway).
   - Force a session-expired response (e.g., revoke/expire the access token server-side, or stub it
     in a debug build) while that screen is active.
   - Confirm the "Sessão expirada" card appears over a light scrim, screen content still visible
     and unchanged underneath.
   - Tap "Entrar novamente", re-authenticate → overlay dismissed, screen state (scroll position)
     restored exactly.
   - Repeat the forced expiry while the overlay is still visible (before dismissing) → overlay
     persists/reappears rather than letting the user proceed.

## Expected outcome

All 5 scenarios above pass; `flutter analyze` and `flutter test --coverage` are clean; the
`lib/**/domain/**` coverage report meets RNF07; no screen's rendered output uses a color, font, or
spacing value traceable to anything other than `lib/core/design_tokens.dart` (spot-check via code
review, since this is not yet an automated lint in this unit).
