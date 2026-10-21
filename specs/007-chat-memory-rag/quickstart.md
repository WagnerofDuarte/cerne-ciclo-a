# Quickstart: P-RF04 — Interactive chat with memory (RAG)

How to validate this unit end-to-end once implemented, mapped to spec.md's five user stories. A run guide —
interfaces are in `contracts/`, state/entities in `data-model.md`.

## Prerequisites

- F000 and RF03 (vault/auth) already implemented and passing — a signed-in, authenticated test account can
  reach `/home`.
- At least one prior entry seeded on the test account about a specific, identifiable topic (reuse
  `docs/input/backend/fixtures/seeded-search-entries.md`'s own fixtures if the backend's RAG retrieval draws
  from the same entries RF06 already seeds) — needed for Story 1's "grounded in your own journal" check.
- An account with zero chat sessions yet, for the Edge Case "first-ever use of chat" scenario, and a second
  account (or the same account after Story 1) with 2+ sessions and, ideally, more sessions than
  `chat-sessions-list`'s default page `limit` (20) for the SC-007 pagination check.
- A way to force a mid-stream connection drop or backend error for Story 2/3 (airplane mode toggled partway
  through a response, or a test double at the repository layer for automated tests).

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html    # RNF07 gate — ChatTitleDeriver, ChatStreamEvent,
                                                         # ChatMessage's status-transition logic, etc.
dart test/architecture/no_bloc_imports_bloc_test.dart   # ChatBloc/ChatSessionsBloc stay within lib/features/chat/
dart test/architecture/domain_purity_test.dart          # chat/domain/ imports neither Flutter nor chat/data/
```

`contracts/sse-transport-extension.md`, `contracts/chat-repository.md`, `contracts/chat-bloc.md`, and
`contracts/chat-sessions-bloc.md` each carry the full scenario table this unit's coverage depends on.

## Manual verification (device/Simulator)

### Story 1 — Getting an answer grounded in your own journal (P1)

1. With the seeded prior entry present, open the chat and send a message related to that entry's topic
   without quoting it (e.g., if the entry is about pre-presentation anxiety, ask "o que me ajuda a lidar com
   nervosismo antes de falar em público?"). **Expect**: the streamed response reflects the seeded entry's
   content (SC-001).
2. Leave the chat screen (open "Meus Registros", then come back via the side menu), then fully restart the
   app. **Expect**: the full exchange, in the same order, is still present with no resend (Acceptance
   Scenario 2).
3. Open "Meus Registros" right after sending a chat message. **Expect**: no new entry was created from it —
   the chat message exists only in the conversation, never as a journal entry (Acceptance Scenario 3/FR-003).

### Story 2 — Always knowing what the agent is doing (P1)

1. Send a message. **Expect**: the response appears progressively with a visible streaming indicator
   (pulsing cursor), distinct from a finished bubble.
2. Let it finish normally. **Expect**: the final text is shown with a timestamp, no streaming indicator left
   (Acceptance Scenario 2).
3. Send another message, then force a mid-stream failure (airplane mode, or kill the backend connection).
   **Expect**: whatever partial text had already arrived stays visible, with "Falha ao gerar resposta" in
   place of the timestamp — never blanked or removed (SC-003).

### Story 3 — Recovering from a failed response without losing the conversation (P2)

1. On the failed message from Story 2, tap it. **Expect**: a fresh attempt starts, going through the same
   streaming → complete/error states; the original question still appears exactly once in the history
   (SC-004).
2. Force the retry itself to fail again. **Expect**: the same failure state, with the same tap-to-retry
   affordance — not a dead end (Acceptance Scenario 3).
3. Scroll up to an older failed message (not the most recent one in the conversation) and retry it. **Expect**:
   only that message's response changes; every later message is untouched (Edge Cases).

### Story 4 — Organizing conversations from the side menu (P2)

1. With at least one existing conversation, open the side menu (☰). **Expect**: a "CONVERSAS" section lists
   each conversation with a title (derived from its first message) and a timestamp, most-recently-active
   first.
2. Tap "Novo Chat". **Expect**: the chat screen shows an empty conversation, composer ready; the previous
   conversation is unaffected (Acceptance Scenario 2).
3. Send a first message in this new conversation, then reopen the side menu. **Expect**: the new conversation
   now appears in "CONVERSAS" with its derived title (research.md R6).
4. Tap the earlier conversation from the list. **Expect**: its full history reopens exactly as it was left
   (Acceptance Scenario 3).
5. On an account with more sessions than one backend page, scroll to the bottom of "CONVERSAS". **Expect**:
   the next page loads via `cursor`, with no conversation ever permanently hidden (SC-007).

### Story 5 — Reading history while offline (P3)

1. With a conversation already loaded, enable airplane mode. **Expect**: the existing history stays visible
   and scrollable; a banner explains new messages are blocked; the composer's send control is visibly
   disabled.
2. Try to type and send anyway. **Expect**: nothing is sent — the control stays disabled, no request is
   attempted (FR-012).
3. While still offline, open the side menu and switch to a *different* conversation that was opened at least
   once earlier while online. **Expect**: its own cached history shows correctly too — not just the
   conversation that happened to be open when connectivity dropped (SC-006/Clarification 3).
4. While still offline, select from the side menu a conversation that has **never** been opened before.
   **Expect**: the standard no-connection state appears instead of any content (Edge Cases) — distinct from
   the normal "cached and readable" case in step 3.
5. Disable airplane mode. **Expect**: the send control re-enables and the offline banner disappears without
   any manual action, within one interaction (SC-006).

### Edge cases worth exercising manually at least once

- Try to send an empty or whitespace-only message. **Expect**: the send control stays disabled; no request
  fires.
- Type a message at the 8000-character cap (`chat.messages.send`'s `maxLength`). **Expect**: the field simply
  stops accepting further characters — no backend validation round-trip is ever needed (research.md R12).
- Send a message, then immediately try to send another before the first response resolves. **Expect**: the
  composer stays disabled for the whole conversation until that turn completes or is retried to a new
  resolution (FR-007).
- Force a session expiration ("Sessão expirada") while a response is mid-stream. **Expect**: the existing
  overlay appears, history and scroll position are preserved underneath it, and re-authenticating resumes the
  same conversation exactly where it was (Edge Cases — reusing RF03/RF07's existing behavior, not a new one).
- Navigate away from a conversation (via the side menu) while a response is still streaming, then return to
  it a few seconds later. **Expect**: the message reflects whatever the backend ultimately recorded (complete
  or failed), not a stuck in-progress state (Edge Cases; research.md R11).
- On a brand-new account with zero conversations, open the chat screen. **Expect**: an empty, ready-to-send
  conversation is shown immediately — no session is created until the first message is actually sent
  (Edge Cases/FR-010).
