# Data Model: P-RF08 — Proactive insights (mechanism)

Source: spec.md §Key Entities/§Requirements; requirements.md §§1 (RF08), 6.3 (`chat-insight-create`), 9, 10
(fixed parameters), 13; `docs/input/backend/api/openapi.yaml`'s `/chat/sessions/{id}/insight` POST schema;
`docs/input/prototype/prototype-extract.md` §2.2 ("Tela 1 — Insight") and `cerne-prototype.html`'s own
`msg.isInsight` markup; `.specify/memory/constitution.md`. Extends one already-existing feature folder
(`lib/features/chat/`) and two `core/` files (`design_tokens.dart`, `routing/app_router.dart`) — no new feature
folder, no new DI registration (`createInsight` is reached through the already-registered `ChatRepository`).

## `InsightTriggerType` / `InsightTrigger` / `InsightTriggerKeyBuilder` (`lib/features/chat/domain/entities/insight_trigger.dart`) — NEW

```dart
/// FR-002's two trigger kinds. Wire-format mapping (`message_count`/
/// `inactivity`) lives in `ChatRemoteDataSource` only — this enum carries no
/// backend-shape knowledge (RNF06/Principle V).
enum InsightTriggerType { messageCount, inactivity }

/// One occurrence of a satisfied trigger condition — either about to be
/// attempted immediately, or deferred (FR-003) until the current turn
/// resolves. Equatable only for test convenience; never compared in
/// production logic beyond null-checks (research.md R5).
class InsightTrigger extends Equatable {
  const InsightTrigger({required this.type, required this.triggerKey});
  final InsightTriggerType type;
  final String triggerKey;
  @override
  List<Object?> get props => [type, triggerKey];
}

/// Pure, stateless `triggerKey` formatting (FR-002; research.md R2) — no
/// `package:flutter`, no network/storage access.
class InsightTriggerKeyBuilder {
  const InsightTriggerKeyBuilder._();
  static String forMessageCount(int count) => 'message_count:$count';
  static String forInactivity(DateTime firedAt) =>
      'inactivity:${firedAt.toUtc().toIso8601String()}';
}
```

## `ProactiveInsight` (`lib/features/chat/domain/entities/proactive_insight.dart`) — NEW

```dart
/// The single visible card at any one time (FR-004) — ephemeral, never
/// persisted or reconstructed (FR-009; spec.md Key Entities). `anchorIndex`
/// is `ChatReady.messages.length` captured the instant generation actually
/// started (research.md R5) — the slot `home_chat_shell_page.dart`'s
/// `ListView.builder` renders this card into, ahead of whatever message sat
/// at that index when the attempt began.
class ProactiveInsight extends Equatable {
  const ProactiveInsight({required this.content, required this.anchorIndex});
  final String content;
  final int anchorIndex;
  @override
  List<Object?> get props => [content, anchorIndex];
}
```

No `package:flutter`/`chat/data/` import on either new domain file (RNF06/Principle V).

## `ChatRepository`/`ChatRepositoryImpl`/`ChatRemoteDataSource` — EXTENDED

```dart
abstract class ChatRepository {
  // createSession / listSessions / cachedSessions / listMessages / cachedMessages /
  // setLastActiveSessionId / lastActiveSessionId / sendMessage / retryMessage /
  // savedEntryIdFor / recordMessageSaved — unchanged

  /// `POST /chat/sessions/:id/insight` (`chat-insight-create`). `Right(content)`
  /// only for `status: 'ready'`; every other outcome — a transport failure,
  /// or a 200 response with `status: 'failed'` — is `Left` (research.md R7).
  /// Retries once via `SessionRepository.refresh()` on `AuthExpiredFailure`,
  /// the same shape as every other non-streaming call (research.md R7).
  /// Never reads or writes any local cache — nothing about an insight is
  /// ever persisted (FR-009).
  Future<Either<Failure, String>> createInsight({
    required String sessionId,
    required InsightTriggerType triggerType,
    required String triggerKey,
  });
}
```

`ChatRemoteDataSource`:

```dart
Future<Either<Failure, String>> createInsight({
  required String sessionId,
  required InsightTriggerType triggerType,
  required String triggerKey,
}) async {
  final result = await _apiClient.call(
    'chat-insight-create',
    method: 'POST',
    pathSegments: [sessionId],
    body: {
      'triggerType': _wireTriggerType(triggerType),
      'triggerKey': triggerKey,
    },
  );
  return result.flatMap(_parseInsightContent);
}

String _wireTriggerType(InsightTriggerType type) => switch (type) {
  InsightTriggerType.messageCount => 'message_count',
  InsightTriggerType.inactivity => 'inactivity',
};

// research.md R7 — collapses the 200-response `status: 'failed'` outcome
// into the same `Left` channel every transport failure already uses.
Either<Failure, String> _parseInsightContent(Map<String, dynamic> data) {
  try {
    if (data['status'] as String? == 'ready') {
      return Right(data['content'] as String);
    }
    return Left(
      ErrorMapper.fromResponse({
        'code': data['errorCode'],
        'message': 'Proactive insight generation failed',
        'requestId': data['id'],
      }),
    );
  } on TypeError {
    return const Left(_malformedChatFailure);
  }
}
```

`ChatRepositoryImpl` (no local-cache field, no new constructor dependency — reuses the existing
`_retryAfterSilentRefreshIfExpired<T>` helper, FR-009's "never persisted" needing zero storage interaction):

```dart
@override
Future<Either<Failure, String>> createInsight({
  required String sessionId,
  required InsightTriggerType triggerType,
  required String triggerKey,
}) => _retryAfterSilentRefreshIfExpired(
  () => _remoteDataSource.createInsight(
    sessionId: sessionId,
    triggerType: triggerType,
    triggerKey: triggerKey,
  ),
);
```

See `contracts/chat-repository-insight-extension.md` for the full test-scenario table.

## `ChatEvent`/`ChatState`/`ChatBloc` — EXTENDED

New events:

| Event | When |
|---|---|
| `ChatForegroundChanged(bool isForegrounded)` | App backgrounded/resumed, drawer opened/closed, or Records/Settings pushed/popped (research.md R10) — all treated identically. |
| `InsightInactivityTimerFired(DateTime firedAt)` | The 2-minute single-shot `Timer` elapses (research.md R4). |
| `InsightDismissed()` | Tapping the card's "x" (FR-008). |

```dart
class ChatForegroundChanged extends ChatEvent {
  const ChatForegroundChanged(this.isForegrounded);
  final bool isForegrounded;
  @override List<Object?> get props => [isForegrounded];
}

class InsightInactivityTimerFired extends ChatEvent {
  const InsightInactivityTimerFired(this.firedAt);
  final DateTime firedAt;
  @override List<Object?> get props => [firedAt];
}

class InsightDismissed extends ChatEvent {
  const InsightDismissed();
}
```

`ChatReady` gains one new field:

```dart
class ChatReady extends ChatState {
  const ChatReady({
    required this.sessionId,
    required this.messages,
    required this.isOffline,
    required this.awaitingResponse,
    this.loadFailure,
    this.bookmarks = const {},
    this.insight,                      // NEW — ProactiveInsight?, null = no card visible
  });

  // ...existing fields...
  final ProactiveInsight? insight;

  // copyWith(...) gains `ProactiveInsight? insight` + `bool clearInsight = false`,
  // the same `clearSessionId`-style boolean-flag shape already used for `sessionId`
  // (never the `_unset`-sentinel shape used for `loadFailure`, since `insight`'s
  // "clear" case — dismissal — is a named, common operation, not a rare default-preserving one).
  // props gains `insight`.
}
```

`ChatBloc` gains one new constructor parameter (no new dependency — only a testability seam, research.md R4)
and three new handlers; it is otherwise unchanged in its dependency surface:

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required ChatRepository chatRepository,
    required ConnectivityChecker connectivityChecker,
    required CreateEntryUseCase createEntryUseCase,
    Duration insightInactivityTimeout = const Duration(minutes: 2),   // NEW
  }) : ... {
    // ...existing on<...> registrations...
    on<ChatForegroundChanged>(_onForegroundChanged);                 // NEW
    on<InsightInactivityTimerFired>(_onInsightInactivityTimerFired);  // NEW
    on<InsightDismissed>(_onInsightDismissed);                       // NEW
  }

  final Duration _insightInactivityTimeout;

  // Insight mechanism bookkeeping — private, never part of ChatState (research.md R1).
  int _insightMessageCount = 0;
  bool _insightInFlight = false;
  InsightTrigger? _pendingInsightTrigger;
  int _insightGeneration = 0;
  bool _isForegrounded = true;
  Timer? _inactivityTimer;

  bool get _insightSuspended =>
      _insightInFlight ||
      _pendingInsightTrigger != null ||
      (state case ChatReady(insight: final i) when i != null => true, _ => false);
}
```

Core helpers:

```dart
// Conversation (re)opened — FR-009's "counters start fresh" moment.
// Called from _onStarted / _onConversationSelected / _onNewConversationRequested,
// right before emitting the fresh ChatReady.
void _resetInsightMechanism() {
  _insightGeneration++;
  _insightMessageCount = 0;
  _insightInFlight = false;
  _pendingInsightTrigger = null;
  _inactivityTimer?.cancel();
}

void _armInactivityTimer() {
  _inactivityTimer?.cancel();
  if (!_isForegrounded || _insightSuspended) return;
  _inactivityTimer = Timer(
    _insightInactivityTimeout,
    () => add(InsightInactivityTimerFired(DateTime.now())),
  );
}

void _onForegroundChanged(ChatForegroundChanged event, Emitter<ChatState> emit) {
  _isForegrounded = event.isForegrounded;
  if (!_isForegrounded) {
    _inactivityTimer?.cancel();
    return;
  }
  _armInactivityTimer(); // FR-010 — always a fresh 2 minutes, never a resumed partial count
}

Future<void> _onInsightInactivityTimerFired(
  InsightInactivityTimerFired event,
  Emitter<ChatState> emit,
) async {
  final current = state;
  if (current is! ChatReady || current.sessionId == null) return; // research.md R6
  if (_insightSuspended) return; // defensive — the timer is cancelled the instant suspension begins
  final trigger = InsightTrigger(
    type: InsightTriggerType.inactivity,
    triggerKey: InsightTriggerKeyBuilder.forInactivity(event.firedAt),
  );
  if (current.awaitingResponse) {
    _pendingInsightTrigger ??= trigger; // FR-003 — defer until the turn resolves
    return;
  }
  await _startInsightAttempt(trigger, sessionId: current.sessionId!, emit: emit);
}

void _onInsightDismissed(InsightDismissed event, Emitter<ChatState> emit) {
  final current = state;
  if (current is! ChatReady || current.insight == null) return;
  emit(current.copyWith(clearInsight: true));
  _armInactivityTimer(); // FR-004/FR-008 — suspension ends, fresh window starts
}

Future<void> _startInsightAttempt(
  InsightTrigger trigger, {
  required String sessionId,
  required Emitter<ChatState> emit,
}) async {
  _inactivityTimer?.cancel();
  _pendingInsightTrigger = null;
  _insightInFlight = true;
  final generation = _insightGeneration;
  final anchorIndex = (state as ChatReady).messages.length;

  if (!await _connectivityChecker.hasConnection()) {
    _insightInFlight = false; // FR-007 — never attempted; resolved like a failure
    if (generation == _insightGeneration) _armInactivityTimer();
    return;
  }

  final result = await _chatRepository.createInsight(
    sessionId: sessionId,
    triggerType: trigger.type,
    triggerKey: trigger.triggerKey,
  );

  _insightInFlight = false;
  if (generation != _insightGeneration) return; // stale — conversation switched away mid-flight

  final latest = state;
  if (latest is! ChatReady) return;

  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) _reauthController.add(null);
      _armInactivityTimer(); // FR-006 — no card, no indicator; occurrence fully resolved
    },
    (content) => emit(
      latest.copyWith(insight: ProactiveInsight(content: content, anchorIndex: anchorIndex)),
    ),
  );
}

// Called once per turn resolution — the end of _consumeTurn (after
// _reconcileSilentFailure) and inside _failTurn, both now `Future<void>`.
Future<void> _onTurnResolved(String sessionId, Emitter<ChatState> emit) async {
  final hadPending = _pendingInsightTrigger != null;
  final trigger = _pendingInsightTrigger;
  if (trigger != null) {
    final current = state;
    if (current is ChatReady && !current.awaitingResponse) {
      await _startInsightAttempt(trigger, sessionId: sessionId, emit: emit);
    }
  }
  // Only re-arm here if a deferred trigger just finished resolving without a
  // card (failed/skipped) — a turn with no pending trigger leaves whatever
  // timer _onMessageSubmitted already armed at send-time alone (research.md R4).
  if (hadPending && !_insightSuspended) _armInactivityTimer();
}
```

Extensions to existing handlers:

- **`_onStarted` / `_onConversationSelected` / `_onNewConversationRequested`**: each calls
  `_resetInsightMechanism()` before emitting its fresh `ChatReady` (which never passes `insight:`, so it
  defaults to `null`), then `_armInactivityTimer()` right after.
- **`_onMessageSubmitted`**: immediately after building `optimisticUser`/`optimisticAssistant`, insert:
  ```dart
  if (!_insightSuspended) {
    _insightMessageCount++;
    if (_insightMessageCount % 5 == 0) {
      _pendingInsightTrigger ??= InsightTrigger(
        type: InsightTriggerType.messageCount,
        triggerKey: InsightTriggerKeyBuilder.forMessageCount(_insightMessageCount),
      );
    }
  }
  _armInactivityTimer(); // FR-001b — resets "time since last message sent" now
  ```
  then, at the point `_consumeTurn` is awaited (both the brand-new-session and existing-session branches),
  nothing else changes — `_consumeTurn` itself now calls `_onTurnResolved` internally (below).
- **`_consumeTurn`**: after the existing `await _reconcileSilentFailure(emit, sessionId, assistantId,
  generation);` line, add `if (generation == _turnGeneration) await _onTurnResolved(sessionId, emit);` (the
  existing `_turnGeneration` guard, not `_insightGeneration` — a stale/abandoned turn should not trigger a fresh
  insight attempt on behalf of a conversation no longer active).
- **`_failTurn`**: becomes `Future<void> _failTurn(...)`, and after its existing `emit(_applyFailure(...))`
  line, adds `await _onTurnResolved(sessionId, emit);` — both call sites (`_onMessageSubmitted`'s and
  `_retryLazySessionCreation`'s lazy-`createSession`-failure branches) are updated to `await _failTurn(...)`.
- **`close()`**: adds `_inactivityTimer?.cancel();` alongside the existing subscription/controller cleanup.

See `contracts/chat-bloc-insight-extension.md` for the full handler listing and test-scenario table.

## Widgets — `insight_card.dart` (NEW), `home_chat_shell_page.dart` (extended), `app_router.dart` (extended)

```dart
class InsightCard extends StatelessWidget {
  const InsightCard({required this.content, required this.onDismiss, super.key});
  final String content;
  final VoidCallback onDismiss;
}
```

Renders the prototype's exact markup — full-width (no 82%-max-width bound, unlike a message bubble), a 3 dp
ochre spine on the left edge via a `Stack`+`Positioned`, "INSIGHT" (`textMonoCaption.copyWith(colorAccent)`) and
a `Icons.close` dismiss glyph (`sizeInsightDismissIcon`, `colorTextSecondary`) on one row, the generated text
below (`textBodyMd`, unmodified) — see research.md R12 for the exact token mapping.

`home_chat_shell_page.dart`'s `ListView.builder`:

```dart
final insight = chatReady?.insight;
...
ListView.builder(
  itemCount: messages.length + (insight == null ? 0 : 1),
  itemBuilder: (context, index) {
    if (insight != null && index == insight.anchorIndex) {
      return InsightCard(
        content: insight.content,
        onDismiss: () => context.read<ChatBloc>().add(const InsightDismissed()),
      );
    }
    final messageIndex = (insight != null && index > insight.anchorIndex) ? index - 1 : index;
    final message = messages[messageIndex];
    return ChatMessageBubble(/* unchanged wiring */);
  },
)
```

`_HomeChatShellPageState` additionally mixes in `WidgetsBindingObserver, RouteAware` (research.md R10):

```dart
class _HomeChatShellPageState extends State<HomeChatShellPage>
    with WidgetsBindingObserver, RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ...existing _reauthSubscription wiring, unchanged...
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    chatRouteObserver.subscribe(this, ModalRoute.of(context)! as PageRoute<void>);
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    // ...existing _reauthSubscription.cancel(), unchanged...
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<ChatBloc>().add(ChatForegroundChanged(state == AppLifecycleState.resumed));
  }

  @override
  void didPushNext() => context.read<ChatBloc>().add(const ChatForegroundChanged(false));

  @override
  void didPopNext() => context.read<ChatBloc>().add(const ChatForegroundChanged(true));

  // Scaffold.onDrawerChanged gains one line:
  //   onDrawerChanged: (isOpen) {
  //     context.read<ChatBloc>().add(ChatForegroundChanged(!isOpen));
  //     if (isOpen) context.read<ChatSessionsBloc>().add(const SessionsRefreshRequested());
  //   },
}
```

`app_router.dart` gains one top-level value and one `GoRouter` constructor argument:

```dart
final RouteObserver<PageRoute<void>> chatRouteObserver = RouteObserver<PageRoute<void>>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  observers: [chatRouteObserver],   // NEW
  initialLocation: AppRoutes.splash,
  routes: [ /* unchanged */ ],
);
```

**Token additions** (research.md R12 — exact prototype values, Principle IV):

| Token | Value | Used for |
|---|---|---|
| `widthInsightSpine` | `3` (double, dp) | The left accent bar |
| `spacingInsightPaddingLeft` | `20` (double, dp) | Card's left padding (clears the spine) |
| `spacingInsightPaddingVertical` | `14` (double, dp) | Card's top/bottom padding |
| `spacingInsightHeaderGap` | `6` (double, dp) | Gap between the header row and the body text |
| `sizeInsightDismissIcon` | `14` (double, dp) | The "x" glyph's size |

**Token reuse** (no new color or text-style token needed):

| Element | Token |
|---|---|
| Card background | `DesignTokens.colorSurfaceElevated` |
| Card radius | `DesignTokens.radiusMd` |
| Card shadow | `DesignTokens.elevation1` |
| Card right padding | `DesignTokens.spacingMd` |
| Spine / "INSIGHT" label color | `DesignTokens.colorAccent` |
| "INSIGHT" label style | `DesignTokens.textMonoCaption` (font/size/letter-spacing already match; only `color` overridden) |
| Body text style | `DesignTokens.textBodyMd` (used unmodified) |
| Dismiss icon color | `DesignTokens.colorTextSecondary` |

## DI (`lib/core/di/service_locator.dart`) — unchanged

`ChatBloc`'s registration is untouched: `createInsight` is reached through the already-injected
`ChatRepository`, and `insightInactivityTimeout` is a constructor parameter with a production-correct default
that only tests ever override. No new `getIt` registration, no reordering.
