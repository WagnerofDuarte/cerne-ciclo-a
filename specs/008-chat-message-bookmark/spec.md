# Feature Specification: P-RF10 — Save a chat message as an entry

**Feature Branch**: `008-chat-message-bookmark` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-21

**Status**: Draft

**Input**: User description: "P-RF10 — Save a chat message as an entry: Let the user turn one of their own chat messages into a journal entry, per docs/input/requirements.md section 1 (RF10) and its acceptance criteria. Prototype state: 'Tela 1 — Bookmark' with its sub-states (prototype extract, section 2.2). Backend: POST /entries with source `chat` and `chatMessageId` (requirements, section 6.2/6.3). Depends on RF01, RF04. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turning a message you just wrote into a journal entry (Priority: P1)

While chatting with the agent, the user says something worth keeping on its own — not through the dedicated capture flow (RF01), but right there in the conversation. They tap a bookmark control on their own message, and it becomes a normal, persisted journal entry without leaving the chat or retyping anything.

**Why this priority**: This is the entire premise of RF10 — a second, lightweight path into the journal for moments that happen inside a conversation. Without it, the feature does not exist.

**Independent Test**: Can be fully tested by sending a chat message, tapping its bookmark control, and confirming a new entry exists with that message's content, `source` = `chat`, and a `chatMessageId` pointing back to the originating message.

**Acceptance Scenarios**:

1. **Given** the user has sent a message in an active conversation, **When** they tap its bookmark control in its resting (`idle`) state, **Then** the control shows a saving indicator (spinner) and, on success, settles into a saved indicator (ochre check) — and a journal entry now exists with that message's text as content, `source` = `chat`, and `chatMessageId` set to that message's id.
2. **Given** a message's bookmark is in the saved state, **When** the user reopens the conversation later (including after restarting the app), **Then** the bookmark still shows the saved state for that message rather than resetting to idle.
3. **Given** the user saves a message, **When** that entry is later viewed anywhere entries are shown, **Then** it is structurally indistinguishable from an entry captured through RF01 — same content, same processing pipeline — except for carrying `source` = `chat` and a non-null `chatMessageId`.

---

### User Story 2 - Saving the same message twice never creates a duplicate (Priority: P1)

A user taps a bookmark that is already saved, or a save silently succeeded on the backend but the app never learned about it (lost connection, a restart mid-save, a reinstalled app with no local record of what was already saved). Either way, retrying never results in two entries for the same message.

**Why this priority**: Called out explicitly as its own acceptance criterion ("saving the same message twice does not create duplicate entries") — without it, a flaky connection or an impatient double-tap would pollute the journal with duplicate content, undermining trust in every other feature that reads entries.

**Independent Test**: Can be fully tested by saving a message, then issuing the save again for that same message (e.g., by forcing the app to forget its local saved-state record and tapping the bookmark again), and confirming exactly one entry exists afterward.

**Acceptance Scenarios**:

1. **Given** a message has already been saved as an entry, **When** a save for that same message is attempted again through the shared entry-creation flow (not via the `saved` checkmark itself, which is a non-interactive status indicator with no tap handler — see FR-003), **Then** no second entry is created — the existing entry is reused, and the bookmark still ends in the saved state.
2. **Given** the app has no local record of a message's save having already succeeded (e.g., the local record was lost or never updated after a dropped response), **When** the user taps its bookmark and it was in fact already saved on the backend, **Then** the outcome is identical to Scenario 1 — one entry, saved state — never a duplicate.

---

### User Story 3 - A failed save never disrupts the conversation (Priority: P2)

A save attempt fails — most commonly because the device has no connection. The user keeps chatting normally, and the failed bookmark offers a clear way to try again whenever they're ready.

**Why this priority**: RF10's acceptance criteria require this explicitly and anchor it to the same failure-isolation pattern used elsewhere in the product (RF08) — a save failure must be a contained, recoverable glitch, never something that degrades the surrounding chat experience.

**Independent Test**: Can be fully tested by forcing a save to fail (e.g., no connection), confirming the bookmark shows an error indicator while the rest of the conversation (sending, receiving, scrolling, other bookmarks) keeps working normally, then tapping the failed bookmark again once the failure condition is removed and confirming the save completes.

**Acceptance Scenarios**:

1. **Given** the device has no connection, **When** the user taps a message's bookmark, **Then** the control shows an error indicator (red warning) instead of getting stuck in the saving state, and every other part of the chat screen continues to function exactly as before the attempt.
2. **Given** a bookmark is in the error state, **When** the user taps it again, **Then** it re-attempts the save (returning to the saving indicator) and can reach the saved state once the underlying failure condition is gone.
3. **Given** a bookmark is saving or has failed, **When** the user sends new messages, scrolls, or interacts with other bookmarks in the same conversation, **Then** none of those actions are blocked or delayed by the in-progress or failed save.

---

### User Story 4 - Only your own messages can become entries (Priority: P2)

The bookmark control appears only on the user's own messages — never on the agent's responses.

**Why this priority**: Called out explicitly as an acceptance criterion; getting this wrong would let AI-generated text be filed into the journal as if the user had written it, which is a content-integrity problem, not just a cosmetic one.

**Independent Test**: Can be fully tested by inspecting a conversation containing both user and assistant messages and confirming the bookmark control renders only on the user ones.

**Acceptance Scenarios**:

1. **Given** a conversation contains both user messages and assistant responses, **When** the chat screen renders them, **Then** a bookmark control is present on every user message and absent from every assistant message, with no exceptions (including insight cards and partial/failed assistant responses).

---

### Edge Cases

- The user taps a bookmark twice in quick succession before the first tap's request resolves: the control ignores the second tap (or treats it as a no-op) rather than firing two concurrent save requests for the same message.
- A save is in flight when the user navigates away from the conversation (e.g., via the side menu) and later returns: the bookmark reflects whatever the save ultimately resolved to (saved or error), not a stale saving indicator tied to a request that already finished.
- The session expires (RF03/RF07's existing "Sessão expirada" behavior) while a save is in flight: the existing overlay takes over as it already does for the rest of the screen; once re-authenticated, the bookmark reflects the save's actual outcome rather than being stuck mid-attempt.
- The underlying message content is at or near the entry content length limit: the save either succeeds normally (chat messages are already capped well below the entry limit) or surfaces the resulting backend validation error on the bookmark as a normal error state — it does not crash or silently drop the attempt.
- A save fails for a reason other than connectivity (e.g., the PII check or embedding step fails after the write): the bookmark still shows the error state and remains retryable, the same as a connectivity failure — the user is not expected to distinguish the underlying cause.
- The user attempts to save an assistant message some other way than the (absent) bookmark control: there is no such path in this unit — assistant messages simply have no save action available anywhere.
- Opening My Records, search, export, the dashboard, the insertion modal, or any other screen or action not named in this feature: unaffected by this unit and not touched by it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A bookmark control MUST appear on every user message in the chat and MUST NOT appear on any assistant message, with no exceptions (including insight cards and assistant messages in any status — streaming, complete, or failed).
- **FR-002**: The bookmark control MUST have exactly four visible states — `idle` (resting), `saving` (spinner, in progress), `saved` (ochre check, succeeded), `error` (red warning, failed) — and MUST always be in exactly one of them.
- **FR-003**: Tapping a bookmark in the `idle` or `error` state MUST create a journal entry from that message (`POST /entries`) with `content` equal to the message's own text, `source` = `chat`, and `chatMessageId` set to that message's id, transitioning the control to `saving` and then, on success, to `saved`. The `saved` state is a terminal, non-interactive status indicator — it carries no tap handler, so a message that has reached `saved` cannot be re-tapped to trigger another save.
- **FR-004**: Saving a message whose entry already exists — whether because the control is already in the `saved` state or because the app has no local record that a prior save already succeeded — MUST NOT create a second entry; the existing entry is reused and the control ends in the `saved` state in either case.
- **FR-005**: If a save attempt fails for any reason (no connection, timeout, or any other write failure reported by the backend), the control MUST move to the `error` state rather than remaining in `saving` indefinitely or reverting silently to `idle`, and MUST remain tappable to retry.
- **FR-006**: An in-progress or failed save for one message MUST NOT block, delay, or otherwise affect any other part of the chat screen — sending new messages, receiving responses, scrolling, viewing insights, and the bookmarks on other messages all continue to function normally.
- **FR-007**: While a bookmark is in the `saving` state, further taps on that same bookmark MUST be ignored until that save resolves (to `saved` or `error`) — a message never has two save requests in flight at once.
- **FR-008**: The `saved` state of a message's bookmark MUST be reflected again whenever that conversation is reopened — including after navigating away and back, or restarting the app — for as long as the client can determine the message was already saved.
- **FR-009**: Entry creation triggered from the chat feature MUST go through the same shared entry-creation interface/use case already used elsewhere in the product, and MUST NOT directly import a repository or data source belonging to the entries feature from within the chat feature.
- **FR-010**: This unit MUST NOT implement the proactive-insight mechanism (RF08), the export flow (RF05), the dashboard (RF09), any extension feature (requirements section 2), or any change to the backend, its API contract, or its configuration.

### Key Entities

- **Journal Entry (chat-sourced)**: The same Journal Entry already defined for RF01 — a persisted, immutable record with text content and a creation time — now also reachable with `source` = `chat` and a non-null `chatMessageId` pointing back to the chat message it was saved from. Structurally identical to any other entry; nothing about later screens that read entries needs to treat it differently.
- **Bookmark**: Per-message, per-viewer UI state attached to a user chat message, cycling through `idle` → `saving` → `saved` (success) or `idle`/`error` → `saving` → `error` (failure, retryable). It exists only in relation to a specific message and never itself becomes a persisted record — the entry it may produce is the persisted side effect, not the bookmark itself.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Tapping the bookmark on a user message produces a retrievable journal entry with the correct content, `source`, and `chatMessageId` in 100% of success-path attempts.
- **SC-002**: Across repeated or retried save attempts on the same message — including after losing any local record of a prior successful save — exactly one journal entry exists per message in 100% of tested cases, with zero observed duplicates.
- **SC-003**: In 100% of forced save-failure cases (e.g., no connection), the rest of the chat screen remains fully usable throughout the failure, and the failed bookmark reaches the `saved` state once retried after the failure condition is removed.
- **SC-004**: Across all tested conversations, zero bookmark controls appear on assistant messages.
- **SC-005**: A message's `saved` bookmark state is still shown correctly after reopening its conversation (including after an app restart) in 100% of tested cases where the client has a way to know the save already succeeded.

## Assumptions

- The entry's `content` is the chat message's own text, saved verbatim with no edit step offered before saving — the feature is "save this message," not "compose a new entry from this message."
- The entry's `occurredAt` is the chat message's own `createdAt` timestamp (when it was sent), not the moment the user taps the bookmark, so the entry lands at the correct point in the user's timeline.
- Whether a message's bookmark shows `saved` after reopening a conversation (FR-008) relies on a device-local record of which messages this client has already saved; that record is a convenience, not a correctness mechanism — if it is ever missing or wrong (reinstall, cleared cache, a save that succeeded on the backend without the client learning about it), tapping the bookmark again is always safe and resolves to the correct `saved` state without creating a duplicate (FR-004), because the backend itself guarantees the idempotency.
- PII handling and embedding generation for chat-sourced entries follow the exact same pipeline already used for any other entry (RNF02) — this unit introduces no separate consent step or content review specific to chat-origin content.
- No distinct visual treatment (e.g., a badge or label) is added elsewhere in the product to call out chat-sourced entries beyond the `source` field already embedded in the entry's own data — no such element exists in the prototype outside the bookmark control itself.
- "The same shared interface/use case already used elsewhere in the product" (FR-009) refers to whatever cross-feature entry-creation contract RF01 already established (or, if none yet exists in a reusable form, the one this unit must introduce) — the specific shape of that contract is an implementation decision for the planning phase, not a product requirement.
- The `saved` state's checkmark is a terminal, non-interactive status indicator rather than a re-tappable button (FR-003): neither `docs/input/requirements.md` nor the prototype extract says whether a visibly `saved` bookmark can be tapped again, so this was resolved as a reasonable technical decision rather than left open — it keeps the bookmark's state machine simple (no `saved` → `saving`/`error` regression) and avoids a pointless network call once the check mark is showing. FR-004's duplicate-prevention guarantee still protects the real-world path that produces a "second save attempt": a message that renders `idle` only because the local saved-record was lost or never written, not a literal re-tap on a visible `saved` icon.
