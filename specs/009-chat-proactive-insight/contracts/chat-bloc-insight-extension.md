# Contract: `ChatBloc` insight-trigger extension

Source: spec.md §Requirements (FR-001–FR-010); data-model.md; research.md R1–R6, R10.

## New constructor parameter

```dart
Duration insightInactivityTimeout = const Duration(minutes: 2)
```

Production default is the fixed RF08 parameter (section 10 — "not to be reinterpreted"); tests pass a short
`Duration` purely for speed, the same seam `RecordsBloc.debounceDuration` already establishes for RF06.

## New events and their handlers

| Event | Handler | Core behavior |
|---|---|---|
| `ChatForegroundChanged(bool)` | `_onForegroundChanged` | Updates `_isForegrounded`; cancels the inactivity timer on `false`, re-arms it (fresh) on `true` if not suspended. |
| `InsightInactivityTimerFired(DateTime)` | `_onInsightInactivityTimerFired` | If no session yet, no-op (research.md R6). If the turn is idle, starts the attempt immediately. If not idle, defers it (`_pendingInsightTrigger`). |
| `InsightDismissed()` | `_onInsightDismissed` | Clears `ChatReady.insight`; re-arms the inactivity timer fresh. |

## Extended existing handlers

| Handler | Addition |
|---|---|
| `_onStarted` / `_onConversationSelected` / `_onNewConversationRequested` | `_resetInsightMechanism()` before emit; `_armInactivityTimer()` after. |
| `_onMessageSubmitted` | Message-count increment + crossing check (skipped while suspended); unconditional `_armInactivityTimer()` call right after. |
| `_consumeTurn` | `await _onTurnResolved(sessionId, emit)` after `_reconcileSilentFailure`, guarded by the existing `_turnGeneration` check. |
| `_failTurn` | Becomes `async`; calls `await _onTurnResolved(sessionId, emit)` after emitting the failure state. |
| `close()` | Cancels `_inactivityTimer`. |

## Invariants (SC-006, FR-004)

1. At most one `_chatRepository.createInsight` call is ever awaited at a time per `ChatBloc` instance
   (`_insightInFlight` guards re-entry; `_startInsightAttempt` is the only call site).
2. At most one `ChatReady.insight != null` at a time (a new attempt is only ever started once the previous
   card has been cleared — `_insightSuspended` blocks both counting and firing while it is non-null).
3. Message counting and the inactivity timer are both inert — no increment, no armed timer — for the entire
   span from "a trigger fired" through "its card (if any) has been dismissed, or it resolved without one."

## Test-scenario table

| # | Scenario | Setup | Expected outcome |
|---|---|---|---|
| 1 | 5th message fires once turn resolves | Send 5 messages, each turn completing normally; mock `createInsight` returns `Right('insight text')` | `createInsight` called exactly once, with `triggerType: messageCount`, `triggerKey: 'message_count:5'`, only after the 5th turn's `StreamDone`; emitted state carries `insight != null` |
| 2 | Re-arms at the next crossing | Continuing from #1, dismiss the card, send 5 more messages | `createInsight` called a 2nd time with `triggerKey: 'message_count:10'` |
| 3 | Deferred until turn idle | Message-count crossing lands on a message whose turn is still streaming when checked | `createInsight` is not called until `StreamDone`/failure resolves that turn; verified via call-order assertion |
| 4 | Inactivity fires after 2 min idle | `insightInactivityTimeout: Duration(milliseconds: 10)`; open a conversation with one prior message, wait | `createInsight` called once with `triggerType: inactivity` |
| 5 | Sending a message resets the inactivity window | Arm timer, send a message before it elapses | Original timer never fires; a new one starts from the send instant |
| 6 | Pause on background | Emit `ChatForegroundChanged(false)` before the timeout elapses | Timer never fires while backgrounded |
| 7 | Resume from zero, not from where it paused | `ChatForegroundChanged(false)` after 1.9 of 2 "minutes" (scaled), then `ChatForegroundChanged(true)` | A **new**, full-length timer starts — it does not fire after the remaining 0.1 |
| 8 | Suspended while a card is visible | Trigger fires, resolves to a card | No further `createInsight` call even after another 5 messages are sent / another timeout elapses, until `InsightDismissed` |
| 9 | Suspended while an attempt is in flight | Trigger fires; `createInsight` not yet resolved (pending `Future`) | A second, independently-satisfied trigger condition during that window produces no 2nd call |
| 10 | Failure → no card, immediate resume | `createInsight` resolves `Left(AiGenerationTimeoutFailure(...))` | State's `insight` stays/returns to `null`; the next crossing/timeout fires normally afterward |
| 11 | Offline → never attempted | `ConnectivityChecker.hasConnection()` returns `false` when a trigger condition is satisfied | `createInsight` never called; occurrence resolved exactly like #10 |
| 12 | Dismiss touches nothing else | A card is visible with other messages present | `InsightDismissed` → emitted state has `insight: null`, identical `messages`/`sessionId`/`isOffline`/`awaitingResponse`/`bookmarks` |
| 13 | New conversation discards a prior in-flight attempt | Trigger fires (attempt in flight) on session A; `ConversationSelected(B)` dispatched before it resolves | Once the stale call resolves, no state mutation occurs (generation guard); session B's own counters start at 0 |
| 14 | `AuthExpiredFailure` raises the overlay but still shows no card | `createInsight` resolves `Left(AuthExpiredFailure(...))` | `reauthRequired` emits; `insight` stays `null` |
| 15 | No session yet — inactivity is a no-op | Fresh "Novo Chat" (`sessionId == null`); timer fires | `createInsight` never called; timer stays disarmed until the first message is sent |
| 16 | Message count never double-counts a retry | Send 4 messages, let the 5th fail outright (`createSession`/turn failure), retry it | The retry does not increment `_insightMessageCount` a second time; the crossing still fires exactly once, at the correct message |

## Explicitly out of scope for this contract (per spec.md FR-011)

- No backend call for dismissal.
- No retry of a specific failed/skipped occurrence — only the *next* natural crossing/window tries again.
- No configuration UI for N=5/T=2min — both are compile-time constants.
