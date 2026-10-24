---

description: "Task list for P-RF08 — Proactive insights (mechanism)"
---

# Tasks: P-RF08 — Proactive insights (mechanism)

**Input**: Design documents from `/specs/009-chat-proactive-insight/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included — this project's RNF07 (≥80% domain coverage) and RNF09 (Either + 15/15 error scenarios)
constitution standards, and quickstart.md's own automated-checks list, require them for every new/extended file.

**Organization**: Tasks are grouped by user story per spec.md's four priorities (US1/US2 = P1, US3/US4 = P2).
Foundational work (domain entities, repository/data-source extension, bloc event/state scaffolding, design
tokens) is shared by all four stories and lives in Phase 2, since FR-004's single suspension mechanism and the
one new `ChatReady.insight` field are inseparable from every story's acceptance criteria.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (message-count trigger), US2 (inactivity trigger), US3 (failure/offline invisibility), US4 (dismiss)
- Every file path below is exact — no new feature folder is created (plan.md's Project Structure)

## Path Conventions

Single Flutter app, Clean Architecture per `lib/features/<feature>/{domain,data,presentation}/`. This unit
touches only `lib/features/chat/`, `lib/features/home/presentation/pages/home_chat_shell_page.dart`, and
`lib/core/{design_tokens.dart,routing/app_router.dart}` — confirmed against the current tree (no `chat/domain/`
file besides `repositories/chat_repository.dart` and the existing `entities/` siblings needs touching beyond
what's listed).

---

## Phase 1: Setup

No setup required — this unit adds no dependency, no new feature folder, no new DI registration (plan.md
Technical Context/Scale-Scope). Proceed directly to Phase 2.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The domain value objects, repository/data-source extension, design tokens, and bloc event/state
scaffolding every one of the four user stories depends on.

**⚠️ CRITICAL**: No user-story task below can be completed (nor its test made to pass) until this phase is done.

- [X] T001 [P] Create `InsightTriggerType` enum, `InsightTrigger` (`Equatable`, `type`/`triggerKey` fields), and
  `InsightTriggerKeyBuilder` (static `forMessageCount(int count) => 'message_count:$count'` and
  `forInactivity(DateTime firedAt) => 'inactivity:${firedAt.toUtc().toIso8601String()}'`) in
  `lib/features/chat/domain/entities/insight_trigger.dart`, per data-model.md — no `package:flutter`, no
  `chat/data/` import (RNF06/Principle V)
- [X] T002 [P] Create `ProactiveInsight` (`Equatable`, `content` (`String`) and `anchorIndex` (`int`) fields) in
  `lib/features/chat/domain/entities/proactive_insight.dart`, per data-model.md — no `package:flutter`, no
  `chat/data/` import
- [X] T003 [P] Unit test `InsightTriggerKeyBuilder.forMessageCount`/`forInactivity` and `InsightTrigger` equality
  in `test/features/chat/domain/entities/insight_trigger_test.dart` (contributes to RNF07's domain-coverage
  target, research.md R2)
- [X] T004 [P] Unit test `ProactiveInsight` construction/equality in
  `test/features/chat/domain/entities/proactive_insight_test.dart`
- [X] T005 [P] Add the five new `DesignTokens` constants to `lib/core/design_tokens.dart`: `widthInsightSpine`
  (`3.0`), `spacingInsightPaddingLeft` (`20.0`), `spacingInsightPaddingVertical` (`14.0`),
  `spacingInsightHeaderGap` (`6.0`), `sizeInsightDismissIcon` (`14.0`) — exact prototype transcription, no
  rounding to the 4 dp grid (research.md R12, Constitution Principle IV)
- [X] T006 Add `Future<Either<Failure, String>> createInsight({required String sessionId, required
  InsightTriggerType triggerType, required String triggerKey})` to the abstract `ChatRepository` in
  `lib/features/chat/domain/repositories/chat_repository.dart` (data-model.md) — depends on T001
- [X] T007 Implement `ChatRemoteDataSource.createInsight` in `lib/features/chat/data/chat_remote_data_source.dart`:
  calls `chat-insight-create` via `POST`, body `{'triggerType': _wireTriggerType(triggerType), 'triggerKey':
  triggerKey}` (`_wireTriggerType`: `messageCount` → `'message_count'`, `inactivity` → `'inactivity'`); on
  success, `_parseInsightContent` returns `Right(content)` only when `status == 'ready'`, otherwise
  `Left(ErrorMapper.fromResponse({'code': data['errorCode'], 'message': 'Proactive insight generation failed',
  'requestId': data['id']}))`, and `Left(_malformedChatFailure)` on a caught `TypeError` (missing/wrong-typed
  `status`) — per data-model.md/contracts/chat-repository-insight-extension.md. Depends on T006
- [X] T008 Implement `ChatRepositoryImpl.createInsight` in `lib/features/chat/data/chat_repository_impl.dart` as
  a one-line wrap of the existing `_retryAfterSilentRefreshIfExpired` helper, forwarding to
  `_remoteDataSource.createInsight(...)` — no `ChatLocalCache` read or write of any kind (FR-009). Depends on T007
- [X] T009 [P] Contract tests for `ChatRemoteDataSource.createInsight`/`ChatRepositoryImpl.createInsight` in
  `test/features/chat/data/chat_remote_data_source_test.dart` and
  `test/features/chat/data/chat_repository_impl_test.dart`, covering
  contracts/chat-repository-insight-extension.md's full 9-row table verbatim: (1) success → `Right(content)`;
  (2) `status: 'failed'` with `errorCode: 'AI_GENERATION_TIMEOUT'` → `Left(AiGenerationTimeoutFailure)`; (3)
  `status: 'failed'` with `errorCode: null` → `Left(ValidationFailure)`; (4) missing `status` →
  `Left(_malformedChatFailure)` (`TypeError` caught); (5) timeout → `Left(NetworkTimeoutFailure)` unchanged; (6)
  no connection → `Left(NetworkOfflineFailure)` unchanged; (7) `AuthExpiredFailure` + successful silent refresh
  → `Right(content)` retried transparently; (8) `AuthExpiredFailure` + failed refresh →
  `Left(AuthExpiredFailure(message: 'Session could not be renewed', ...))`; (9) `ChatLocalCache` never called
  (`verifyNever`) for any outcome above. Depends on T007, T008
- [X] T010 Add `ChatForegroundChanged(bool isForegrounded)`, `InsightInactivityTimerFired(DateTime firedAt)`, and
  `InsightDismissed()` event classes (each `Equatable`, per data-model.md's exact field lists) to
  `lib/features/chat/presentation/bloc/chat_event.dart`
- [X] T011 Add the `insight` field (`ProactiveInsight?`, defaults to `null`) to `ChatReady` in
  `lib/features/chat/presentation/bloc/chat_state.dart`: constructor parameter, `copyWith(...)` gains
  `ProactiveInsight? insight` plus a `bool clearInsight = false` boolean flag (never the `_unset`-sentinel
  shape used for `loadFailure` — dismissal is a named, common operation), and `props` gains `insight`. Depends
  on T002
- [X] T012 Register the `insightInactivityTimeout` constructor parameter (`Duration`, default `const
  Duration(minutes: 2)` — the fixed RF08 parameter, never product-configurable per FR-011) on `ChatBloc` in
  `lib/features/chat/presentation/bloc/chat_bloc.dart`, plus the six private bookkeeping fields
  (`_insightMessageCount = 0`, `_insightInFlight = false`, `_pendingInsightTrigger` (`InsightTrigger?`),
  `_insightGeneration = 0`, `_isForegrounded = true`, `_inactivityTimer` (`Timer?`)) and the derived
  `_insightSuspended` getter (`_insightInFlight || _pendingInsightTrigger != null || (state is ChatReady &&
  (state as ChatReady).insight != null)`) — none of these six fields become part of `ChatState` (research.md
  R1/R5). Depends on T010, T011

**Checkpoint**: Domain entities, repository/data-source, tokens, and bloc scaffolding exist — user-story
handlers can now be implemented.

---

## Phase 3: User Story 1 - A suggestion appears after a burst of conversation, unasked (Priority: P1) 🎯 MVP

**Goal**: Sending the 5th (10th, 15th, ...) user message in a viewing session, once that message's turn is
idle, triggers exactly one `createInsight` call with `triggerType: message_count`, rendering a card on success.

**Independent Test**: Open a conversation, send 5 user messages letting each turn resolve, confirm the insight
call fires once after the 5th resolves and a card renders interleaved in the message list.

### Implementation for User Story 1

- [X] T013 [US1] In `_onMessageSubmitted` (`lib/features/chat/presentation/bloc/chat_bloc.dart`), immediately
  after building `optimisticUser`/`optimisticAssistant`, add: if `!_insightSuspended`, increment
  `_insightMessageCount`; if the new count is a multiple of 5, set `_pendingInsightTrigger` (only if currently
  `null`) to `InsightTrigger(type: InsightTriggerType.messageCount, triggerKey:
  InsightTriggerKeyBuilder.forMessageCount(_insightMessageCount))` — per research.md R3/R5. Depends on T012
- [X] T014 [US1] Implement `_startInsightAttempt(InsightTrigger trigger, {required String sessionId, required
  Emitter<ChatState> emit})` in `chat_bloc.dart`: cancel `_inactivityTimer`, clear `_pendingInsightTrigger`, set
  `_insightInFlight = true`, capture `anchorIndex = (state as ChatReady).messages.length`, pre-check
  `_connectivityChecker.hasConnection()` (offline → `_insightInFlight = false`, re-arm if generation still
  current, return — FR-007/research.md R8), else call `_chatRepository.createInsight(...)`, set
  `_insightInFlight = false`, bail if `generation != _insightGeneration` (stale) or `state` is no longer
  `ChatReady`, then on `Left` call `_reauthController.add(null)` if `AuthExpiredFailure` and re-arm the timer
  (no card, FR-006), on `Right(content)` emit `latest.copyWith(insight: ProactiveInsight(content: content,
  anchorIndex: anchorIndex))` — per data-model.md. Depends on T008, T013
- [X] T015 [US1] Implement `_onTurnResolved(String sessionId, Emitter<ChatState> emit)` in `chat_bloc.dart`: if
  `_pendingInsightTrigger != null` and the current state is `ChatReady` with `awaitingResponse == false`, call
  `await _startInsightAttempt(trigger, sessionId: sessionId, emit: emit)`; otherwise, if there was a pending
  trigger that resolved without a card and `!_insightSuspended`, re-arm the inactivity timer — per
  data-model.md. Depends on T014
- [X] T016 [US1] Wire `_onTurnResolved` into the turn-resolution paths in `chat_bloc.dart`: in `_consumeTurn`,
  after the existing `await _reconcileSilentFailure(emit, sessionId, assistantId, generation);` line, add `if
  (generation == _turnGeneration) await _onTurnResolved(sessionId, emit);` (guarded by the existing
  `_turnGeneration`, not `_insightGeneration` — research.md data-model.md); make `_failTurn` `async` and, after
  its existing `emit(_applyFailure(...))` line, add `await _onTurnResolved(sessionId, emit);`; update both call
  sites of `_failTurn` (`_onMessageSubmitted`'s and `_retryLazySessionCreation`'s lazy-`createSession`-failure
  branches) to `await _failTurn(...)`. Depends on T015
- [X] T017 [US1] Extend `_onStarted`, `_onConversationSelected`, and `_onNewConversationRequested` in
  `chat_bloc.dart` to call a new `_resetInsightMechanism()` helper (increments `_insightGeneration`, resets
  `_insightMessageCount = 0`, `_insightInFlight = false`, `_pendingInsightTrigger = null`, cancels
  `_inactivityTimer`) before emitting each handler's fresh `ChatReady` (which never passes `insight:`, so it
  defaults to `null`) — FR-009's "counters start fresh" moment. Depends on T012
- [X] T018 [P] [US1] Create `InsightCard` (`StatelessWidget`, `content`/`onDismiss` constructor params) in
  `lib/features/chat/presentation/widgets/insight_card.dart`: full-width card (no 82%-max-width bubble bound),
  3 dp ochre spine on the left edge (`Stack`+`Positioned`, `widthInsightSpine`, `colorAccent`), a header row
  with "INSIGHT" (`textMonoCaption.copyWith(color: colorAccent)`) and an `Icons.close` dismiss glyph
  (`sizeInsightDismissIcon`, `colorTextSecondary`, `onTap: onDismiss`), `spacingInsightHeaderGap` below the
  header, then the body text (`textBodyMd`, unmodified) — background `colorSurfaceElevated`, radius `radiusMd`,
  shadow `elevation1`, left padding `spacingInsightPaddingLeft`, right padding `spacingMd`, top/bottom padding
  `spacingInsightPaddingVertical` — per data-model.md/research.md R12. Depends on T005
- [X] T019 [US1] In `lib/features/home/presentation/pages/home_chat_shell_page.dart`'s `ListView.builder`, read
  `insight = chatReady?.insight`, set `itemCount = messages.length + (insight == null ? 0 : 1)`, and in
  `itemBuilder`: if `insight != null && index == insight.anchorIndex`, return `InsightCard(content:
  insight.content, onDismiss: () => context.read<ChatBloc>().add(const InsightDismissed()))`; otherwise map
  `index` to `messages[(insight != null && index > insight.anchorIndex) ? index - 1 : index]` and render the
  existing `ChatMessageBubble` unchanged — per data-model.md R11. Depends on T011, T018
- [X] T020 [P] [US1] `bloc_test` scenarios for `ChatBloc` User Story 1 in
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`, per contracts/chat-bloc-insight-extension.md
  rows 1–3, 16: (1) 5 messages each resolving normally → `createInsight` called exactly once with
  `triggerType: messageCount`, `triggerKey: 'message_count:5'`, only after the 5th turn's completion, emitted
  state has `insight != null`; (2) continuing from (1), dismiss then send 5 more → 2nd call with
  `triggerKey: 'message_count:10'`; (3) a message-count crossing landing on a message whose turn is still
  streaming defers the call until the turn resolves (call-order assertion); (16) sending 4 messages, letting
  the 5th fail outright and retrying it, does not double-count the retry — the crossing still fires exactly
  once at the correct message. Depends on T016, T017
- [X] T021 [P] [US1] Widget test for `InsightCard` rendering and dismiss-tap callback in
  `test/features/chat/presentation/widgets/insight_card_test.dart`. Depends on T018
- [X] T022 [US1] Widget test for `home_chat_shell_page.dart`'s insight-card interleaving (card renders at
  `anchorIndex`, surrounding messages render at the correct shifted indices, no change to scroll/composer) in
  `test/features/home/presentation/pages/home_chat_shell_page_test.dart`. Depends on T019

**Checkpoint**: User Story 1 is independently functional and testable — the message-count trigger fires,
defers correctly, and renders a card.

---

## Phase 4: User Story 2 - A suggestion appears after a quiet moment (Priority: P1)

**Goal**: 2 minutes of inactivity on a foregrounded conversation triggers exactly one `createInsight` call with
`triggerType: inactivity`; a new message resets the window; leaving the view pauses it.

**Independent Test**: Open a conversation, stay idle 2 minutes while foregrounded, confirm the insight call
fires with `triggerType: inactivity`.

### Implementation for User Story 2

- [X] T023 [US2] Implement `_armInactivityTimer()` in `chat_bloc.dart`: cancel any existing `_inactivityTimer`;
  if `!_isForegrounded || _insightSuspended`, return; otherwise start a fresh single-shot `Timer`
  (`_insightInactivityTimeout`) that dispatches `add(InsightInactivityTimerFired(DateTime.now()))` on elapse —
  the same `Timer`-dispatches-an-event pattern as `RecordsBloc`'s debounce (research.md R4). Depends on T012
- [X] T024 [US2] Implement `_onInsightInactivityTimerFired(InsightInactivityTimerFired event, Emitter<ChatState>
  emit)` in `chat_bloc.dart`: return immediately (no call, no re-arm) if `state` is not `ChatReady` or
  `sessionId == null` (research.md R6); return if `_insightSuspended` (defensive); otherwise build
  `InsightTrigger(type: InsightTriggerType.inactivity, triggerKey:
  InsightTriggerKeyBuilder.forInactivity(event.firedAt))` and, if `current.awaitingResponse`, set
  `_pendingInsightTrigger ??= trigger` and return (FR-003 deferral), else `await
  _startInsightAttempt(trigger, sessionId: current.sessionId!, emit: emit)`. Register this handler and
  `_onForegroundChanged`/`_onInsightDismissed` (T025/T026) via `on<...>()` in the constructor. Depends on T014,
  T023
- [X] T025 [US2] Implement `_onForegroundChanged(ChatForegroundChanged event, Emitter<ChatState> emit)` in
  `chat_bloc.dart`: set `_isForegrounded = event.isForegrounded`; if now `false`, cancel `_inactivityTimer` and
  return; if now `true`, call `_armInactivityTimer()` (FR-010 — always a fresh 2 minutes, never a resumed
  partial count). Depends on T023
- [X] T026 [US2] Implement `_onInsightDismissed(InsightDismissed event, Emitter<ChatState> emit)` in
  `chat_bloc.dart`: return if `state` is not `ChatReady` or `insight == null`; otherwise `emit(current.copyWith(
  clearInsight: true))` then `_armInactivityTimer()` (FR-004/FR-008 — suspension ends, fresh window starts).
  Depends on T023
- [X] T027 [US2] Call `_armInactivityTimer()` unconditionally at the end of `_onMessageSubmitted`'s existing
  body in `chat_bloc.dart`, right after the message-count check added in T013 — FR-001b's "time since last
  user message sent" resets the instant the message is dispatched, not when its turn resolves. Depends on T013,
  T023
- [X] T028 [US2] Extend `_onStarted`/`_onConversationSelected`/`_onNewConversationRequested` (already touched in
  T017) to call `_armInactivityTimer()` immediately after emitting the fresh `ChatReady`. Depends on T017, T023
- [X] T029 [US2] Add `_inactivityTimer?.cancel();` to `ChatBloc.close()` in `chat_bloc.dart`, alongside the
  existing subscription/controller cleanup. Depends on T012
- [X] T030 [US2] Mix `WidgetsBindingObserver` into `_HomeChatShellPageState`
  (`lib/features/home/presentation/pages/home_chat_shell_page.dart`): `WidgetsBinding.instance.addObserver(this)`
  in `initState`, `WidgetsBinding.instance.removeObserver(this)` in `dispose`, and
  `didChangeAppLifecycleState(AppLifecycleState state)` dispatching `context.read<ChatBloc>().add(
  ChatForegroundChanged(state == AppLifecycleState.resumed))` — mirrors `VaultLifecycleObserver`'s existing
  precedent (research.md R10). Depends on T010
- [X] T031 [US2] Add `final RouteObserver<PageRoute<void>> chatRouteObserver = RouteObserver<PageRoute<void>>();`
  as a top-level value in `lib/core/routing/app_router.dart`, and pass `observers: [chatRouteObserver]` to the
  existing `GoRouter(...)` constructor call
- [X] T032 [US2] Mix `RouteAware` into `_HomeChatShellPageState`: subscribe via `chatRouteObserver.subscribe(
  this, ModalRoute.of(context)! as PageRoute<void>)` in `didChangeDependencies`, unsubscribe via
  `chatRouteObserver.unsubscribe(this)` in `dispose`, and implement `didPushNext()` dispatching
  `ChatForegroundChanged(false)` and `didPopNext()` dispatching `ChatForegroundChanged(true)` — per research.md
  R10. Depends on T030, T031
- [X] T033 [US2] Add one line to `home_chat_shell_page.dart`'s existing `Scaffold.onDrawerChanged` callback:
  dispatch `context.read<ChatBloc>().add(ChatForegroundChanged(!isOpen))` (opening → `false`, closing → `true`)
  alongside its existing `SessionsRefreshRequested()` dispatch on open. Depends on T030
- [X] T034 [P] [US2] `bloc_test` scenarios for `ChatBloc` User Story 2 in
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`, per contracts/chat-bloc-insight-extension.md
  rows 4–7, 15: (4) with `insightInactivityTimeout: Duration(milliseconds: 10)` and one prior message,
  `createInsight` fires once with `triggerType: inactivity` after the timeout; (5) sending a message before the
  timeout elapses means the original timer never fires and a new one starts from the send instant; (6) emitting
  `ChatForegroundChanged(false)` before the timeout elapses means the timer never fires; (7) `
  ChatForegroundChanged(false)` after 90% of the configured duration has elapsed, then `
  ChatForegroundChanged(true)`, starts a brand-new full-length timer that does not fire after only the
  remaining 10%; (15) on a fresh "Novo Chat" (`sessionId == null`), the timer firing never calls `createInsight`
  and stays disarmed until the first message is sent. Depends on T024, T025, T026, T027, T028, T029
- [X] T035 [US2] Widget/integration test for the `WidgetsBindingObserver`/`RouteAware`/drawer wiring in
  `test/features/home/presentation/pages/home_chat_shell_page_test.dart`: dispatching an `AppLifecycleState`
  change, a drawer open/close, and a `didPushNext`/`didPopNext` pair each produce the expected
  `ChatForegroundChanged` event on the bloc. Depends on T030, T032, T033

**Checkpoint**: User Stories 1 AND 2 both work independently — message-count and inactivity triggers both fire
correctly, and the inactivity timer correctly pauses/resumes across backgrounding, drawer, and navigation.

---

## Phase 5: User Story 3 - A failed or blocked attempt never disrupts the conversation (Priority: P2)

**Goal**: Every failure cause (transport failure, `status: 'failed'`, offline) produces zero visible effect and
never permanently disables the mechanism for later crossings.

**Independent Test**: Force a trigger while offline, and separately force the insight call to fail while
online; confirm no card/indicator appears either way and the rest of the screen stays fully usable.

### Implementation for User Story 3

- [X] T036 [P] [US3] `bloc_test` scenarios for `ChatBloc` User Story 3 in
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`, per contracts/chat-bloc-insight-extension.md
  rows 8–11, 13–14: (8) a trigger that resolves to a visible card suspends the mechanism — no further
  `createInsight` call fires even after another 5 messages are sent or another timeout elapses, until
  `InsightDismissed`; (9) a second, independently-satisfied trigger condition while a `createInsight` call is
  still pending produces no 2nd call; (10) `createInsight` resolving `Left(AiGenerationTimeoutFailure(...))`
  leaves `insight` at/returning to `null`, and the next crossing/timeout fires normally afterward; (11)
  `ConnectivityChecker.hasConnection()` returning `false` when a trigger fires means `createInsight` is never
  called, and the occurrence resolves exactly like (10); (13) a trigger firing (attempt in flight) on session A
  followed by `ConversationSelected(B)` before it resolves means the stale call's eventual resolution causes no
  state mutation (generation guard), and session B's own counters start at 0; (14) `createInsight` resolving
  `Left(AuthExpiredFailure(...))` emits `reauthRequired` but `insight` stays `null`. Depends on T014, T017,
  T024

**Checkpoint**: User Stories 1, 2, AND 3 all work independently — failures and offline skips are fully
invisible and self-recovering, with no permanent disabling of the mechanism.

---

## Phase 6: User Story 4 - Dismissing a suggestion touches nothing else (Priority: P2)

**Goal**: Tapping a visible card's "x" removes only that card — no other state changes — and the mechanism
re-arms normally afterward, with no insight ever surviving a reopened viewing session.

**Independent Test**: Trigger a visible card, note scroll position, tap "x", confirm scroll position and every
other message/composer state are unchanged except the card's removal; reopen the conversation and confirm no
card reappears.

### Implementation for User Story 4

- [X] T037 [P] [US4] `bloc_test` scenario for `ChatBloc` User Story 4 in
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`, per contracts/chat-bloc-insight-extension.md row
  12: with a card visible and other messages present, dispatching `InsightDismissed` emits a state with
  `insight: null` and an otherwise byte-identical `messages`/`sessionId`/`isOffline`/`awaitingResponse`/
  `bookmarks`. Depends on T026
- [X] T038 [P] [US4] Widget test confirming tapping `InsightCard`'s dismiss control in the rendered
  `home_chat_shell_page.dart` tree removes only the card (scroll offset and other message widgets unchanged) in
  `test/features/home/presentation/pages/home_chat_shell_page_test.dart`. Depends on T019, T026
- [X] T039 [US4] Integration-level `bloc_test` confirming FR-009/SC-005: a dismissed or still-visible card never
  reappears after `_onConversationSelected`/`_onNewConversationRequested`/a fresh `ChatBloc` instance (app
  restart) re-emits `ChatReady`, and the message-count/inactivity counters have restarted at zero (sending 4
  messages after reopening does not fire a 5th-message crossing) — added to
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`. Depends on T017, T028

**Checkpoint**: All four user stories are independently functional. The full mechanism — trigger, suspend,
resolve, dismiss, never persist — works end to end.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Project-wide gates this unit must still satisfy once all four stories are implemented.

- [X] T040 [P] Run `test/architecture/no_bloc_imports_bloc_test.dart`, `test/architecture/domain_purity_test.dart`,
  and `test/architecture/no_cross_feature_data_imports_test.dart` against the extended `lib/features/chat/` and
  confirm all three pass unmodified (plan.md Testing section — no new bloc, no new flutter/data import in
  `chat/domain/`, no cross-feature boundary touched)
- [X] T041 Run `fvm flutter test --coverage` and confirm `lib/**/domain/**` stays ≥80% (RNF07), with
  `insight_trigger.dart`/`proactive_insight.dart` both contributing full coverage
- [ ] T042 Execute quickstart.md's manual validation scenarios 1–6 on a device/simulator (message-count fire,
  inactivity fire, pause/resume across backgrounding/drawer/navigation, failure/offline invisibility, dismiss
  isolation, no cross-session persistence)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: None — skipped (no setup needed).
- **Phase 2 (Foundational)**: No dependencies beyond the existing codebase — BLOCKS all user stories.
- **Phase 3 (US1)**: Depends on Phase 2 completion.
- **Phase 4 (US2)**: Depends on Phase 2 completion. Independent of US1's tasks, but both extend the same
  `_onMessageSubmitted`/`_onStarted` family of handlers (T013/T017 vs. T027/T028) — sequence US1 before US2 if
  worked by the same person to avoid merge friction on those shared methods; fully parallel-safe across two
  people since the touched call sites don't overlap statement-for-statement.
- **Phase 5 (US3)**: Depends on Phase 3 (T014, T017) and Phase 4 (T024) — US3's scenarios exercise the
  `_startInsightAttempt`/foreground machinery both stories build.
- **Phase 6 (US4)**: Depends on Phase 4 (T026) and Phase 3 (T019, T017, T028).
- **Phase 7 (Polish)**: Depends on all four user stories being complete.

### Within Each Phase

- Domain entities (T001–T002) before anything that imports them.
- Repository/data-source (T006–T009) before any bloc handler that calls `createInsight` (T014).
- Event/state scaffolding (T010–T012) before any handler implementation (T013+).
- Each user story's test tasks depend on that story's implementation tasks (tests are written against the
  finished handler per quickstart.md's "automated checks" ordering, since RF08 has no TDD mandate beyond RNF07/
  RNF09's coverage gates).

### Parallel Opportunities

- T001–T005 (domain entities + their tests + tokens) are all `[P]` — different files, no interdependency.
- T009 (data-layer contract tests) is `[P]` relative to T010–T012 (bloc scaffolding) — different files.
- T018 (`InsightCard` widget) is `[P]` relative to T013–T017 (bloc handler chain) — different files.
- T020, T021, T034, T036, T037, T038 are each `[P]` relative to their sibling test tasks in other phases once
  their own phase's implementation tasks are done — same test file (`chat_bloc_test.dart`) but added as
  independent `group`s/`blocTest` cases; coordinate to avoid edit conflicts if run concurrently by multiple
  people.

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Launch domain-entity creation and its tests together:
Task: "Create InsightTriggerType/InsightTrigger/InsightTriggerKeyBuilder in lib/features/chat/domain/entities/insight_trigger.dart"
Task: "Create ProactiveInsight in lib/features/chat/domain/entities/proactive_insight.dart"
Task: "Unit test insight_trigger.dart in test/features/chat/domain/entities/insight_trigger_test.dart"
Task: "Unit test proactive_insight.dart in test/features/chat/domain/entities/proactive_insight_test.dart"
Task: "Add five DesignTokens constants to lib/core/design_tokens.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (domain entities, repository/data-source, tokens, bloc scaffolding).
2. Complete Phase 3: User Story 1 (message-count trigger end to end, including `InsightCard` and interleaving).
3. **STOP and VALIDATE**: Run quickstart.md's automated checks for US1's files plus manual scenario 1.
4. Demo: send 5 messages, see a card appear.

### Incremental Delivery

1. Phase 2 → Foundation ready.
2. Phase 3 (US1) → message-count trigger demo-able.
3. Phase 4 (US2) → inactivity trigger + pause/resume demo-able; both P1 stories now complete.
4. Phase 5 (US3) → failure/offline invisibility verified; mechanism proven robust.
5. Phase 6 (US4) → dismiss isolation + no-persistence verified; all acceptance scenarios covered.
6. Phase 7 → architecture/coverage gates confirmed, manual quickstart run end to end.

### Parallel Team Strategy

With two developers after Phase 2 is done: Developer A takes US1 (T013–T022) and US3 (T036, which depends on
A's own T014/T017); Developer B takes US2 (T023–T035) and US4 (T037–T039, which depends on B's own T026).
Coordinate on `chat_bloc.dart` and `chat_bloc_test.dart` — both stories' handlers live in the same file, so
treat T013–T017 and T023–T029 as a single short sequential window before splitting off into each story's
independent test/widget work.

---

## Notes

- [P] tasks = different files, no dependencies.
- [Story] label maps task to specific user story for traceability.
- No task introduces a new `getIt` registration, a new bloc, or a new domain usecase — this unit's entire
  surface is the six files plan.md's Scale/Scope section names plus two new domain files and one new widget.
- The trigger parameters (N=5, T=2min) are hardcoded as literals (`% 5`, `const Duration(minutes: 2)`) per
  FR-011 — no task adds a Settings UI or config surface for either.
- Verify `fvm flutter test test/architecture/` passes after every bloc/domain change, not only at Phase 7 — the
  gate is cheap to re-run and catches an accidental `chat/data/` or `package:flutter` import in `insight_trigger.dart`/
  `proactive_insight.dart` immediately.
