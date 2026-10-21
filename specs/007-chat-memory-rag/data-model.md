# Data Model: P-RF04 — Interactive chat with memory (RAG)

Source: spec.md §Key Entities; requirements.md §§1 (RF04), 6.3, 8, 10, 13; `docs/input/backend/api/
openapi.yaml`'s `/chat/sessions*` schemas; `docs/input/backend/error-taxonomy.md`;
`docs/input/prototype/prototype-extract.md` §§2.2, 3, 4, 6. This is a new feature folder,
`lib/features/chat/`, depending on `core/network/*` (extended, R1/R8), `features/session/domain/repositories/
session_repository.dart` (unchanged, read-only reuse), and nothing from `entries/`/`records/` (chat never
touches the entries pipeline in this unit — FR-003/FR-014).

## `ChatPersona` / `ChatSession` (`lib/features/chat/domain/entities/chat_session.dart`) — NEW

```dart
enum ChatPersona { analitico, empatico, socratico }

class ChatSession extends Equatable {
  const ChatSession({
    required this.id,
    required this.title,
    required this.personaSnapshot,
    required this.userMessageCount,
    required this.lastUserMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ChatPersona personaSnapshot;   // read-only here (FR-014) — never written back
  final int userMessageCount;
  final DateTime? lastUserMessageAt;   // nullable per schema; in practice always non-null once listed (spec.md Key Entities)
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props =>
      [id, title, personaSnapshot, userMessageCount, lastUserMessageAt, createdAt, updatedAt];
}
```

Every field above is `required` in both `chat.sessions.create`'s and `chat.sessions.list`'s response schema
(openapi.yaml) — none is optional to model, mirroring `Entry`'s own precedent (RF01 data-model.md).

## `ChatRole` / `ChatMessageStatus` / `ChatMessage` (`lib/features/chat/domain/entities/chat_message.dart`) — NEW

```dart
enum ChatRole { user, assistant }
enum ChatMessageStatus { streaming, complete, failed }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.seq,
    required this.status,
    required this.retryCount,
    required this.createdAt,
  });

  final String id;           // `local-<timestamp>`-prefixed until reconciled (research.md R5)
  final String sessionId;
  final ChatRole role;
  final String content;      // grows incrementally while status == streaming (token deltas appended)
  final int seq;
  final ChatMessageStatus status;
  final int retryCount;
  final DateTime createdAt;

  bool get isOptimistic => id.startsWith('local-');

  @override
  List<Object?> get props => [id, sessionId, role, content, seq, status, retryCount, createdAt];
}
```

Matches `chat-messages-list`'s response schema field-for-field. `seq` for an optimistic placeholder (R5) is
set to `previousMessage.seq + 1` (or `0` for the very first message of a brand-new session) purely so the
list's existing sort-by-`seq` ordering holds before the server's own `seq` is known; it is overwritten once
real data arrives via `message_created`/`done` (R2) — the server is always the final authority on ordering.

**Status transitions** (FR-004):

```
(message sent/retried)
     │
     ▼
 streaming ──(done event)──► complete
     │
     └──(error event, DioException, or connection drop)──► failed
```

`complete` and `failed` are terminal for that specific turn; `failed` is the only state eligible for
`MessageRetryRequested`, which starts a **new** `streaming` message at the same list position (R10) rather
than mutating the failed one — `retryCount` increments on each such replacement, for the UI's own benefit
(not currently rendered anywhere, but captured since the server's response carries it).

## `ChatSessionsPage` (`lib/features/chat/domain/entities/chat_sessions_page.dart`) — NEW

```dart
class ChatSessionsPage extends Equatable {
  const ChatSessionsPage({required this.sessions, required this.nextCursor});

  final List<ChatSession> sessions;   // ordered by lastUserMessageAt desc (FR-008; backend-ordered — see contracts/chat-repository.md)
  final String? nextCursor;           // meta.nextCursor verbatim; null = last page

  @override
  List<Object?> get props => [sessions, nextCursor];
}
```

Directly mirrors `EntriesPage` (RF01/RF07) — same shape, same "null `nextCursor` = last page" convention.

## `ChatStreamEvent` (`lib/features/chat/domain/entities/chat_stream_event.dart`) — NEW

```dart
sealed class ChatStreamEvent extends Equatable {
  const ChatStreamEvent();
}

class MessageCreated extends ChatStreamEvent {
  const MessageCreated({required this.userMessageId, required this.assistantMessageId});
  final String userMessageId;
  final String assistantMessageId;
  @override List<Object?> get props => [userMessageId, assistantMessageId];
}

class ContextReceived extends ChatStreamEvent {
  const ContextReceived();
  @override List<Object?> get props => [];
}

class TokenReceived extends ChatStreamEvent {
  const TokenReceived(this.delta);
  final String delta;
  @override List<Object?> get props => [delta];
}

class StreamDone extends ChatStreamEvent {
  const StreamDone({required this.assistantMessageId, required this.content, required this.createdAt});
  final String assistantMessageId;
  final String content;
  final DateTime createdAt;
  @override List<Object?> get props => [assistantMessageId, content, createdAt];
}
```

No `ErrorEvent` variant — a business-level `error` SSE frame and a transport-level `DioException` both become
a `Left(Failure)` on the *same* `Stream<Either<Failure, ChatStreamEvent>>` (research.md R1/R2), so
`ChatBloc`/`ChatSessionsBloc` only ever need one failure-handling branch per stream, exactly like every other
`Either`-returning call in this codebase.

## `ChatTitleDeriver` (`lib/features/chat/domain/entities/chat_title_deriver.dart`) — NEW

```dart
class ChatTitleDeriver {
  const ChatTitleDeriver._();

  static const _maxLength = 48;

  /// Pure, total; never returns an empty string given a non-empty `firstMessageText`
  /// (research.md R6). No `package:flutter` import, no I/O.
  static String derive(String firstMessageText) {
    final collapsed = firstMessageText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= _maxLength) return collapsed;
    return '${collapsed.substring(0, _maxLength)}…';
  }
}
```

## `ChatRepository` (`lib/features/chat/domain/repositories/chat_repository.dart`) — NEW

```dart
abstract class ChatRepository {
  /// `POST /chat/sessions` (`chat-sessions-create`). Retries exactly once through
  /// `SessionRepository.refresh()` on `AuthExpiredFailure` (same shape as every other
  /// non-streaming call in this codebase).
  Future<Either<Failure, ChatSession>> createSession({required String title});

  /// `GET /chat/sessions` (`chat-sessions-list`), ordered by `lastUserMessageAt` desc (FR-008).
  Future<Either<Failure, ChatSessionsPage>> listSessions({String? cursor, int? limit});

  /// Every session returned by any successful [listSessions] call this process has made,
  /// backed by `ChatLocalCache` so it survives a restart (research.md R4) — the offline
  /// fallback `ChatSessionsBloc` reads when a fetch fails outright.
  List<ChatSession> get cachedSessions;

  /// `GET /chat/sessions/:id/messages` (`chat-messages-list`), ordered by `seq`.
  Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId);

  /// The last successfully-fetched message list for [sessionId], or `null` if this session's
  /// history has never been fetched while online (research.md R4/Clarification 3) — `null`
  /// is the signal `ChatBloc` uses to show the "standard no-connection state" instead of any
  /// content when selecting it while offline.
  List<ChatMessage>? cachedMessages(String sessionId);

  /// Persists which conversation to resume on next app open (spec.md Assumptions).
  Future<void> setLastActiveSessionId(String? sessionId);
  Future<String?> get lastActiveSessionId;

  /// `POST /chat/sessions/:id/messages` (`chat-messages-send`), SSE. Retries the whole call
  /// exactly once via `SessionRepository.refresh()` only if the very first emitted item is
  /// `AuthExpiredFailure` (research.md R3).
  Stream<Either<Failure, ChatStreamEvent>> sendMessage({
    required String sessionId,
    required String content,
  });

  /// `POST /chat/sessions/:id/messages/:userMessageId/retry` (`chat-messages-retry`), SSE.
  /// Same retry-once-if-first-frame-fails shape as [sendMessage] (research.md R3).
  Stream<Either<Failure, ChatStreamEvent>> retryMessage({
    required String sessionId,
    required String userMessageId,
  });
}
```

See `contracts/chat-repository.md` for `ChatRemoteDataSource`/`ChatRepositoryImpl`'s exact implementation and
the full SSE frame→event mapping.

## `SseFrame` / `ApiClient.sseStream` (`lib/core/network/sse_frame.dart`, extends `api_client.dart`) — NEW, shared

```dart
class SseFrame extends Equatable {
  const SseFrame({required this.event, required this.data});
  final String event;   // e.g. "message_created", "context", "token", "done", "error"
  final String data;    // raw JSON text, parsed by the caller (ChatRemoteDataSource) — ApiClient stays generic
  @override List<Object?> get props => [event, data];
}
```

```dart
class ApiClient {
  // ...existing call()...

  /// Generic SSE transport (research.md R1) — knows nothing about chat specifically. Never
  /// throws past this boundary, same guarantee as call(): a transport failure becomes the
  /// stream's one and only `Left(Failure)` item, then the stream closes.
  Stream<Either<Failure, SseFrame>> sseStream(
    String function, {
    required String method,
    Map<String, dynamic>? body,
    List<String>? pathSegments,
    AuthMode authMode = AuthMode.userSession,
  });
}
```

## `ChatLocalCache` (`lib/features/chat/data/chat_local_cache.dart`) — NEW

```dart
class ChatLocalCache {
  ChatLocalCache({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static const _sessionsKey = 'chatSessionsLocalCache';
  static const _messagesKey = 'chatMessagesLocalCache';
  static const _lastActiveKey = 'chatLastActiveSessionId';

  Future<List<ChatSession>> readSessions();
  Future<void> writeSessions(List<ChatSession> sessions);        // upsert-by-id merge, like EntriesLocalCache

  Future<Map<String, List<ChatMessage>>> readAllMessages();
  Future<void> writeMessagesForSession(String sessionId, List<ChatMessage> messages);  // replace-whole-list

  Future<String?> readLastActiveSessionId();
  Future<void> writeLastActiveSessionId(String? sessionId);
}
```

On-disk JSON shapes (research.md R4):

```jsonc
// key: chatSessionsLocalCache
[{"id": "...", "title": "...", "personaSnapshot": "analitico", "userMessageCount": 3,
  "lastUserMessageAt": "2026-10-19T12:00:00.000Z", "createdAt": "...", "updatedAt": "..."}, ...]

// key: chatMessagesLocalCache
{"<sessionId>": [{"id": "...", "sessionId": "...", "role": "user", "content": "...",
                  "seq": 0, "status": "complete", "retryCount": 0, "createdAt": "..."}, ...], ...}

// key: chatLastActiveSessionId
"<sessionId>"   // a bare JSON string, or the key is simply absent when no session exists yet
```

## `ChatRepositoryImpl` (`lib/features/chat/data/chat_repository_impl.dart`) — NEW

Wraps `ChatRemoteDataSource` + `ChatLocalCache` + `SessionRepository` (for the silent-refresh retry,
research.md R3) — same constructor shape as `EntriesRepositoryImpl`. `createSession`/`listSessions`/
`listMessages` each go through the existing `_retryAfterSilentRefresh` pattern verbatim; `sendMessage`/
`retryMessage` apply R3's "only if the first frame fails" variant. Every successful `listSessions`/
`listMessages` result is written through to `ChatLocalCache` before being returned (mirroring
`EntriesRepositoryImpl._cacheAndPersist`).

## `ChatEvent` / `ChatState` (`lib/features/chat/presentation/bloc/`) — NEW

| Event | When |
|---|---|
| `ChatStarted` | Dispatched once by `app_router.dart`'s `/home` route builder, right after `ChatBloc` is constructed — resumes `lastActiveSessionId`, or shows the empty state if none exists. |
| `ConversationSelected(String sessionId)` | Tapping a past conversation in the side menu (dispatched by `AppDrawer` to the shared `ChatBloc`, research.md R7). |
| `NewConversationRequested` | Tapping "Novo Chat" (same dispatch path). Drops `sessionId`/`messages`, shows the empty, ready-to-send state — no repository call (FR-010's "MUST NOT by itself create a session"). |
| `MessageSubmitted(String text)` | The composer's send tap. |
| `MessageRetryRequested(String userMessageId)` | Tapping a `failed` message bubble. |
| `_ConnectivityChanged(bool isOnline)` *(internal)* | Fired by the `ConnectivityChecker.onConnectivityChanged` subscription `ChatBloc` opens in its constructor (research.md R8). |

```dart
sealed class ChatState extends Equatable { const ChatState(); }

class ChatLoading extends ChatState { const ChatLoading(); }   // only while resuming lastActiveSessionId on ChatStarted

/// Everything else — an existing conversation, the empty "Novo Chat" state, or an outright
/// load failure with nothing cached to fall back to, are all one state shape so the screen
/// never has to discard/rebuild its `Scaffold`/`AppBar` switching between them.
class ChatReady extends ChatState {
  const ChatReady({
    required this.sessionId,            // null = empty conversation, no session created yet (FR-010)
    required this.messages,             // [] for an empty conversation
    required this.isOffline,
    required this.awaitingResponse,     // research.md R9 — gates the composer, true during a send/retry turn
    this.loadFailure,                   // set only when selecting an existing session's history failed outright
                                         // AND nothing is cached for it (Clarification 3's no-content edge case)
  });

  final String? sessionId;
  final List<ChatMessage> messages;
  final bool isOffline;
  final bool awaitingResponse;
  final Failure? loadFailure;

  bool get canSend => !isOffline && !awaitingResponse && loadFailure == null;

  @override
  List<Object?> get props => [sessionId, messages, isOffline, awaitingResponse, loadFailure];
}
```

`Stream<void> get reauthRequired` on `ChatBloc` — same one-shot-side-effect shape as `RecordsBloc`'s own
(research.md R3/R7; consumed by `HomeChatShellPage`, not `ChatBloc` itself).

See `contracts/chat-bloc.md` for the full handler-by-handler sequencing (lazy session creation, the
optimistic-placeholder append, `emit.forEach` over the SSE stream, retry's position-matching).

## `ChatSessionsEvent` / `ChatSessionsState` (`lib/features/chat/presentation/bloc/`) — NEW

Directly mirrors `RecordsEvent`/`RecordsState`'s own shape (RF07), narrowed to one bounded concern:

| Event | When |
|---|---|
| `SessionsStarted` | Dispatched once when `ChatSessionsBloc` is constructed (the drawer's very first open). |
| `SessionsRefreshRequested` | `Scaffold.onDrawerChanged(true)` on every subsequent open (research.md R7) — refetches page 1, keeps any already-loaded further pages' sessions merged in by id. |
| `SessionsNextPageRequested` | Scroll-to-bottom of the "CONVERSAS" section (FR-008). |
| `SessionsPageLoadRetried` | The inline retry affordance on a failed page-list fetch. |

```dart
sealed class ChatSessionsState extends Equatable { const ChatSessionsState(); }
class ChatSessionsLoading extends ChatSessionsState { const ChatSessionsLoading(); }
class ChatSessionsLoadFailure extends ChatSessionsState {
  const ChatSessionsLoadFailure(this.failure);
  final Failure failure;
  @override List<Object?> get props => [failure];
}
class ChatSessionsLoaded extends ChatSessionsState {
  const ChatSessionsLoaded({
    required this.sessions,
    required this.nextCursor,
    required this.isLoadingMore,
    this.pageLoadFailure,
  });
  final List<ChatSession> sessions;
  final String? nextCursor;
  final bool isLoadingMore;
  final Failure? pageLoadFailure;
  bool get hasReachedEnd => nextCursor == null;
  @override List<Object?> get props => [sessions, nextCursor, isLoadingMore, pageLoadFailure];
}
```

`Stream<void> get reauthRequired` here too — independent of `ChatBloc`'s own (two separate
`StreamController`s; `AppDrawer` listens to both and forwards each to the shared, app-wide `SessionBloc`).

## Widgets (`lib/features/chat/presentation/`) — new; `home/` — extended in place

- `lib/features/home/presentation/pages/home_chat_shell_page.dart` — **extended**. Wraps its `Scaffold` body
  with `BlocBuilder<ChatBloc, ChatState>`; the previously-inert `_ComposerBar` becomes `ChatComposer`
  (enabled per `ChatReady.canSend`); `Scaffold.onDrawerChanged` added, forwarding to `ChatSessionsBloc`
  (research.md R7). `ChatBloc`/`ChatSessionsBloc` are provided by the route builder in `app_router.dart`
  (`MultiBlocProvider`, replacing the current bare `const HomeChatShellPage()`), not inside this widget, same
  placement RF07 already uses for `RecordsBloc` on `AppRoutes.records`.
- `lib/features/home/presentation/widgets/app_drawer.dart` — **extended**, becomes a `StatefulWidget`. Adds
  the "CONVERSAS" section (`BlocBuilder<ChatSessionsBloc, ChatSessionsState>` + a `ListView`'s own
  `ScrollController`, same scroll-to-bottom-triggers-next-page shape `RecordsPage` already uses) above the
  existing "Meus Registros"/"Configurações" items, and a "Novo Chat" `ListTile` dispatching
  `NewConversationRequested` to `ChatBloc`. Each session row dispatches `ConversationSelected(session.id)` and
  closes the drawer.
- `lib/features/chat/presentation/widgets/chat_message_bubble.dart` — **NEW**. One widget, branching on
  `ChatMessage.role`/`status` (user vs. assistant bubble shape; `streaming` pulsing-cursor vs. `complete`
  timestamp vs. `failed` red "Falha ao gerar resposta — toque para tentar novamente" in place of the
  timestamp, tappable only when `failed`).
- `lib/features/chat/presentation/widgets/chat_composer.dart` — **NEW**, replaces `_ComposerBar`. Owns its own
  `TextEditingController` (never part of `ChatState` — research.md's own "composer text is local" choice,
  consistent with nothing being lost on any failure since it's simply never cleared except on a successful
  dispatch), `maxLength: 8000` (research.md R12), disabled per `ChatReady.canSend`.
- `lib/features/chat/presentation/widgets/chat_offline_banner.dart` — **NEW**. "Sem conexão — histórico
  disponível, novas mensagens bloqueadas" (prototype-extract.md §2.2), shown whenever `ChatReady.isOffline`.

**Token reuse** (prototype-extract.md §§3, 6 — no new token, Principle IV):

| Element | Token |
|---|---|
| User bubble | `DesignTokens.colorChatBubbleUser`, `radiusMd`, straight bottom-right corner |
| Assistant bubble | `DesignTokens.colorSurfaceElevated` + `elevation1`, `radiusMd`, straight bottom-left corner |
| Streaming cursor / failure text | `colorTextPrimary` (streaming) / `colorError` (failure), `textBodyMd` |
| Offline banner | `colorInfoOffline` background, `colorOnPrimary`-equivalent light text |
| Side menu section label ("CONVERSAS") | `textLabelMd` + `colorTextSecondary`, same as `AppDrawer`'s existing item styling |
| Composer send icon (enabled/disabled) | `colorPrimary` / `colorTextSecondary` — same pair `home_chat_shell_page.dart` already uses today |

## DI (`lib/core/di/service_locator.dart`) — additions

```dart
// Chat (P-RF04)
getIt.registerLazySingleton<ChatLocalCache>(ChatLocalCache.new);
getIt.registerLazySingleton<ChatRemoteDataSource>(() => ChatRemoteDataSource(getIt<ApiClient>()));
getIt.registerLazySingleton<ChatRepository>(() => ChatRepositoryImpl(
  getIt<ChatRemoteDataSource>(),
  sessionRepository: getIt<SessionRepository>(),
  localCache: getIt<ChatLocalCache>(),
));
getIt.registerFactory<ChatBloc>(() => ChatBloc(
  chatRepository: getIt<ChatRepository>(),
  connectivityChecker: getIt<ConnectivityChecker>(),
));
getIt.registerFactory<ChatSessionsBloc>(() => ChatSessionsBloc(chatRepository: getIt<ChatRepository>()));
```

`ConnectivityChecker` is already registered (RF01) — only its own class gains `onConnectivityChanged`
(research.md R8), no new registration.

## Routing (`lib/core/routing/app_router.dart`) — changed in place

```dart
GoRoute(
  path: AppRoutes.home,
  builder: (context, state) => MultiBlocProvider(
    providers: [
      BlocProvider<ChatBloc>(create: (_) => getIt<ChatBloc>()..add(const ChatStarted())),
      BlocProvider<ChatSessionsBloc>(create: (_) => getIt<ChatSessionsBloc>()),
    ],
    child: const HomeChatShellPage(),
  ),
),
```

`AppRoutes.home` itself is unchanged (`'/home'`, no parameter — research.md R7).
