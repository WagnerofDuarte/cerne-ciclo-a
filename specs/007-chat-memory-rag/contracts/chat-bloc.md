# Contract: `ChatBloc` (`lib/features/chat/presentation/bloc/chat_bloc.dart`)

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({required ChatRepository chatRepository, required ConnectivityChecker connectivityChecker})
      : _chatRepository = chatRepository, // ignore: prefer_initializing_formals
        _connectivityChecker = connectivityChecker, // ignore: prefer_initializing_formals
        super(const ChatLoading()) {
    on<ChatStarted>(_onStarted);
    on<ConversationSelected>(_onConversationSelected);
    on<NewConversationRequested>(_onNewConversationRequested);
    on<MessageSubmitted>(_onMessageSubmitted);
    on<MessageRetryRequested>(_onMessageRetryRequested);
    on<_ConnectivityChanged>(_onConnectivityChanged);
    _connectivitySubscription = connectivityChecker.onConnectivityChanged.listen(
      (isOnline) => add(_ConnectivityChanged(isOnline)),
    );
  }

  final ChatRepository _chatRepository;
  final ConnectivityChecker _connectivityChecker;
  late final StreamSubscription<bool> _connectivitySubscription;
  final _reauthController = StreamController<void>.broadcast();
  int _turnGeneration = 0;   // guards against a resolved/superseded turn's late emit (defensive; see research.md R9)

  Stream<void> get reauthRequired => _reauthController.stream;
}
```

## `ChatStarted` — resume last session or show empty state

```dart
Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
  final isOnline = await _connectivityChecker.hasConnection();
  final lastId = await _chatRepository.lastActiveSessionId;
  if (lastId == null) {
    emit(ChatReady(sessionId: null, messages: const [], isOffline: !isOnline, awaitingResponse: false));
    return;
  }
  await _loadSession(lastId, emit, isOffline: !isOnline);
}
```

## `ConversationSelected` / `NewConversationRequested`

```dart
Future<void> _onConversationSelected(ConversationSelected event, Emitter<ChatState> emit) async {
  _turnGeneration++;   // invalidate any in-flight turn from the conversation being left (spec.md Edge Cases)
  final isOnline = await _connectivityChecker.hasConnection();
  await _loadSession(event.sessionId, emit, isOffline: !isOnline);
}

Future<void> _onNewConversationRequested(NewConversationRequested event, Emitter<ChatState> emit) async {
  _turnGeneration++;   // same rationale as above
  final current = state;
  final isOffline = current is ChatReady ? current.isOffline : false;
  await _chatRepository.setLastActiveSessionId(null);
  emit(ChatReady(sessionId: null, messages: const [], isOffline: isOffline, awaitingResponse: false));
}
```

Bumping `_turnGeneration` here (not just in `_onMessageSubmitted`/`_onMessageRetryRequested`) ensures `_consumeTurn`'s
`generation != _turnGeneration` guard also catches the case where the user navigates away from a conversation
mid-stream (spec.md Edge Cases: "the message reflects whatever the backend ultimately recorded... rather than
being stuck in a stale in-progress state") — without this, an abandoned turn's later `TokenReceived`/`StreamDone`/
`Left` items could still pass the guard and mutate whichever conversation's `ChatReady` state is current.

## `_loadSession` — the shared fetch-with-cache-fallback path (Clarification 3)

```dart
Future<void> _loadSession(String sessionId, Emitter<ChatState> emit, {required bool isOffline}) async {
  final result = await _chatRepository.listMessages(sessionId);
  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) _reauthController.add(null);
      final cached = _chatRepository.cachedMessages(sessionId);
      if (cached == null) {
        // Never opened while online — "the standard no-connection state instead of any content"
        // (Edge Cases) — only reachable here, never for the empty/no-session state above.
        emit(ChatReady(
          sessionId: sessionId, messages: const [], isOffline: isOffline,
          awaitingResponse: false, loadFailure: failure,
        ));
      } else {
        emit(ChatReady(sessionId: sessionId, messages: cached, isOffline: isOffline, awaitingResponse: false));
      }
    },
    (messages) async {
      await _chatRepository.setLastActiveSessionId(sessionId);
      emit(ChatReady(sessionId: sessionId, messages: messages, isOffline: isOffline, awaitingResponse: false));
    },
  );
}
```

## `MessageSubmitted` — lazy session creation + optimistic placeholders + `emit.forEach`

```dart
Future<void> _onMessageSubmitted(MessageSubmitted event, Emitter<ChatState> emit) async {
  final current = state;
  if (current is! ChatReady || !current.canSend) return;   // composer was disabled; defensive no-op

  if (!await _connectivityChecker.hasConnection()) {        // FR-012 — blocked client-side, never attempted
    return;   // composer's own isOffline flag (R8's live stream) will reflect this on its own shortly
  }

  final generation = ++_turnGeneration;
  final now = DateTime.now();
  final optimisticUser = ChatMessage(
    id: 'local-${now.microsecondsSinceEpoch}', sessionId: current.sessionId ?? '',
    role: ChatRole.user, content: event.text, seq: current.messages.length,
    status: ChatMessageStatus.complete, retryCount: 0, createdAt: now,
  );
  final optimisticAssistant = ChatMessage(
    id: 'local-${now.microsecondsSinceEpoch}-response', sessionId: current.sessionId ?? '',
    role: ChatRole.assistant, content: '', seq: current.messages.length + 1,
    status: ChatMessageStatus.streaming, retryCount: 0, createdAt: now,
  );
  emit(current.copyWith(
    messages: [...current.messages, optimisticUser, optimisticAssistant],
    awaitingResponse: true,
  ));

  String sessionId;
  if (current.sessionId == null) {
    final created = await _chatRepository.createSession(title: ChatTitleDeriver.derive(event.text));
    final maybeId = created.match((f) => null, (s) => s.id);
    if (maybeId == null) {
      if (generation != _turnGeneration) return;
      _failTurn(emit, created.getLeft().toNullable()!, optimisticUserId: optimisticUser.id, optimisticAssistantId: optimisticAssistant.id);
      return;
    }
    sessionId = maybeId;
    await _chatRepository.setLastActiveSessionId(sessionId);
  } else {
    sessionId = current.sessionId!;
  }

  final stream = _chatRepository.sendMessage(sessionId: sessionId, content: event.text);
  await _consumeTurn(
    stream, emit, generation: generation, sessionId: sessionId,
    optimisticUserId: optimisticUser.id, optimisticAssistantId: optimisticAssistant.id,
  );
}
```

## `MessageRetryRequested` — position-matched replacement (research.md R10)

```dart
Future<void> _onMessageRetryRequested(MessageRetryRequested event, Emitter<ChatState> emit) async {
  final current = state;
  if (current is! ChatReady || current.awaitingResponse || current.sessionId == null) return;
  final index = current.messages.indexWhere(
    (m) => m.role == ChatRole.assistant && m.status == ChatMessageStatus.failed &&
        _userMessageIdFor(current.messages, m) == event.userMessageId,
  );
  if (index == -1) return;
  if (!await _connectivityChecker.hasConnection()) return;   // FR-012

  final generation = ++_turnGeneration;
  final now = DateTime.now();
  final placeholder = ChatMessage(
    id: 'local-${now.microsecondsSinceEpoch}-retry', sessionId: current.sessionId!,
    role: ChatRole.assistant, content: '', seq: current.messages[index].seq,
    status: ChatMessageStatus.streaming, retryCount: current.messages[index].retryCount + 1,
    createdAt: now,
  );
  final updatedMessages = [...current.messages];
  updatedMessages[index] = placeholder;
  emit(current.copyWith(messages: updatedMessages, awaitingResponse: true));

  final stream = _chatRepository.retryMessage(sessionId: current.sessionId!, userMessageId: event.userMessageId);
  await _consumeTurn(
    stream, emit, generation: generation, sessionId: current.sessionId!,
    optimisticUserId: null, optimisticAssistantId: placeholder.id,
  );
}
```

## `_consumeTurn` — shared `emit.forEach`-driven stream consumption

```dart
Future<void> _consumeTurn(
  Stream<Either<Failure, ChatStreamEvent>> stream, Emitter<ChatState> emit, {
  required int generation, required String sessionId,
  required String? optimisticUserId, required String optimisticAssistantId,
}) async {
  var assistantId = optimisticAssistantId;
  await emit.forEach<Either<Failure, ChatStreamEvent>>(stream, onData: (result) {
    final latest = state;
    if (generation != _turnGeneration || latest is! ChatReady) return latest;   // superseded — ignore (defensive)

    return result.match(
      (failure) {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        return _applyFailure(latest, assistantId, failure);
      },
      (event) => switch (event) {
        MessageCreated() => () {
            assistantId = event.assistantMessageId;
            return _reconcileIds(latest, optimisticUserId, event.userMessageId, optimisticAssistantId, event.assistantMessageId);
          }(),
        ContextReceived() => latest,
        TokenReceived(delta: final d) => _appendToken(latest, assistantId, d),
        StreamDone(assistantMessageId: final id, content: final c, createdAt: final t) =>
          _completeMessage(latest, id, c, t).copyWith(awaitingResponse: false),
      },
    );
  });
}
```

- `_reconcileIds`/`_appendToken`/`_completeMessage`/`_applyFailure` are small, pure `ChatReady → ChatReady`
  helpers operating on `messages` by id/position — each total and independently unit-testable without any
  bloc/stream scaffolding.
- `_applyFailure` sets the matched message's `status` to `failed` (keeping whatever partial `content` had
  already accumulated — FR-005's "never remove, hide, or blank out a partial message") and
  `awaitingResponse: false`.
- `close()` additionally cancels `_connectivitySubscription` and closes `_reauthController` (same shape
  `RecordsBloc.close()` already has, plus the one new subscription).

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `ChatStarted` with no `lastActiveSessionId` stored | `ChatReady(sessionId: null, messages: [])` — no repository call beyond the one `lastActiveSessionId` read |
| 2 | `ChatStarted` with a stored id whose `listMessages` succeeds | `ChatReady(sessionId: ..., messages: [...])` |
| 3 | `ChatStarted` with a stored id whose `listMessages` fails and nothing is cached | `ChatReady(..., loadFailure: failure)` — the no-content edge case |
| 4 | `ChatStarted` with a stored id whose `listMessages` fails but a cache exists | `ChatReady(..., messages: <cached>)`, no `loadFailure` |
| 5 | `MessageSubmitted` on an empty conversation | optimistic user+assistant appended within the same synchronous `emit` (RNF01), *then* `createSession` is called with the derived title, *then* `sendMessage` |
| 6 | `MessageSubmitted` while offline | the composer was already disabled (`canSend == false`), so the handler is a no-op; confirms no repository call fires regardless |
| 7 | A full successful turn: `MessageCreated` → `TokenReceived` × N → `StreamDone` | the assistant message's `content` grows incrementally per token, then is replaced by `StreamDone.content` exactly, `status: complete`, `awaitingResponse: false` |
| 8 | A turn interrupted by `Left(NetworkOfflineFailure)` after 2 tokens | the assistant message keeps its 2-tokens-worth of partial content, `status: failed`, `awaitingResponse: false` (FR-005) |
| 9 | `MessageRetryRequested` on a `failed` message not at the end of the conversation (Edge Cases) | only that one message's position is replaced; every later message in `messages` is untouched |
| 10 | Two `MessageRetryRequested` dispatched back-to-back for the same message (simulating a double-tap before the composer visually disables) | the second dispatch is a no-op (`current.awaitingResponse` is already `true` from the first) |
| 11 | `NewConversationRequested` while a previous conversation has unsaved-to-disk messages in memory | the previous conversation's own cache entry (`ChatLocalCache`) is untouched — only `lastActiveSessionId` changes; reselecting it later still shows its full history |
| 12 | A `_ConnectivityChanged(false)` event arrives mid-turn (device goes offline while a response is streaming) | `isOffline` becomes `true` immediately; the in-flight turn is **not** aborted by this alone — it still resolves via whatever `sendMessage`'s own stream eventually yields (a real disconnect surfaces as its own `NetworkOfflineFailure` item from `ApiClient.sseStream`, not from this separate connectivity event) |
| 13 | `ConversationSelected`/`NewConversationRequested` dispatched while a turn is mid-stream for the conversation being left | the in-flight turn's later `TokenReceived`/`StreamDone`/`Left` items are ignored (generation mismatch) — the newly-loaded conversation's state is never mutated by the abandoned turn |
