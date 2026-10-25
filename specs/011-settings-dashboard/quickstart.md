# Quickstart: P-RF09 — Temporal summaries / dashboard

Manual/exploratory validation guide — proves the feature end-to-end against a running backend. Automated
coverage (unit/bloc/widget) is tasks.md's job; this is the human-runnable complement, mirroring every prior
unit's quickstart shape (seeded accounts + a numbered walk-through per acceptance scenario).

## Prerequisites

- `.env` with `FUNCTIONS_BASE_URL`/`SUPABASE_ANON_KEY` pointed at a reachable backend (Constitution Principle
  III) — same as every other unit's quickstart.
- `fvm flutter run` on an iOS simulator or device.
- At least these seeded test accounts (reuse whatever seeding mechanism prior units' quickstarts already
  established for `docs/input/backend/fixtures/`, extended with the counts this unit specifically needs):

| Account | Entries | Exercises |
|---|---|---|
| A | 0 | FR-003 (zero-entry dashboard state) |
| B | 1 | FR-004 (single-bar state) |
| C | 5 (all within the last 3 days) | FR-005/spec.md Clarification 1 (partial multi-bar chart, same-day-range degenerate bucketing) |
| D | 32, spread across several months | FR-005 (fully-populated 10-bar chart), acceptance scenario 3 |
| E | Any account with a configured PIN (post-RF03 first-time setup), biometrics available on the test device | User Story 3's biometric toggle |

## Story 1 — Dashboard

1. Log into **Account A**, open Settings (drawer → "Configurações"). Expect: light-gray placeholder chart
   icon, "Comece a registrar para ver sua evolução aqui," no narrative area at all.
2. Log into **Account B**. Expect: one small bar, "Ainda é cedo pra ver um padrão — volte em alguns dias.",
   no narrative area.
3. Log into **Account C**. Expect: the multi-bar chart with only some of the 10 bars populated (not the
   single-bar state), and a narrative paragraph once it resolves — confirms spec.md Clarification 1.
4. Log into **Account D**. Expect: all (or nearly all) 10 bars populated, ochre, plus a narrative paragraph.
5. From Account D, create one new entry on Home/Chat, return to Settings. Expect: the newly-created entry is
   reflected in the chart on this visit (FR-008) — not the pre-entry snapshot.
6. With the backend reachable, block only `dashboard-narrative-get` (e.g. a proxy rule, or temporarily
   renaming the function if testing against a local stack) while leaving `dashboard-aggregate-get` working, on
   Account D. Expect: chart renders correctly; narrative area shows "narrativa indisponível" wording, not a
   blank area and not Account A's empty-history copy (FR-006).
7. Block `dashboard-aggregate-get` itself (airplane mode, or a backend 500) on Account D. Expect: a distinct,
   retryable chart-area error state, no narrative requested, "Tentar novamente" (or equivalent) recovers once
   connectivity returns (FR-007).

## Story 2 — Account deletion

1. On any seeded account, tap "Apagar conta." Expect: centered dialog, red title "Apagar sua conta?",
   permanent/irreversible explanatory text, red "Apagar tudo," outline "Cancelar."
2. Tap "Cancelar." Expect: dialog closes; Settings unaffected; confirm via backend logs/dashboard that no
   `DELETE /account` request was sent.
3. Re-open the dialog, tap "Apagar tudo" with the backend reachable. Expect: lands at the vault/PIN screen (if
   this device has one configured) or login (if not); attempting to log back in with the same credentials
   fails (account gone).
4. Repeat with the backend unreachable (airplane mode). Expect: dialog stays open, shows a retryable error,
   account remains fully usable afterward (log back in to confirm).
5. Double-tap "Apagar tudo" quickly (airplane mode, so the first request hangs) — confirm via logs that only
   one `DELETE /account` request was ever sent (FR-022).

## Story 3 — Profile and sign-out

1. Open Settings. Expect: 52px initials avatar, current display name, email (read-only, no pencil/edit
   affordance next to it), pencil icon next to the name.
2. Tap the pencil. Expect: name becomes an editable field, pencil becomes a check, email unaffected.
3. Clear the field entirely and tap the check. Expect: inline validation error, field stays in edit mode, no
   network request (FR-011) — confirm via logs.
4. Type a valid new name, tap the check with the backend reachable. Expect: field returns to display mode
   with the new name; **fully restart the app** and reopen Settings — the new name is still shown (SC-005).
5. Repeat step 4 with the backend unreachable. Expect: field stays in edit mode, typed text intact, retryable
   error shown; restoring connectivity and retrying (without re-typing) succeeds.
6. On **Account E** (biometrics-capable device), flip the Face ID/Touch ID toggle. Expect: saves immediately
   (RNF01, no spinner needed for the optimistic flip); background the app and relaunch — the vault screen's
   own biometric-first behavior now matches the new toggle value.
7. Flip the toggle again with the backend unreachable. Expect: toggle visually reverts to its prior value, a
   retryable error is shown, and the vault's own unlock behavior did **not** change (still gated on the
   last-confirmed value).
8. On a device/simulator with no enrolled biometrics, open Settings. Expect: no Face ID/Touch ID row at all
   (not a disabled one).
9. Tap "Sair." Expect: lands at vault/login exactly as in Story 2 step 3's destination; confirm the app
   requires full re-authentication afterward (no residual session) — e.g. relaunching the app does not land
   directly on Home.

## Edge cases

- While Settings is loading (any state above), trigger an existing session expiry (whatever mechanism prior
  units' own quickstarts use to force `AUTH_EXPIRED` — e.g. a manually-expired/revoked token). Expect: the
  app-wide "Sessão expirada" dialog appears over Settings (not a crash); after re-authenticating, Settings'
  dashboard/profile/toggle reload fresh, and the one thing you had in progress (open name edit, if any) still
  shows the typed, unsaved text (research.md R15).
- Cross-check `test/architecture/domain_purity_test.dart` and `no_bloc_imports_bloc_test.dart` still pass after
  adding `features/settings/` — both are structural, not scenario-based, so this is a `flutter test` run, not
  a manual step.
