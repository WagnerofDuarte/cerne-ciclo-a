# Feature Specification: P-RF04 — Interactive chat with memory (RAG)

**Feature Branch**: `007-chat-memory-rag` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "P-RF04 — Interactive chat with memory (RAG): Build the conversation with the AI agent, which answers with context from the user's previous entries, per docs/input/requirements.md section 1 (RF04) and its acceptance criteria. Prototype states: 'Tela 1 — Home/Chat' (default), 'Streaming', 'Falha ao gerar resposta', 'Offline'; 'Tela 3 — Menu lateral' with the session list and the new-conversation action (prototype extract, sections 2.2 and 4). Backend: POST /chat/sessions, GET /chat/sessions, GET /chat/sessions/:id/messages, POST /chat/sessions/:id/messages (SSE), POST /chat/sessions/:id/messages/:userMessageId/retry (requirements, section 6.3). Depends on F000, RF03. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## Clarifications

### Session 2026-10-19

- Q: `POST /chat/sessions` accepts an optional `title`, the backend has no auto-titling logic of its own, and no endpoint exists to rename a session afterward — so whatever the app does at creation time is permanent for that conversation. Should the app send a title derived from the first message, or never send one? → A: The app derives a short title client-side from the first message's text (trimmed, capped to a short preview length) and sends it in `POST /chat/sessions`'s `title` field at the moment that first message creates the session. This is the only mechanism that can ever give a conversation a human-recognizable name, and User Story 4 explicitly requires the side menu to let users find past conversations "by name." (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: `GET /chat/sessions` is cursor-paginated (`cursor`/`limit`, default 20, max 50) and its items carry no documented sort order; the prototype's side-menu extract shows a flat "CONVERSAS" list with no load-more control. How should the side menu order and page through sessions once an account has more than one page's worth? → A: The list is ordered by most recent activity (`lastUserMessageAt`, descending; a session always has a `lastUserMessageAt` by the time it is listed, since sessions are only created together with their first message), and the side menu fetches further pages via `cursor` as the user scrolls to the bottom of the "CONVERSAS" section (the same infinite-scroll pattern already established for RF07's own list) — so no conversation ever becomes unreachable as the account accumulates sessions beyond a single page. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: `docs/input/requirements.md` §6.3 marks both `GET /chat/sessions` and `GET /chat/sessions/:id/messages` as "works offline (cache)," without scoping that to only the one conversation that happened to be open when connectivity dropped. Does offline mode cover every previously-opened conversation, or only the one open at disconnect? → A: The cache (and offline readability) covers every chat session the user has opened at least once while online — both the side menu's own session list and the message history of each previously-opened conversation remain browsable and switchable while offline; only creating a session, sending a message, and retrying require connectivity (already covered by FR-012). Selecting a conversation from the side menu that was never loaded while online, while currently offline, shows the standard no-connection state (no cached data to fall back to) rather than any content. (Resolved by technical judgment per user direction, applying Constitution Principle I.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Getting an answer grounded in your own journal (Priority: P1)

A user opens the chat and asks the AI agent something related to their life, without repeating what they already wrote elsewhere. The agent's answer reflects relevant things the user recorded before, not just the current message in isolation, and the exchange stays on screen as a normal, persisted conversation the user can come back to.

**Why this priority**: This is the entire premise of RF04 — "memory" via semantic search over past entries. Without it, the screen is just a generic chat window with no connection to the rest of the product.

**Independent Test**: Can be fully tested by seeding an account with a prior entry about a specific topic, sending a chat message that references that topic without quoting it verbatim, and confirming the agent's response demonstrates awareness of the seeded entry's content.

**Acceptance Scenarios**:

1. **Given** the user has at least one prior entry about a specific topic, **When** they send a chat message related to that topic, **Then** the agent's response reflects information from that entry, even though the message itself never restated it.
2. **Given** a conversation already has one or more exchanges, **When** the user leaves the screen and returns later (including after an app restart), **Then** the full exchange history is still present, in the same order, without needing to be resent.
3. **Given** the user sends a chat message, **When** the message is accepted, **Then** it is stored and displayed as part of the conversation but does **not** create a journal entry — chat messages are conversational only, with no automatic persistence as an entry (the one exception, an explicit save action, belongs to a later unit and is out of scope here).

---

### User Story 2 - Always knowing what the agent is doing (Priority: P1)

While waiting for or reading a response, the user can always tell, at a glance, which of three things is happening: the answer is still arriving, it finished successfully, or it failed — and a response that stops arriving partway through never just vanishes.

**Why this priority**: RF04's acceptance criteria explicitly require these three states and the no-disappearing-partial-message rule; without a clear, honest status, users cannot trust the chat enough to rely on it.

**Independent Test**: Can be fully tested by sending a message and observing the UI progress through the "processing/streaming" state into either "complete response" or "error," and separately by forcing a connection drop mid-response and confirming the partial text stays visible with a failure indication instead of disappearing.

**Acceptance Scenarios**:

1. **Given** the user has just sent a message, **When** the agent begins producing a reply, **Then** the response is revealed progressively (streaming) with a visible in-progress indicator, distinct from a finished message.
2. **Given** a response finishes streaming normally, **When** the last token arrives, **Then** the message is shown in its final, complete form with its timestamp, no longer carrying any in-progress indicator.
3. **Given** the connection drops, or the backend returns an error, while a response is still arriving, **When** that happens, **Then** whatever text had already arrived stays visible, together with a clear failure indication in place of the timestamp — the message is never removed or left in an ambiguous unfinished-looking state.

---

### User Story 3 - Recovering from a failed response without losing the conversation (Priority: P2)

A response fails or is cut short. The user taps the failed message and gets a fresh attempt at an answer to the same question, without having to retype it, without creating a duplicate question in the history, and without disturbing the rest of the conversation.

**Why this priority**: A direct extension of Story 2's failure state — the failure indication is only useful if there's a documented way out of it, and the requirement calls this out explicitly ("a way to try again" is part of RF04's own scope).

**Independent Test**: Can be fully tested by forcing a response failure, tapping the failed message to retry, and confirming a new response is generated for the same original question, with the user's question appearing exactly once in the history.

**Acceptance Scenarios**:

1. **Given** a message shows the "Falha ao gerar resposta" state, **When** the user taps it, **Then** a new response attempt starts for that same original question, going through the same processing/streaming → complete/error states as a normal response.
2. **Given** a retry is in progress or has completed, **When** the history is inspected, **Then** the user's original question appears exactly once — retrying never duplicates the question, only replaces the failed answer with a new attempt.
3. **Given** the retry itself fails again, **When** that happens, **Then** the message returns to the same failure state with the same way to try again — retrying is not limited to a single attempt.

---

### User Story 4 - Organizing conversations from the side menu (Priority: P2)

A user wants to start a brand-new conversation without losing an existing one, and wants to see and return to past conversations by name and recency from the side menu.

**Why this priority**: RF04's own scope explicitly includes the side menu's session list and "Novo Chat" action (prototype extract, sections 2.2 and 4) — without it, a user has no way to manage more than one conversation at a time.

**Independent Test**: Can be fully tested by having at least one existing conversation, opening the side menu, confirming it lists past sessions with a title and timestamp, tapping "Novo Chat," confirming the chat screen shows an empty conversation, and confirming the prior conversation is unchanged when reopened from the list.

**Acceptance Scenarios**:

1. **Given** the user has one or more existing conversations, **When** they open the side menu, **Then** a "CONVERSAS" section lists each one with a title and a timestamp.
2. **Given** the side menu is open, **When** the user taps the new-conversation action ("Novo Chat"), **Then** the chat screen shows an empty conversation, ready to accept a first message, without discarding any previous conversation.
3. **Given** the user selects a past conversation from the list, **When** it opens, **Then** its full message history is shown exactly as it was left.

---

### User Story 5 - Reading history while offline (Priority: P3)

A user without a connection can still read everything they already loaded, but cannot send anything new, and is told clearly why.

**Why this priority**: Explicitly one of the four required prototype states for this screen, and it protects against the worse failure mode of a chat screen that looks broken or loses content when connectivity drops — but it is a secondary concern relative to the core conversation and failure-recovery loops above.

**Independent Test**: Can be fully tested by loading a conversation, simulating a loss of connectivity, confirming the existing history stays visible and scrollable, confirming the send control is disabled with an explanatory banner, and confirming sending is not possible until connectivity returns.

**Acceptance Scenarios**:

1. **Given** a conversation is already loaded, **When** the device goes offline, **Then** the existing message history remains visible and scrollable, and a banner explains that new messages are blocked.
2. **Given** the device is offline, **When** the user looks at the composer, **Then** the send control is visibly disabled — no message can be sent until the connection returns.
3. **Given** the connection returns, **When** the user resumes using the screen, **Then** the send control re-enables and new messages can be sent normally.
4. **Given** the user has previously opened more than one conversation while online, **When** the device goes offline and the user switches between those previously-opened conversations from the side menu, **Then** each one's cached history is shown exactly as it was left, not just the conversation open at the moment connectivity dropped.

---

### Edge Cases

- The user tries to send an empty or whitespace-only message: the send control stays disabled/inactive, and no request is made.
- A message at or near the backend's maximum length is sent: the system either prevents exceeding that maximum before sending or surfaces the backend's resulting validation error clearly, without losing the text the user typed.
- A message is sent while a previous response in the same conversation is still streaming, or is sitting in the failed/"tap to retry" state: the composer stays disabled until that turn resolves (completes or is retried to a new resolution), so a session never has two responses racing at once.
- The session expires (RF03/RF07's existing "Sessão expirada" behavior) while a response is mid-stream or while viewing history: the existing overlay is shown, history and scroll position are preserved underneath it, and once the user re-authenticates, the conversation resumes exactly where it was — this unit reuses that behavior rather than redefining it.
- The user navigates away from a conversation (e.g., via the side menu) while a response is still streaming: when the user returns to that conversation, the message reflects whatever the backend ultimately recorded for it (complete or failed) rather than being stuck in a stale in-progress state tied to a connection that no longer exists.
- An account has zero conversations yet (first-ever use of chat): the chat screen still shows a ready-to-use empty conversation, and a session is created at the point the first message is actually sent.
- The user retries a failed message that is not the most recent message in the conversation: the retry still succeeds and only affects that specific message's response, leaving every later message in the conversation untouched.
- An account has more conversations than fit in one backend page of `GET /chat/sessions` (more than its default/max `limit`): scrolling to the bottom of the side menu's "CONVERSAS" section fetches the next page via `cursor` rather than silently stopping at the first page.
- The user is offline and selects, from the side menu, a conversation that was never opened while online: no cached data exists for it, so the screen shows the standard no-connection state instead of any content, distinct from the normal offline case of browsing an already-cached conversation.
- Opening the side menu's conversation list, the export job, dashboard, filters, action-plan board, and every other screen or action not named in this feature's scope: unaffected by this unit and not touched by it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST let an authenticated user send a text message in an active conversation (`POST /chat/sessions/:id/messages`) and receive a response generated with the help of the user's own previously captured entries — the response MUST be able to reflect information from a prior entry that the user's message does not itself restate.
- **FR-002**: Every message the user sends and every response the agent produces MUST be persisted as part of the conversation (`chat_messages`) and MUST still be present, in the same order, the next time that conversation is opened — including after the app is closed and reopened (`GET /chat/sessions/:id/messages`).
- **FR-003**: Sending a chat message MUST NOT create a journal entry under any circumstance handled by this unit; the only path from a chat message to a persisted entry is the explicit save action of a later unit (RF10), which this unit does not implement.
- **FR-004**: While a response is being generated, the system MUST render it in a visibly distinct "processing/streaming" state (content revealed progressively, in-progress indicator) and MUST transition it to one of exactly two end states: "complete response" (final text, timestamp shown, no in-progress indicator) or an error state ("Falha ao gerar resposta," shown in place of the timestamp). A response MUST always end in one of these three states — streaming, complete, or error — never left ambiguous.
- **FR-005**: If the response stream is interrupted before completion (connection drop, backend error, or any other cause), the system MUST keep whatever partial text had already arrived visible, together with the failure indication — it MUST NOT remove, hide, or blank out a partial message.
- **FR-006**: A message in the error state MUST be tappable to trigger a retry (`POST /chat/sessions/:id/messages/:userMessageId/retry`) that regenerates the response to that same original question. A retry MUST NOT duplicate the user's original question in the conversation, and MUST go through the same processing/streaming → complete/error states as any other response. Retrying MUST remain available after a retry itself fails, with no fixed limit on the number of attempts, and MUST remain available on any message in the error state regardless of how much later conversation exists after it.
- **FR-007**: While a response in the current conversation is streaming or sitting in the error state awaiting retry, the system MUST keep the message-send control disabled, re-enabling it only once that response reaches a final state (complete, or retried to a new resolution) — so a single conversation never has two responses in flight at once.
- **FR-008**: The side menu MUST show a "CONVERSAS" section listing the user's existing conversations (`GET /chat/sessions`), each with its title and a timestamp, ordered by most recent activity (latest `lastUserMessageAt` first). If the account has more sessions than fit in one backend page, the list MUST fetch further pages via the endpoint's `cursor` as the user scrolls to the bottom of the section, so every conversation stays reachable.
- **FR-009**: The side menu MUST offer a "Novo Chat" action that opens the chat screen in an empty conversation state, ready to accept a first message, without discarding or altering any existing conversation. Selecting an existing conversation from the list MUST open it with its full message history intact, exactly as it was left.
- **FR-010**: A new conversation (`POST /chat/sessions`) MUST only be created at the point a first message is actually sent into an empty conversation state — opening an empty conversation state (via "Novo Chat," or on an account with no conversations yet) MUST NOT by itself create a session with no messages in it. That creation call MUST include a `title` derived from the first message's own text (a short, trimmed preview), so the new conversation has a distinguishable, human-recognizable name in the side menu from the moment it exists — the backend has no auto-titling of its own and no later rename endpoint.
- **FR-011**: While the device is offline, the system MUST keep every previously-opened conversation's history, and the side menu's own "CONVERSAS" list, visible, scrollable, and switchable from the local cache — not only the one conversation that happened to be open when connectivity dropped — MUST disable the send control, and MUST show an explanatory message that new messages are blocked until the connection returns. Selecting a conversation that was never opened while online, while currently offline, MUST show the standard no-connection state rather than any content, since nothing was ever cached for it. Sending MUST become possible again as soon as connectivity is restored, with no manual reset required.
- **FR-012**: The system MUST NOT attempt to create a new conversation or send/retry a message while offline — both actions require a connection and MUST be blocked client-side rather than attempted and failed.
- **FR-013**: The screen MUST reuse the existing session-expiration handling (RF03/RF07's "Sessão expirada" overlay: history and scroll position preserved, re-authentication returning to the same conversation state) rather than introducing a separate expiration treatment for chat.
- **FR-014**: This unit MUST NOT implement the "save message as entry" button (RF10), the proactive-insight card (RF08), AI-persona selection as an active setting (extension, requirements section 2 — persona is only read at session creation as whatever the backend already returns), or any change to the backend, its API contract, or its configuration.

### Key Entities

- **Chat Session**: One conversation thread, identified by an id, with a title derived client-side from its first message at creation time and shown in the side menu's "CONVERSAS" section (a defensive generic placeholder is shown only if a session is ever encountered with an empty title), the persona that was in effect when it was created (read-only here — not user-editable in this unit), and timestamps including when it was created and when it last received a user message (the latter drives the side menu's ordering).
- **Chat Message**: One turn inside a Chat Session — either the user's question or the agent's response — with its content, its position in the conversation, and its status (still arriving, complete, or failed). A failed message is the one eligible for retry; retrying produces a new resolution for the same original question rather than a new message pair.
- **Context used for a response**: The set of the user's own prior entries the agent draws on to ground a given response. It is retrieved automatically for every response and is not displayed to the user as a separate citation list — the prototype defines no such element — but it is what makes a response "grounded" rather than generic, per User Story 1.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When a seeded prior entry exists on a topic, a chat message about that topic that does not restate the entry's content still produces a response reflecting that entry's information, in 100% of tested cases.
- **SC-002**: Every sent or retried message ends in exactly one of the three defined states (streaming → complete, or streaming → error) with zero cases observed stuck in an undefined or ambiguous state.
- **SC-003**: In 100% of forced stream-interruption scenarios, the partial response text remains visible on screen together with its failure indication — never disappearing.
- **SC-004**: Across repeated retries of the same failed message, the user's original question appears exactly once in the conversation history, with zero observed duplicates.
- **SC-005**: Conversation history is preserved exactly (same messages, same order) across an app restart and across switching away from and back to a conversation via the side menu, in 100% of tested cases.
- **SC-006**: While offline, 100% of the history of every previously-opened conversation stays readable and switchable from the side menu (not only the one open at disconnect), and the send control is visibly disabled for the entire duration of the outage, re-enabling within one interaction of connectivity returning.
- **SC-007**: On an account with more conversations than one backend page of `GET /chat/sessions` returns, 100% of them remain reachable from the side menu by scrolling, with zero conversations permanently hidden.

## Assumptions

- A conversation ("session") is created lazily, only when the user actually sends a first message into an empty conversation state, rather than eagerly when "Novo Chat" is tapped or when the chat screen is simply opened — this keeps the backend free of empty sessions and matches `POST /chat/sessions` accepting no required `title`. Re-opening the app resumes whichever conversation the user was last in (if any exist); when none exist yet, the screen shows the same empty, ready-to-send state "Novo Chat" also produces.
- The "context" step of the backend's streaming sequence (`message_created -> context -> token* -> done|error`) is an internal signal the client may use to drive its own progress indicator, not a citation list rendered to the user — the prototype defines no UI for displaying which entries were used.
- A session's `personaSnapshot` (requirements section 2's persona extension) is read and stored as whatever the backend returns at session creation; this unit does not add any UI for choosing or changing it.
- Network-error handling for this screen's write calls (send, retry, create session) follows the same retryable/non-retryable pattern already established project-wide (RNF09) — no new error-presentation style is introduced specifically for chat.
- Every chat session is created with a client-derived title (see FR-010), so the generic placeholder in the side-menu list is a defensive fallback for an unexpected empty title rather than the normal case; the exact wording of both the derived-title preview length and the fallback placeholder is a presentation detail left to implementation.
- The composer's existing disabled-by-default rendering (already scaffolded by F000) becomes conditionally enabled by this unit whenever there is non-empty text to send and no response currently in flight or awaiting retry for that conversation — it does not require a separate redesign of the composer itself.
