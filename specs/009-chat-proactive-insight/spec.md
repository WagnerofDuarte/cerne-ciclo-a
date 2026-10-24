# Feature Specification: P-RF08 — Proactive insights (mechanism)

**Feature Branch**: `009-chat-proactive-insight` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "P-RF08 — Proactive insights (mechanism): Insert an AI suggestion into the chat without the user asking for it, per docs/input/requirements.md section 1 (RF08) and its acceptance criteria; parameter in section 10. Prototype state: 'Tela 1 — Insight' (prototype extract, section 2.2). Backend: POST /chat/sessions/:id/insight. Depends on RF04. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## Clarifications

### Session 2026-10-22

- Q: `POST /chat/sessions/:id/insight` has no sibling read endpoint (no `GET` returns past insights, and `GET /chat/sessions/:id/messages` never includes them) and no dismiss endpoint — the response schema's `dismissed` status value has no call that can ever produce it. Given RF08's acceptance criteria describe only a mechanism, not a persisted record, should insight cards survive leaving and reopening a conversation, and is dismissal a backend action? → A: Insight cards are purely ephemeral, client-side, per-viewing-session state. Dismissal (the "x") is a local UI action only — never a backend call — and nothing about an insight (shown, dismissed, or failed) is persisted or reconstructed when the conversation is reopened (including after an app restart) or when switching to it from the side menu; the mechanism's counters simply start fresh for that new viewing session. This is the only reading consistent with the endpoint inventory: there is no way to ask the backend "what insights has this session already had," so the client cannot and must not try to restore that history. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: The trigger parameter ("5 messages OR 2 minutes of inactivity, fires exactly once per satisfied condition") does not say whether the mechanism keeps re-arming for the rest of a long conversation, or fires only once ever, nor what happens if a new condition becomes satisfied while a previous insight attempt is still in flight or its card is still awaiting dismissal. How should re-arming and overlap be handled? → A: The mechanism re-arms continuously for the life of each viewing session — a new message-count crossing (10th, 15th, ... user message) or a new 2-minute idle window can each fire again after the previous one has been resolved. At most one insight attempt is ever in flight and at most one insight card is ever awaiting dismissal per conversation at a time; while either is true, both trigger conditions are suspended (not counted, not timed) and resume only once that attempt resolves (success, failure, or was skipped offline) and any resulting card is dismissed. This keeps the mechanism simple and matches the explicit "never disrupts the conversation" intent — a backlog of stacked, unrequested cards would be the opposite of that. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: Neither the requirement nor the prototype extract defines any visible failure state for an insight (unlike RF04's "Falha ao gerar resposta" or RF10's error bookmark) — the prototype's only documented insight state is the successful card. Should a failed or skipped (offline) attempt show any indicator at all? → A: No indicator of any kind. A failed HTTP call, a successful call that resolves to `status: 'failed'`, and a trigger condition satisfied while offline are all treated identically: no card appears, nothing is shown anywhere on screen about the attempt, and the rest of the chat screen is completely unaffected — consistent with RF08's own scope note that generation failures must leave "the main chat keep[ing] working normally," and with there being no prototype state to render even if the app wanted to surface one. (Resolved by technical judgment per user direction, applying Constitution Principle I.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A suggestion appears after a burst of conversation, unasked (Priority: P1)

While chatting normally, after the user has sent several messages in the current conversation, an insight card appears on its own, interleaved among the messages — without the user ever asking for a suggestion or tapping anything to request one.

**Why this priority**: This is the message-count path of RF08's trigger — one of its two defining conditions — and it is the most deterministic, reproducible way to demonstrate the entire feature exists.

**Independent Test**: Can be fully tested by opening a conversation and sending 5 user messages, each turn allowed to resolve normally, and confirming an insight-generation call fires once the 5th message's turn is idle, with a card rendered interleaved in the message list on success.

**Acceptance Scenarios**:

1. **Given** the user has sent fewer than 5 messages since opening the conversation, **When** they send the 5th such message and its turn resolves (response complete or failed), **Then** the system calls the insight endpoint once with `triggerType` = `message_count`, and, on success, renders a card interleaved in the message list at that point, with no change to the composer or scroll position beyond the card's own insertion.
2. **Given** an insight already fired and was resolved (shown and dismissed, or failed/skipped) at the 5-message mark, **When** the user sends 5 further messages (reaching the 10th overall in that viewing session), **Then** the mechanism fires again exactly once for that new crossing.
3. **Given** the response to the user's most recent message is still streaming, or is sitting in the error state awaiting retry, when the 5-message mark is reached, **When** that turn eventually resolves, **Then** the insight attempt is made only once the conversation is idle for that turn — never concurrently with an in-flight response or retry.

---

### User Story 2 - A suggestion appears after a quiet moment (Priority: P1)

While a conversation is open and visible on screen, if the user goes quiet — no new message sent — for 2 minutes, an insight card appears on its own, without a new message being needed to set it off.

**Why this priority**: This is the inactivity path of RF08's trigger — the second of its two defining conditions, and the one that fires without any further user action at all.

**Independent Test**: Can be fully tested by opening a conversation, taking no action for 2 minutes while the screen stays foregrounded, and confirming an insight-generation call fires with `triggerType` = `inactivity`.

**Acceptance Scenarios**:

1. **Given** a conversation is open and foregrounded with no new user message sent for 2 minutes, **When** that 2-minute mark is reached, **Then** the system calls the insight endpoint once with `triggerType` = `inactivity`.
2. **Given** the inactivity timer is counting, **When** the user sends a new message before 2 minutes elapse, **Then** the timer resets and no inactivity trigger fires for that window.
3. **Given** the inactivity timer is counting, **When** the user navigates away from that conversation (backgrounds the app, opens the side menu, or switches to a different conversation) before 2 minutes elapse, **Then** the timer pauses and only resumes counting from zero once that same conversation is foregrounded again — time spent away never counts toward the 2 minutes.

---

### User Story 3 - A failed or blocked attempt never disrupts the conversation (Priority: P2)

A trigger condition is satisfied, but generating the insight fails, or cannot even be attempted because the device is offline. Either way, the conversation keeps working exactly as if nothing had happened.

**Why this priority**: Called out explicitly as its own acceptance criterion — a proactive feature the user never asked for must never become a visible point of failure.

**Independent Test**: Can be fully tested by forcing a trigger condition while offline, and separately by forcing the insight call to fail or time out while online, and confirming in both cases that no card, error indicator, or disruption appears anywhere, and the rest of the screen (composer, scrolling, other messages) remains fully usable throughout.

**Acceptance Scenarios**:

1. **Given** a trigger condition becomes satisfied while the device is online, **When** the insight call fails outright (network error, timeout) or returns successfully with `status: 'failed'`, **Then** no insight card and no error indicator of any kind appear, and the rest of the chat screen is completely unaffected.
2. **Given** a trigger condition becomes satisfied while the device is offline, **When** that happens, **Then** the system does not attempt the call at all, with the same no-visible-effect outcome as Scenario 1.
3. **Given** a prior attempt failed or was skipped offline, **When** the next trigger condition is later satisfied (the next message-count crossing or the next 2-minute idle window), **Then** a new attempt is made normally — one failed or skipped attempt never permanently disables the mechanism for that conversation.

---

### User Story 4 - Dismissing a suggestion touches nothing else (Priority: P2)

Having dismissed a visible insight card leaves the rest of the conversation exactly as it was before — same scroll position, same messages, same composer state — with only the card itself gone.

**Why this priority**: Called out explicitly as its own acceptance criterion, protecting the core conversation from side effects of a feature that is, by definition, unrequested.

**Independent Test**: Can be fully tested by triggering a visible insight card, noting the current scroll position, tapping its dismiss ("x") control, and confirming the scroll position and every other part of the conversation are unchanged except for the card's removal.

**Acceptance Scenarios**:

1. **Given** a visible insight card at some scroll position, **When** the user taps its dismiss control, **Then** the card is removed from view, the scroll position is exactly preserved, and no other message, the composer, or any other screen state changes.
2. **Given** an insight card has just been dismissed, **When** a new trigger condition is later satisfied, **Then** the mechanism may produce a new, independent insight card as normal — dismissing one does not permanently disable future ones.
3. **Given** a conversation containing a dismissed (or still-visible, un-dismissed) insight card is left and later reopened (including after an app restart, or by switching away and back via the side menu), **When** it reopens, **Then** no insight card from the earlier viewing session reappears — insights are not persisted, and the mechanism's counters start fresh for the new viewing session.

---

### Edge Cases

- A trigger condition becomes satisfied while an insight attempt from an earlier trigger is still in flight, or its resulting card is still awaiting dismissal: the new condition is not evaluated into a second concurrent attempt or a second card — at most one insight attempt is in flight and at most one card is awaiting dismissal per conversation at any time (see User Stories 1–2's re-arming behavior and Clarifications).
- The session expires (RF03/RF07's existing "Sessão expirada" overlay) while an insight attempt is in flight or a card is visible: the existing overlay behavior takes over exactly as it already does for the rest of the screen; an in-flight attempt is treated as failed (no card) the instant the session-expiry failure is received — the same immediate resolution RF04's own turn-failure handling already applies to `AuthExpiredFailure` — and the suspended trigger conditions resume normally from that point, independent of whether re-authentication has yet completed; an already-visible card is left exactly as it was.
- The user starts a brand-new conversation via "Novo Chat" (RF04) while viewing one that already has a visible/pending insight: that prior conversation's insight state is irrelevant to the new, empty conversation — the new conversation's counters start at zero, independently.
- The chat screen is offline for an extended period while a conversation is open and idle: the inactivity timer may still reach 2 minutes, but the resulting attempt is skipped exactly as in User Story 3's offline scenario — it is not queued to fire automatically once connectivity returns; the next natural crossing (next 2-minute window, or the next message once one can be sent) governs instead.
- The insight card itself is never eligible for RF10's "save as entry" bookmark control — RF10 already scopes its control to user messages only and explicitly excludes insight cards; this unit introduces no save action on the card either.
- Opening the side menu, My Records, search, export, the dashboard, the insertion modal, or any other screen or action not named in this feature: unaffected by this unit and not touched by it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For the chat session currently open and foregrounded on screen, the system MUST track two independent trigger conditions, each scoped to that single viewing session: (a) a count of user messages sent since the conversation was opened (or since the mechanism's counters were last reset), firing once every time that count reaches a new multiple of N = 5; (b) an inactivity timer measuring time since the last user message was sent (or since the counters were last reset) while the screen remains the active, foregrounded view, firing once when T = 2 minutes elapse with no new user message.
- **FR-002**: A fired trigger MUST call `POST /chat/sessions/:id/insight` with `triggerType` set to `message_count` or `inactivity` (matching whichever condition fired) and a `triggerKey` that uniquely identifies that specific occurrence within the session (e.g., which message-count crossing, or which idle window).
- **FR-003**: If a trigger condition becomes satisfied while the conversation's current turn is not idle (a response is streaming, or a message is in the error state awaiting retry per RF04), the system MUST defer the resulting insight attempt until that turn resolves, rather than attempting it concurrently or dropping it.
- **FR-004**: At most one insight attempt MUST be in flight, and at most one insight card MUST be awaiting dismissal, per conversation at any time. While either is true, both trigger conditions defined in FR-001 MUST be suspended — neither counted nor timed — resuming only once the in-flight attempt resolves (success, failure, or was skipped per FR-007) and any resulting card has been dismissed.
- **FR-005**: On a successful insight response (`status: 'ready'` with non-null `content`), the system MUST render a card interleaved in the message list at the point corresponding to when it was generated, carrying the generated text and a dismiss ("x") control, matching the prototype's "Tela 1 — Insight" treatment (ochre spine, "INSIGHT" label).
- **FR-006**: Any failure of an insight attempt — the HTTP call itself failing or timing out, or a successful call that resolves to `status: 'failed'` — MUST NOT produce any visible card or error indicator anywhere on screen, and MUST leave every other part of the chat screen (composer, scrolling, message history, other in-flight work) completely unaffected. The corresponding trigger condition MUST then be treated as resolved for that occurrence (no automatic retry of that specific occurrence).
- **FR-007**: If a trigger condition becomes satisfied while the device is offline, the system MUST NOT attempt the call, and MUST treat that occurrence identically to a failed attempt under FR-006 (no card, no indicator, no automatic retry once connectivity returns for that specific occurrence).
- **FR-008**: Dismissing a visible insight card (tapping "x") MUST be a local, client-only action — it MUST remove only that card from view, MUST NOT alter the scroll position or any other message's state, and MUST re-enable the trigger conditions suspended under FR-004 so a future occurrence of either can fire again normally.
- **FR-009**: Insight cards and their state (visible, dismissed, failed, or skipped) MUST NOT be persisted or reconstructed: leaving a conversation and returning (including after an app restart, or by switching to a different conversation and back via the side menu) MUST show no insight card carried over from an earlier viewing session, and the counters defined in FR-001 MUST restart at zero for the newly opened viewing session.
- **FR-010**: Switching away from a conversation's active, foregrounded view (backgrounding the app, opening the side menu, or navigating to a different conversation or screen) MUST pause that conversation's inactivity timer; it MUST resume counting from zero only once that same conversation becomes the active, foregrounded view again — time spent away never counts toward the 2-minute threshold.
- **FR-011**: This unit MUST NOT implement a save/bookmark action on insight cards (RF10 already excludes them), any UI for configuring or tuning the content or quality of the generated insight text, the "x" dismiss call as a backend request (no such endpoint exists), or any change to the backend, its API contract, or its configuration.

### Key Entities

- **Proactive Insight**: An ephemeral, client-side suggestion card tied to one chat session and one viewing of it — generated on demand by a satisfied trigger condition, carrying generated text content on success. It is never written to, or read back from, any backend store beyond the single request that created it; it exists only in the client's current view and leaves no trace once that view ends, whether or not it was dismissed.
- **Trigger Condition**: One of two independent, per-viewing-session counters defined for a chat session — a user-message count checked against multiples of 5, and an inactivity timer checked against 2 minutes — each producing at most one insight attempt per crossing, and both suspended while an insight attempt is in flight or its card awaits dismissal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a conversation where the user sends 5 messages without a 2-minute gap between them, exactly one insight attempt is made for that 5-message crossing, in 100% of tested cases, with zero duplicate attempts for the same crossing.
- **SC-002**: In a conversation left idle (no new user message) for 2 minutes while foregrounded, exactly one insight attempt is made for that idle window, in 100% of tested cases.
- **SC-003**: Across 100% of forced-failure and offline-trigger test scenarios, the rest of the chat screen (sending, scrolling, composer, other features) remains fully usable throughout and immediately afterward, with zero visible indicators tied to the failed or skipped attempt.
- **SC-004**: Dismissing a visible insight card changes nothing else observable on screen (scroll position, message order and content, composer state) in 100% of tested cases.
- **SC-005**: Across navigating away and back, switching conversations, and app restarts, zero insight cards from a prior viewing session ever reappear, in 100% of tested cases.
- **SC-006**: At every point measured across tested conversations, no conversation ever shows more than one insight card awaiting dismissal or has more than one insight attempt in flight at the same time.

## Assumptions

- The message-count trigger counts user messages sent since the current viewing session began, not the conversation's total historical message count — reopening a conversation that already has many messages from past sessions does not, by itself, immediately fire an insight; counting restarts cleanly for the new viewing session (see Clarifications).
- The exact construction of `triggerKey` (e.g., encoding the crossing number or an idle-window timestamp) is an implementation detail left to the planning phase, as long as it uniquely identifies the occurrence within that session's request.
- `POST /chat/sessions/:id/insight` is a synchronous call that resolves directly to `ready` or `failed` (per its own summary, "never an HTTP error"); any locally-rendered loading state during the call is a client-side placeholder (shown only if the call exceeds RNF01's 300 ms threshold), not a distinct `generating` value ever read back from a response.
- The response schema's `dismissed` status value and the request's general shape leave room for a future read/dismiss endpoint, but none exists today; this unit treats dismissal purely as local UI state and never attempts to report it to the backend.
- This unit depends on RF04 for: the composer/turn state machine used to determine when a conversation is "idle" (FR-003), the message list into which the card is interleaved (FR-005), and the existing connectivity detection already built for RF04's own offline handling (FR-007) — it introduces no separate offline-detection mechanism of its own.
- The quality, wording, tone, and prompt design of the generated insight text are explicitly out of scope, per RF08's own stated scope ("never the quality of the generated text") — this unit is tested only on when and whether an attempt happens and how its outcome is (or is deliberately not) shown, never on what the text says.
