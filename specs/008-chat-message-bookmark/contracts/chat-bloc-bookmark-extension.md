# Contract: `ChatBloc` bookmark extension (`lib/features/chat/presentation/bloc/chat_bloc.dart`)

Extends `specs/007-chat-memory-rag/contracts/chat-bloc.md` — every existing handler (`ChatStarted`,
`ConversationSelected`, `NewConversationRequested`, `MessageSubmitted`, `MessageRetryRequested`,
`_ConnectivityChanged`) is unchanged in behavior; `_loadSession` gains one additional line per emit branch, and
one new event/handler is added.

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required ChatRepository chatRepository,
    required ConnectivityChecker connectivityChecker,
    required CreateEntryUseCase createEntryUseCase,   // NEW
  }) : _chatRepository = chatRepository,
       _connectivityChecker = connectivityChecker,
       _createEntryUseCase = createEntryUseCase,   // NEW
       super(const ChatLoading()) {
    on<ChatStarted>(_onStarted);
    on<ConversationSelected>(_onConversationSelected);
    on<NewConversationRequested>(_onNewConversationRequested);
    on<MessageSubmitted>(_onMessageSubmitted);
    on<MessageRetryRequested>(_onMessageRetryRequested);
    on<BookmarkTapped>(_onBookmarkTapped);   // NEW
    on<_ConnectivityChanged>(_onConnectivityChanged);
    // ...unchanged connectivity subscription...
  }

  final ChatRepository _chatRepository;
  final ConnectivityChecker _connectivityChecker;
  final CreateEntryUseCase _createEntryUseCase;   // NEW
  // ...unchanged _turnGeneration, _reauthController...
}
```

## `_loadSession` — one new line per emit branch

```dart
Future<void> _loadSession(String sessionId, Emitter<ChatState> emit, {required bool isOffline}) async {
  final result = await _chatRepository.listMessages(sessionId);
  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) _reauthController.add(null);
      final cached = _chatRepository.cachedMessages(sessionId);
      if (cached == null) {
        emit(ChatReady(
          sessionId: sessionId, messages: const [], isOffline: isOffline,
          awaitingResponse: false, loadFailure: failure,
        ));   // empty messages — bookmarks stays default {}
      } else {
        emit(ChatReady(
          sessionId: sessionId, messages: cached, isOffline: isOffline, awaitingResponse: false,
          bookmarks: _seedBookmarks(cached),   // NEW
        ));
      }
    },
    (messages) async {
      await _chatRepository.setLastActiveSessionId(sessionId);
      emit(ChatReady(
        sessionId: sessionId, messages: messages, isOffline: isOffline, awaitingResponse: false,
        bookmarks: _seedBookmarks(messages),   // NEW
      ));
    },
  );
}
```

`_seedBookmarks` is safe to call here specifically because `listMessages()` (just awaited, in both its
success and post-retry-failure paths) always awaits `ChatRepositoryImpl._ensureLocalCacheLoaded()` before
returning — see contracts/chat-repository-bookmark-extension.md's own note.

## `_seedBookmarks` — new private helper

```dart
Map<String, BookmarkStatus> _seedBookmarks(List<ChatMessage> messages) {
  final result = <String, BookmarkStatus>{};
  for (final m in messages) {
    if (m.role != ChatRole.user) continue;
    if (_chatRepository.savedEntryIdFor(m.id) != null) result[m.id] = BookmarkStatus.saved;
  }
  return result;
}
```

Pure given its two inputs (`messages`, `_chatRepository.savedEntryIdFor`'s current contents) — total, no
exceptions, directly unit-testable against a fake `ChatRepository` with no bloc/stream scaffolding.

## `BookmarkTapped` — new event, new handler

```dart
class BookmarkTapped extends ChatEvent {
  const BookmarkTapped(this.messageId);
  final String messageId;
  @override List<Object?> get props => [messageId];
}
```

```dart
Future<void> _onBookmarkTapped(BookmarkTapped event, Emitter<ChatState> emit) async {
  final current = state;
  if (current is! ChatReady) return;

  final index = current.messages.indexWhere((m) => m.id == event.messageId);
  if (index == -1) return;   // defensive — the event always originates from a currently-rendered message
  final message = current.messages[index];

  if (message.role != ChatRole.user) return;        // defensive — FR-001, UI never dispatches this for AI messages
  if (message.isOptimistic) return;                 // research.md R6 — real id not yet assigned

  final currentStatus = current.bookmarkStatusFor(message.id);
  if (currentStatus == BookmarkStatus.saving || currentStatus == BookmarkStatus.saved) {
    return;   // FR-007 (ignore while saving) / FR-003 (saved carries no tap handler — defensive double-check)
  }

  emit(current.copyWith(bookmarks: {...current.bookmarks, message.id: BookmarkStatus.saving}));

  final created = await _createEntryUseCase(
    message.content,
    EntrySource.chat,
    chatMessageId: message.id,
    occurredAt: message.createdAt,
  );

  final latest = state;
  if (latest is! ChatReady) return;   // the user navigated away mid-save (Edge Cases) — see note below

  await created.match(
    (failure) async {
      if (failure is AuthExpiredFailure) _reauthController.add(null);   // research.md R9
      emit(latest.copyWith(bookmarks: {...latest.bookmarks, message.id: BookmarkStatus.error}));
    },
    (entry) async {
      await _chatRepository.recordMessageSaved(chatMessageId: message.id, entryId: entry.id);
      final afterRecord = state;
      if (afterRecord is! ChatReady) return;
      emit(afterRecord.copyWith(bookmarks: {...afterRecord.bookmarks, message.id: BookmarkStatus.saved}));
    },
  );
}
```

- **No `_turnGeneration` involvement.** A bookmark save is an independent, single request/response per
  message — it neither starts nor is affected by a conversation's "turn" (send/retry), and FR-006 (a save must
  never block the rest of the screen) holds by construction: the handler touches only `bookmarks`, never
  `awaitingResponse`/`messages`.
- **Navigating away mid-save (Edge Cases).** If the user switches conversations while a save is in flight,
  `state` by the time `created` resolves may already be a *different* `ChatReady` (a new session's messages/
  bookmarks, loaded via `ConversationSelected`). The `latest is! ChatReady` guard only protects against a
  non-`ChatReady` state (e.g. mid-`ChatLoading`, which cannot actually happen here since nothing re-enters
  `ChatLoading` after the first `ChatStarted`); it does **not** guard against "wrong session." Merging the
  save's outcome into whatever `ChatReady` is current adds a harmless, unrendered key under the old message's
  id to the new session's `bookmarks` map (that message isn't in the new session's `messages`, so nothing
  displays it). When the user navigates back to the original conversation, `_loadSession` reruns and rebuilds
  `bookmarks` from scratch via `_seedBookmarks` — which by then reflects the save's real outcome correctly via
  `recordMessageSaved`'s already-persisted write (on success) or simply via the message resuming `idle`
  (on failure, since nothing is recorded for a failed save) — exactly the Edge Case's own requirement ("the
  bookmark reflects whatever the save ultimately resolved to... not a stale saving indicator").

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `_loadSession` resolves with 3 messages, one of which (`m2`, a user message) has `savedEntryIdFor('m2')` returning a non-null id | `ChatReady.bookmarks == {'m2': BookmarkStatus.saved}`; `m1`/`m3` (assistant, or unsaved user) are absent from the map, i.e. report `idle` via `bookmarkStatusFor` |
| 2 | `BookmarkTapped('m1')` where `m1` is an `idle` user message | `bookmarks['m1']` transitions `saving` → (on `Right(entry)`) `saved`; `_createEntryUseCase` called once with `(content, EntrySource.chat, chatMessageId: 'm1', occurredAt: m1.createdAt)`; `_chatRepository.recordMessageSaved(chatMessageId: 'm1', entryId: entry.id)` called once |
| 3 | `BookmarkTapped('m1')` where `_createEntryUseCase` resolves `Left(NetworkOfflineFailure(...))` | `bookmarks['m1']` transitions `saving` → `error`; `recordMessageSaved` is never called |
| 4 | `BookmarkTapped('m1')` where `_createEntryUseCase` resolves `Left(AuthExpiredFailure(...))` | `bookmarks['m1']` ends `error`; `reauthRequired` emits exactly one event |
| 5 | `BookmarkTapped('m1')` dispatched twice back-to-back before the first call resolves | `_createEntryUseCase` is called exactly once — the second dispatch is a no-op because `bookmarkStatusFor('m1')` is already `saving` by the time it's handled |
| 6 | `BookmarkTapped('m1')` where `m1`'s current `bookmarkStatusFor` is already `saved` | No-op — `_createEntryUseCase` never called |
| 7 | `BookmarkTapped(optimisticUserMessage.id)` (a `'local-...'`-id message, before `message_created` arrives) | No-op — `_createEntryUseCase` never called (research.md R6) |
| 8 | `BookmarkTapped(assistantMessage.id)` (defensive — UI never dispatches this, but the handler is exercised directly in a test) | No-op — `_createEntryUseCase` never called |
| 9 | `BookmarkTapped('m1')` in flight; a `ConversationSelected('other-session')` is dispatched before it resolves; the save then resolves `Right(entry)` | The now-current `ChatReady` (for `'other-session'`) is unaffected in any way a test would assert on (its own `messages` don't contain `'m1'`); `recordMessageSaved` is still called (the write itself is unconditional on which session is currently displayed) — confirms Edge Cases' "reflects whatever it ultimately resolved to" without asserting on the stray map key itself |
| 10 | A full `BookmarkTapped` → `Right` round trip, immediately followed by re-selecting the same `sessionId` via `ConversationSelected` (simulating navigate-away-and-back) | `_seedBookmarks` on the reload calls `savedEntryIdFor('m1')`, which now returns the `entryId` `recordMessageSaved` persisted — the reloaded `ChatReady.bookmarks['m1']` is `saved` |
