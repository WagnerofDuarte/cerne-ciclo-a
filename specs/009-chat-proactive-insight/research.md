# Research: P-RF08 — Proactive insights (mechanism)

Phase 0 output. Each item is a reasonable technical decision made under Constitution Principle I ("where these
documents are silent, implementers MUST make a reasonable technical decision rather than block on
clarification"). None reopens spec.md's own already-resolved Clarifications (ephemeral-only state, re-arming/
suspension semantics, no failure indicator) — each item below fills in a mechanical detail those, the OpenAPI
contract, or the prototype extract leave open.

## R1 — Where does the trigger/suspension state machine live?

**Decision**: entirely inside `ChatBloc` as private fields and handlers — no new domain usecase, no new bloc,
no new repository beyond one extra method on the existing `ChatRepository`. Six private fields track the whole
mechanism: `_insightMessageCount` (int), `_insightInFlight` (bool), `_pendingInsightTrigger`
(`InsightTrigger?`), `_insightGeneration` (int), `_isForegrounded` (bool), `_inactivityTimer` (`Timer?`). None of
these are part of `ChatState` — only the single field the UI actually renders, `ChatReady.insight`
(`ProactiveInsight?`, the visible card), is state. A derived getter, `_insightSuspended`, folds "attempt in
flight", "a trigger is deferred awaiting turn-idle", and "a card is awaiting dismissal" into the one boolean
FR-004 treats as a single suspension condition.

**Rationale**: this is the identical judgment RF04's own `chat_bloc.dart` already makes for its entire turn
state machine (`_turnGeneration`, the optimistic-id reconciliation, `_consumeTurn`) — none of it lives in
`domain/`, because every piece is specific to exactly one screen's one flow and has no behavior worth testing
independent of `ChatBloc`'s own event sequence. `ChatReady` only carries fields the UI renders or that must
survive a `copyWith`/equality check in tests (RF10's `bookmarks` map is the precedent); the insight counters are
pure internal bookkeeping, the same tier as `_turnGeneration` itself, which has never been part of `ChatState`.

**Alternatives considered**: a dedicated `InsightTriggerBloc`/`InsightTriggerTracker` domain class holding the
counters — rejected: it would either need to duplicate `ChatBloc`'s own `awaitingResponse`/`sessionId`/
`messages.length` reads (to know when a turn is idle and where to anchor a card) or import `ChatBloc` directly,
which this codebase's "no BLoC imports another BLoC" convention (RF07's acceptance criterion) forbids for a
bloc, and which a plain domain class has no clean way to depend on either. A plain pure-Dart tracker that
`ChatBloc` calls into — rejected as unnecessary indirection: the only genuinely pure, reusable, worth-isolating
computation here is `triggerKey` construction (R2 below), which is factored out on its own; the rest
(suspension, deferral, re-arming) is pure orchestration of `ChatBloc`'s *own* already-private state, with no
separate testable contract beyond "did `ChatBloc` emit/call what the scenario says."

## R2 — `triggerKey` construction (FR-002; spec.md Assumptions flags this as a planning-phase detail)

**Decision**: a new, stateless domain entity, `InsightTriggerKeyBuilder`
(`lib/features/chat/domain/entities/insight_trigger.dart`), with two static methods:

```dart
static String forMessageCount(int count) => 'message_count:$count';
static String forInactivity(DateTime firedAt) => 'inactivity:${firedAt.toUtc().toIso8601String()}';
```

`count` is always the exact multiple of 5 just reached (5, 10, 15, ...); `firedAt` is `DateTime.now()` captured
the instant the inactivity timer fires. Both forms are globally unique within a session in practice (no two
message-count crossings share a count; no two inactivity timers fire at the same microsecond) and are at least
1 character, matching the OpenAPI field's `minLength: 1`.

**Rationale**: a pure, deterministic string formatter is exactly the kind of logic this codebase already
isolates into a standalone domain entity for direct unit testing without `bloc_test`/`mocktail` scaffolding —
the same tier as `ChatTitleDeriver`. Keeping it in `domain/` (not inlined in `ChatBloc`) means `InsightTrigger`
occurrences are testable in isolation and contributes to RNF07's domain-coverage target with a trivial,
high-value test.

**Alternatives considered**: a raw UUID or `DateTime.now().microsecondsSinceEpoch` for both trigger kinds —
rejected, it would satisfy uniqueness but throw away the human-readable "which crossing/which window" information
the field exists to carry (useful for backend-side debugging/analytics, per the OpenAPI field's own doc-comment
intent); encoding only the crossing number with no `message_count:`/`inactivity:` prefix — rejected, the prefix
costs nothing and makes a `triggerKey` self-describing in logs without having to cross-reference `triggerType`.

## R3 — Message-count trigger mechanics (FR-001a, FR-002, FR-004)

**Decision**: `_insightMessageCount` increments by exactly 1 inside `_onMessageSubmitted`, once, immediately
after the optimistic user/assistant messages are built — but only when `!_insightSuspended` at that moment
(skipped entirely while suspended, per FR-004's "not counted"). Immediately after incrementing, a single check,
`_insightMessageCount % 5 == 0`, decides whether this is a new crossing; if so,
`_pendingInsightTrigger = InsightTrigger(messageCount, InsightTriggerKeyBuilder.forMessageCount(count))` is set
(only if not already set — see R5). No separate "next threshold" variable is needed: because counting only
ever advances one message at a time and is paused for the entire suspension window every time a crossing fires,
the running count can never skip past a multiple of 5 without visiting it exactly once. `MessageRetryRequested`
and the lazy-session-creation retry path (`_retryLazySessionCreation`) never touch this counter — a retry
resends the same already-counted user message's content; it is not a new one.

**Rationale**: matches User Story 1's acceptance scenarios literally (5th message → fires once; 6th–10th →
fires again once at the 10th) using the simplest possible counter, with zero risk of double-counting a retry.

**Alternatives considered**: tracking a separate `_nextMessageThreshold` field (5, 10, 15, ...) compared with
`>=` — rejected as unnecessary: the modulo check is equivalent given the "exactly one message at a time while
not suspended" invariant above, and is one field smaller.

## R4 — Inactivity-timer mechanics (FR-001b, FR-010)

**Decision**: a single-shot `Timer` (`_inactivityTimer`), the same `Timer`-fires-an-`add(Event())` pattern
`RecordsBloc._debounceTimer`/`SearchDebounceElapsed` already establishes for RF06's 300 ms debounce. A new
constructor parameter, `Duration insightInactivityTimeout = const Duration(minutes: 2)` (mirroring
`RecordsBloc`'s own `debounceDuration` parameter byte-for-byte), is the fixed T = 2 min value in production and
an injectable seam for fast, deterministic `bloc_test` timing in tests — never a product-configurable value
(RF08's own "fixed value, not configurable" framing, section 10). `_armInactivityTimer()` cancels any existing
timer and, only if `_isForegrounded && !_insightSuspended`, starts a fresh one that dispatches
`InsightInactivityTimerFired(DateTime.now())` on elapse. It is called: (a) once right after every "conversation
just (re)opened" emission (`_onStarted`, `_onConversationSelected`, `_onNewConversationRequested`) — the
counters-start-fresh moment (FR-009); (b) unconditionally, right after the message-count check in
`_onMessageSubmitted` — FR-001b's "time since the last user message was sent" resets the instant the message is
dispatched, not when its turn resolves; (c) from `_onForegroundChanged` when regaining foreground; (d) from
`_onInsightDismissed` and from the failure/offline-skip branch of `_startInsightAttempt` — both are "suspension
just ended" moments: FR-010's literal "resume counting from zero" phrasing is implemented as a brand-new,
full-length timer, never a resumed partial count. `_startInsightAttempt` cancels the timer at its very start, so
it physically cannot fire again while an attempt is in flight or a card is visible.

**Rationale**: `RecordsBloc`'s debounce is the exact precedent for "a `Timer` that dispatches a bloc event,
with an injectable `Duration` for test speed" already shipped in this codebase — reusing the identical shape
means no new testing infrastructure (no `fake_async`/`clock` package) is needed; a test can simply pass
`insightInactivityTimeout: const Duration(milliseconds: 5)` and use `bloc_test`'s own `wait:` parameter, exactly
as `records_bloc_test.dart` already does for the search debounce.

**Alternatives considered**: `fake_async`'s `FakeAsync.run` to simulate 2 real minutes virtually without an
injectable `Duration` — rejected, it would be the first use of that package in this codebase for a problem
`RecordsBloc` already solved more simply; a `Stream.periodic` ticking every second with manual elapsed-time
bookkeeping — rejected as needless complexity for a single-shot 2-minute countdown with no visible progress
indicator to drive.

## R5 — One pending trigger at a time; the "generated at" anchor; the suspension getter

**Decision**: `_pendingInsightTrigger` is set only if currently `null` (first writer wins; see Edge Cases'
practical impossibility of a genuine double-fire given the composer already blocks a second message mid-turn
and a sent message always resets the inactivity timer, R4b). `_insightSuspended` is:

```dart
bool get _insightSuspended =>
    _insightInFlight ||
    _pendingInsightTrigger != null ||
    (state case ChatReady(insight: final i) when i != null => true, _ => false);
```

A deferred-but-not-yet-started trigger (`_pendingInsightTrigger != null`, turn not idle yet) is folded into
"suspended" even though no HTTP call has started — FR-004's umbrella language ("At most one insight attempt...
in flight, and at most one... awaiting dismissal... both conditions... suspended") is read as covering the
whole window from "a trigger fired" through "its outcome is fully resolved and any card dismissed," which this
single getter models as one continuous span with three sub-phases (deferred → in-flight → visible) rather than
three independently-toggled flags that could, by a bug, overlap or gap. The card's `anchorIndex` — "the point
corresponding to when it was generated" (FR-005) — is captured as `messages.length` the instant
`_startInsightAttempt` actually begins the call (after any FR-003 deferral has already resolved), not at the
moment the trigger condition was first satisfied; this means the card renders immediately after whatever turn
caused or most recently preceded the attempt, which is the reading that keeps "generated" tied to the actual
generation call rather than to an earlier, possibly long-deferred, detection moment.

**Rationale**: a single derived getter (not three independently-set booleans the rest of the bloc must
remember to keep in sync) makes "is the mechanism currently suspended" impossible to get out of sync with the
three states it's built from — every call site asks the one question FR-004 actually cares about.

**Alternatives considered**: an explicit three-value enum (`idle`, `deferred`, `inFlight`, `visible`) — rejected
as one more piece of state to keep consistent with the three fields that already exist for other reasons
(`_pendingInsightTrigger`'s own non-nullness already *is* the "deferred" signal); a boolean per phase, OR'd
together manually at each call site — rejected, exactly the duplication the single getter avoids.

## R6 — The null-session edge case (inactivity fires on a brand-new, message-less "Novo Chat")

**Decision**: `_onInsightInactivityTimerFired` returns immediately, with no call attempted and no re-arm, if
`current.sessionId == null`. The timer is left disarmed until `_onMessageSubmitted` next arms it (R4b) — i.e.,
until the first message is actually sent in that empty conversation.

**Rationale**: neither spec.md nor the prototype addresses an insight firing on a conversation with zero
messages — there is no session id for `POST /chat/sessions/:id/insight`'s required path parameter to target,
and no content for the backend to generate a suggestion from. Not re-arming (rather than re-arming to fire
again every 2 minutes, forever, on an idle empty screen) avoids an indefinitely-repeating no-op timer for a
state that can only ever resolve one way; FR-001b's own counters-reset points already re-arm it the instant a
first message makes the mechanism meaningful.

**Alternatives considered**: re-arming anyway so the timer "keeps trying" every 2 minutes — rejected as pure
waste (a `DateTime.now()` call and an event dispatch, repeated forever, for a condition that cannot change
without a message being sent, which already re-arms the timer by itself).

## R7 — `createInsight`'s repository/data-source shape; collapsing `status: 'failed'` into `Left`

**Decision**: `ChatRepository` gains exactly one new method:

```dart
Future<Either<Failure, String>> createInsight({
  required String sessionId,
  required InsightTriggerType triggerType,
  required String triggerKey,
});
```

`Right(content)` is the only success shape (`status: 'ready'`); `ChatRemoteDataSource.createInsight` maps a
`status: 'failed'` 200 response to `Left(ErrorMapper.fromResponse({'code': data['errorCode'], ...}))` — reusing
the *existing* code→`Failure` switch `ErrorMapper` already owns for every other endpoint's `{code, message,
requestId}` error body, adapted to this endpoint's differently-named `errorCode` field — rather than inventing a
second failure-mapping table. A genuine HTTP-layer failure (timeout, no connection, malformed JSON) is already
a `Left` by the time it reaches this method, via the same `ApiClient.call` path every other non-streaming
endpoint uses. `ChatRepositoryImpl.createInsight` is a one-line wrap of the *existing*
`_retryAfterSilentRefreshIfExpired` helper (R3's identical shape in 008-chat-message-bookmark/research.md,
itself unchanged here) — no local-cache interaction at all, since nothing about an insight is ever cached
(FR-009).

**Rationale**: FR-006 requires every failure cause (`status: 'failed'`, a timeout, a malformed response) to be
*indistinguishable* to the UI — collapsing `status: 'failed'` into the same `Either.Left` channel every other
failure already flows through means `ChatBloc`'s own handling code needs exactly one failure branch, not a
separate "business failure" vs. "transport failure" distinction that spec.md explicitly says never surfaces
differently. Reusing `ErrorMapper` (rather than a second switch) keeps the one place this codebase maps
`code → Failure` the only place that ever does.

**Alternatives considered**: a richer return type (e.g., an `InsightOutcome` sealed class with `Ready`/`Failed`
variants) threaded all the way to `ChatBloc` — rejected: `ChatBloc` never needs to distinguish *why* an attempt
failed (FR-006), so a type that preserves that distinction all the way to the bloc only to be immediately
discarded adds a type with no consumer; collapsing at the data-source boundary (where the raw distinction
naturally exists, in the response body) is the one place reducing it to a plain `Either<Failure, String>` costs
nothing a caller actually needs.

## R8 — No connectivity pre-check gate... except there is one, unlike RF10's bookmark (FR-007)

**Decision**: unlike the bookmark flow's deliberate no-pre-check (008-chat-message-bookmark/research.md R10),
`_startInsightAttempt` *does* pre-check `ConnectivityChecker.hasConnection()` before calling the repository —
the same pattern `_onMessageSubmitted`'s own FR-012 pre-check already uses for sending a message. If offline,
the call is never attempted; the occurrence is resolved exactly like a failure (R7) with no card, and (if
nothing else is suspending the mechanism) the timer is re-armed immediately.

**Rationale**: FR-007's wording is explicit and different from RF10's own failure-uniformity stance — "the
system MUST NOT attempt the call" when offline, as opposed to RF10's Acceptance Scenario, which describes
*attempting* a save while offline and watching it fail. RF08 has no visible state at all to transition through
(R9/Clarification 3's "no indicator of any kind"), so there is no `saving`-style affordance a skipped attempt
would need to pass through on its way to "resolved" — skipping outright is both literally what FR-007 asks for
and behaviorally identical to attempting-and-failing from the UI's perspective (R9 below).

**Alternatives considered**: no pre-check, relying on the HTTP call to fail naturally offline (RF10's own
approach) — rejected because it contradicts FR-007's specific wording for this unit, even though the visible
outcome would be identical either way.

## R9 — No generating/loading indicator for an insight attempt, ever

**Decision**: no UI state represents "an insight is currently being generated." The call is made, and either a
card appears (success) or nothing visibly changes (failure, skip, or deferral) — there is no intermediate
placeholder, spinner, or any other on-screen trace of the attempt while it is in flight, regardless of how long
it takes.

**Rationale**: the prototype's own state table (`prototype-extract.md` §2.2) documents exactly one insight-related
visual state — "Tela 1 — Insight," the finished card — with no "generating" state anywhere in its 9-state
insertion-modal inventory or its 8-state chat-screen inventory either. RF08's own defining acceptance criterion
is that the mechanism "never disrupts the conversation" and that a failure "keeps the main chat working
normally" — the composer, scrolling, and every other message stay fully interactive throughout an in-flight
attempt (nothing about FR-004's suspension blocks `canSend` or any other screen affordance), so there is nothing
on screen that is "waiting" for this call the way a user-initiated action's own `saving` spinner (RF10's
bookmark) is. RNF01's "network call over 300 ms shows a loading indicator" standard governs *user-initiated*
waits where the user is watching for a specific result of their own action; an unrequested, invisible-until-
successful background call has no such moment, and spec.md's Clarification 3 ("no indicator of any kind" for
every failure/skip cause) is only coherent if the in-flight phase is equally invisible — a visible "generating"
placeholder that silently vanishes on failure would itself be the disruption Clarification 3 rules out.

**Alternatives considered**: a RNF01-literal reading that renders a generic placeholder bubble past 300 ms,
removed silently on failure — rejected: nothing in the prototype models this state, it would introduce a UI
element with no acceptance criterion describing its appearance or removal, and it would contradict Clarification
3's spirit (a thing appearing and then un-appearing with no explanation is still a visible trace of the attempt,
even if brief).

## R10 — Foreground/background detection surface (FR-010)

**Decision**: one new `ChatForegroundChanged(bool isForegrounded)` event, dispatched from three independent
sources, all already present in `home_chat_shell_page.dart`/`app_router.dart` or added as the same kind of
small, established Flutter primitive this codebase already uses elsewhere:

1. **App-level backgrounding** — `_HomeChatShellPageState` adds `with WidgetsBindingObserver`
   (`VaultLifecycleObserver`'s own precedent, scoped locally here instead of wrapping the whole app, since only
   Home/Chat's own inactivity timer cares) and dispatches `isForegrounded: state == AppLifecycleState.resumed`
   from `didChangeAppLifecycleState` — every other `AppLifecycleState` (`inactive`, `paused`, `detached`,
   `hidden`) maps to `false`.
2. **Drawer open/close** — `home_chat_shell_page.dart`'s existing `Scaffold.onDrawerChanged` callback (already
   used to refresh `ChatSessionsBloc` on open) gains one more line: `isOpen` dispatches
   `ChatForegroundChanged(false)`; closing dispatches `ChatForegroundChanged(true)`.
3. **Pushing to Records/Settings and back** — a new `RouteObserver<PageRoute<void>>`
   (`chatRouteObserver`, `app_router.dart`, passed as `GoRouter(observers: [chatRouteObserver])`), with
   `_HomeChatShellPageState` additionally mixing in `RouteAware`, subscribing in `didChangeDependencies`, and
   dispatching `false`/`true` from `didPushNext`/`didPopNext`.

Switching to a *different conversation* (`ConversationSelected`) or starting a new one (`NewConversationRequested`)
is **not** routed through this event at all — both already fully reset the insight mechanism via
`_resetInsightMechanism()` (R1), which is a fresh start, not a pause/resume of the *same* counters (Edge Cases:
"that prior conversation's insight state is irrelevant to the new... conversation").

**Rationale**: `AppDrawer`'s own doc comment already states the drawer "never disposes Home/Chat's `State`
underneath," and `context.push(AppRoutes.records/settings)` (used by both drawer nav items) keeps the `/home`
route's page — and therefore its one `ChatBloc` instance — alive underneath go_router's own `Navigator`, exactly
the scenario FR-010 describes as "pause... resume... once that same conversation becomes the active,
foregrounded view again." A `RouteObserver` is the standard Flutter mechanism for exactly this "did another page
get pushed on top of me / did I come back to the top" question, and this codebase has no existing substitute for
it to reuse.

**Alternatives considered**: tearing down and recreating `ChatBloc` on every navigation away/back (so "resume" is
just "re-run `_onStarted`") — rejected: this is not how `app_router.dart` is structured today (`ChatBloc` is
created once per `/home` route entry, not per visit to Records/Settings), and changing that would be a much
larger, riskier restructuring for a unit whose depends-on list names RF04's *existing* composer/turn state
machine, not a rewrite of it; polling `WidgetsBinding.instance.lifecycleState` instead of observing — rejected,
strictly worse than the push-based observer pattern already used for lifecycle elsewhere in this codebase.

## R11 — Interleaving the card without touching `ChatMessage` (FR-005)

**Decision**: `ChatReady.insight` (`ProactiveInsight? {content, anchorIndex}`) stays a sibling of `messages`,
never folded into it. `home_chat_shell_page.dart`'s `ListView.builder` computes
`itemCount = messages.length + (insight == null ? 0 : 1)` and, in `itemBuilder`, renders the new `InsightCard`
widget when `index == insight.anchorIndex`, otherwise maps `index` back to the right `messages[...]` entry
(subtracting 1 once the card's own slot has been passed). This exactly mirrors how the prototype's own
simulation renders it — a single `sc-for` loop over one `messages` array where `msg.isInsight` is just one more
branch alongside `msg.isUser`/`msg.isAi` — while keeping the *real* `ChatMessage` type (which matches
`chat-messages-list`'s response schema field-for-field, data-model.md's RF04 precedent) free of a client-only,
never-backend-shaped concept, the identical reasoning RF10's own research.md R5 already used to keep
`BookmarkStatus` out of `ChatMessage` too.

**Rationale**: the prototype's one-list, item-type-switch structure is worth matching visually (a card really
does sit interleaved among messages, scrolling as part of the same list) without requiring a parallel
`ChatMessage`-shaped entity or a new sealed "timeline item" hierarchy — a single nullable sibling field plus
index arithmetic in the one widget that already owns the `ListView.builder` is the smallest change that
produces the same rendered result.

**Alternatives considered**: a sealed `ChatTimelineItem` hierarchy (`MessageItem`/`InsightItem`) computed as a
derived getter on `ChatReady` — rejected as a heavier abstraction for a list that, by FR-004, contains at most
one non-`ChatMessage` entry at any time; simpler to special-case that one slot directly in the widget that
already indexes into `messages` for bookmark/retry wiring.

## R12 — Design tokens for the insight card (RNF08/Principle IV)

**Decision**: transcribed directly from the prototype's own inline insight markup
(`docs/input/prototype/cerne-prototype.html`, the `msg.isInsight` branch): background `colorSurfaceElevated`,
16 dp radius (`radiusMd`), `elevation1` shadow — all three already exist and are reused verbatim. Five values
have no existing exact match on the 4 dp spacing scale and are added as new, element-specific tokens (the same
precedent R7 of 008-chat-message-bookmark/research.md already set): `widthInsightSpine = 3` (the left accent
bar), `spacingInsightPaddingLeft = 20`, `spacingInsightPaddingVertical = 14` (top/bottom card padding; right
padding reuses the existing `spacingMd = 16`), `spacingInsightHeaderGap = 6` (between the "INSIGHT"/✕ row and
the body text), `sizeInsightDismissIcon = 14`. The "INSIGHT" label reuses `textMonoCaption` unchanged except for
color (`.copyWith(color: colorAccent)` — the style's own font/size/letter-spacing already match the prototype's
`12px`/`.2px` exactly); the body text reuses `textBodyMd` with **no** override at all (`Karla`, `14px`, `20/14`
line height, `colorTextPrimary` all already match). The dismiss glyph (`ph-x`) maps to `Icons.close`, following
every prior unit's established Phosphor→Material substitution (RF10's own `ph-check`→`Icons.check`
precedent); its color reuses `colorTextSecondary`.

**Rationale**: two existing text styles already match the prototype's insight-card typography exactly with zero
modification — a rare case where no `copyWith` or new token is needed at all for text. The five new scalar
tokens cover the only values that are genuinely off-grid (3, 14, 20) or specific enough to this one element
(the dismiss icon's 14 dp, distinct from `sizeBookmarkIcon`'s 16 dp) to warrant their own name rather than an
approximation.

**Alternatives considered**: rounding 14 dp padding to `spacingMd` (16) and 3 dp spine to a hairline `1`
(`dividerThickness`) to avoid two new tokens — rejected, both are small but measurable, intentional deviations
from the prototype with no justification beyond "avoid adding a constant," the same reasoning RF10's R7 already
rejected for its own 6 dp gap.

## R13 — `chat-insight-create`'s place in RNF09's project-wide write-endpoint tally

**Decision**: this unit treats `POST /chat/sessions/:id/insight` as a genuine new write endpoint for RNF09
purposes and gives it its own full timeout/malformed-response/no-connection scenario coverage
(`contracts/chat-repository-insight-extension.md`), on top of (not instead of) the project's existing
cumulative tally — without asserting a specific final fraction (e.g., claiming this completes "15/15"), since
007-chat-memory-rag's own research notes that the tally completes "across RF05/RF08/RF09/RF10's own later
units" and `POST /export/summary` (RF05, not yet built) may also turn out to be counted.

**Rationale**: the endpoint is unambiguously a write (`POST`) with its own three ordinary transport-layer
failure modes (independent of its 200-response `status: 'failed'` business outcome, R7) — it must be tested for
all three regardless of how the project-wide arithmetic eventually totals, and this plan should not overclaim a
specific "Nth of 5" count it cannot verify against units not yet built.
