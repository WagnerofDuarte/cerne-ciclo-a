# Quickstart: P-RF08 — Proactive insights (mechanism)

Manual + automated validation for this unit. See data-model.md/contracts/ for the exact shapes being
exercised; this file only sequences how to prove each acceptance scenario end-to-end.

## Prerequisites

- `fvm flutter pub get`
- A running backend reachable via `.env`'s `FUNCTIONS_BASE_URL`/`SUPABASE_ANON_KEY` (device/simulator build),
  or a pure `mocktail`-driven test run (no backend needed for the automated suite below).
- An authenticated session with at least one existing chat conversation (RF04 already shipped).

## Automated checks (run first — fastest feedback)

```bash
fvm flutter test test/features/chat/domain/entities/insight_trigger_test.dart
fvm flutter test test/features/chat/domain/entities/proactive_insight_test.dart
fvm flutter test test/features/chat/data/chat_remote_data_source_test.dart
fvm flutter test test/features/chat/data/chat_repository_impl_test.dart
fvm flutter test test/features/chat/presentation/bloc/chat_bloc_test.dart
fvm flutter test test/features/chat/presentation/widgets/insight_card_test.dart
fvm flutter test test/features/home/presentation/pages/home_chat_shell_page_test.dart
fvm flutter test test/architecture/
fvm flutter test --coverage   # RNF07 — lib/**/domain/** ≥ 80%
```

All of `contracts/chat-repository-insight-extension.md`'s and `contracts/chat-bloc-insight-extension.md`'s
scenario tables are expected to be implemented as cases inside the files above — there is no scenario in either
contract that requires a running backend or a physical device to verify.

## Manual validation scenarios (device/simulator, matching spec.md's User Stories)

### 1. Message-count trigger fires once, interleaved (User Story 1, SC-001)

1. Open an existing conversation (or start "Novo Chat" and send the 1st message).
2. Send messages until 5 user messages have been sent in this viewing session, letting each turn's response
   finish (or fail) before sending the next.
3. **Expect**: right after the 5th turn resolves, an ochre-spined "INSIGHT" card appears interleaved in the
   message list, right after the point it was generated — composer, scroll position, and every other message
   are otherwise untouched.
4. Dismiss it (tap "x"), then send 5 more messages.
5. **Expect**: a second, independent card appears once the 10th message's turn resolves.

### 2. Inactivity trigger fires after 2 minutes idle (User Story 2, SC-002)

1. Open a conversation and stop interacting — leave the app foregrounded on this screen, send nothing.
2. Wait 2 minutes.
3. **Expect**: a card appears with no new message having been sent.
4. Send a message with the timer only partially elapsed (e.g., at 1 minute); confirm no card appears at the
   old 2-minute mark — only a fresh 2 minutes after that new message would trigger one.

### 3. Pause/resume across backgrounding, drawer, and navigation (FR-010)

1. Start the 2-minute idle timer (send a message, then wait ~1 minute without sending another).
2. Background the app (Home button / app switcher) for 2+ minutes, then resume.
3. **Expect**: no card appears immediately on resume — the paused time didn't count, and a fresh 2-minute
   window only starts counting from the moment of resume.
4. Repeat using the side-menu drawer (open it, wait, close it) and using "Meus Registros"/"Configurações"
   (navigate there, wait, navigate back) in place of backgrounding — same expected outcome each time.

### 4. Failure and offline are invisible (User Story 3, SC-003)

1. Put the device in airplane mode (or otherwise force offline), then satisfy either trigger condition
   (send 5 messages while offline is blocked by RF04's own composer gate — so instead, let the inactivity
   timer reach 2 minutes while offline).
2. **Expect**: nothing appears anywhere on screen; composer, scrolling, and the offline banner behave exactly
   as RF04 already specifies, with zero additional visible effect from the skipped insight attempt.
3. Restore connectivity and confirm the *next* natural crossing/window (not the skipped one) produces a card
   normally.
4. Separately, with a debug build or a backend test double forcing `chat-insight-create` to return
   `status: 'failed'` (or to time out), repeat steps 1–3 online — same expected invisibility.

### 5. Dismiss touches nothing else (User Story 4, SC-004)

1. Trigger a card, scroll the conversation so the card sits mid-list, note the exact scroll offset.
2. Tap "x".
3. **Expect**: the card disappears; scroll position, every other message, and the composer are pixel-identical
   to before the tap.

### 6. No persistence across viewing sessions (SC-005)

1. Trigger a card (leave it undismissed, or dismiss it — try both).
2. Leave the conversation (switch to another via the drawer, or force-quit and reopen the app) and return to
   the same conversation.
3. **Expect**: no card from the earlier viewing session reappears either way; the message-count/inactivity
   counters have restarted at zero (confirm by sending 4 messages — no 5th-message fire until a genuinely new
   5th message is sent in this new viewing session).

## Out of scope for this quickstart (per spec.md FR-011 / Edge Cases)

- Insight content quality/wording — never evaluated here (RF08's own scope note).
- A save/bookmark action on an insight card — does not exist.
- Any backend/API-contract change — none was made; this unit only calls the already-documented
  `chat-insight-create` function.
