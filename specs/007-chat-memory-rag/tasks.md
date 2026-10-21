---

description: "Task list for P-RF04 — Interactive chat with memory (RAG)"
---

# Tasks: P-RF04 — Interactive chat with memory (RAG)

**Input**: Design documents from `/specs/007-chat-memory-rag/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. `plan.md`'s Constitution Check marks RNF07 (domain coverage ≥80%) and RNF09 (Either +
15/15 error scenarios) both "PASS (gate carried into tasks)", and every file under `contracts/` carries its own
"Test scenarios this contract owns" table plus `quickstart.md`'s "Automated checks" section — this is this
feature's own design material requesting test tasks, not an invented addition.

**Organization**: Tasks are grouped by user story (spec.md's five User Stories: P1, P1, P2, P2, P3). This
feature introduces one entirely new feature folder (`lib/features/chat/`, two blocs) plus two `core/network/`
extensions. Loading a conversation (resume-last / switch / new-empty) is needed by every single story — even
US4's "Novo Chat" and US5's offline browsing go through the same `_loadSession` path — so the shared
transport/data/repository layer and `ChatBloc`'s own "load a conversation" machinery are necessarily
Foundational; each User Story phase then adds that story's own handler bodies, widgets, and tests on top.

## Path Conventions

Single Flutter project (plan.md's "Project Type"): `lib/features/chat/{domain,data,presentation}/`, mirrored
under `test/features/chat/...`; two `core/network/` files extended in place; `lib/features/home/` extended in
place. No `backend/`/`frontend/` split, no `.env`/native project file touched, no change to
`docs/input/backend/api/openapi.yaml` (Constraints, FR-014).

---

## Phase 1: Setup

No setup tasks. `plan.md`'s "Primary Dependencies" is explicit — "No additions... reuses the full existing
stack" — and the Project Structure's "Structure Decision" already fixes every new file's location. Proceed
directly to Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the shared transport (`SseFrame`/`ApiClient.sseStream`, live connectivity), the domain entities,
the data layer (`ChatRemoteDataSource`/`ChatLocalCache`/`ChatRepositoryImpl`), and `ChatBloc`'s own
"resume/switch/new empty conversation" machinery (`ChatStarted`/`ConversationSelected`/
`NewConversationRequested`/`_loadSession`) that every user story's handlers build on top of.

**⚠️ CRITICAL**: No user story phase can begin until this phase is complete.

- [X] T001 [P] Create `lib/core/network/sse_frame.dart`: `class SseFrame extends Equatable` with `final String
  event` and `final String data` (raw JSON text, parsed by the caller — `ApiClient` itself stays generic),
  `props => [event, data]` (data-model.md, contracts/sse-transport-extension.md).

- [X] T002 Extend `lib/core/network/api_client.dart` with `Stream<Either<Failure, SseFrame>> sseStream(String
  function, {required String method, Map<String, dynamic>? body, List<String>? pathSegments, AuthMode authMode
  = AuthMode.userSession})` per contracts/sse-transport-extension.md: issues the request via
  `_dio.request<ResponseBody>(url, options: Options(method: ..., responseType: ResponseType.stream, headers:
  {'apikey': _anonKey, 'Authorization': 'Bearer $bearer'}))` (same header-building logic `call()` already
  uses); decodes each byte chunk as UTF-8 (`allowMalformed: true`) into a buffer and splits frames on the
  blank-line (`\n\n`) SSE delimiter, parsing `event:`/`data:` lines per frame (multiple consecutive `data:`
  lines joined with `\n`; any other SSE field ignored); yields `Right(SseFrame(...))` per parsed frame in
  arrival order; on `DioException`, yields **exactly one** `Left(_mapException(e))` — reusing the existing
  `_mapException` verbatim, no second failure-mapping implementation — as the stream's **last** item, then the
  stream closes (no further iteration of `response.data!.stream` after the exception). `call()` is unchanged.
  Depends on T001.

- [X] T003 Create `test/core/network/api_client_sse_test.dart` per contracts/sse-transport-extension.md's "Test
  scenarios this contract owns" table: scenario #1 (3 frames split across 2 byte chunks mid-frame — all 3 parsed
  correctly, no dropped/duplicated bytes across the boundary); #2 (a `DioException` with `type: connectionTimeout`
  thrown after 1 frame already yielded — exactly `Right(frame1)` then `Left(NetworkTimeoutFailure)` as the
  stream's last item); #3 (a `DioException` with no `response` at all — `Left(NetworkOfflineFailure)` as the
  final item); #4 (a frame containing only `event: context\ndata: {}` — yielded as an ordinary
  `Right(SseFrame(event: 'context', data: '{}'))`, since the generic transport never special-cases an event
  name); #5 (a multi-line `data:` field split across two consecutive `data:` lines — both joined with `\n` into
  one `SseFrame.data`). Mock the underlying `dio` stream response the same way `api_client_test.dart`'s existing
  `call()` tests already mock `Dio`. Depends on T002.

- [X] T004 [P] Add `Stream<bool> get onConnectivityChanged` to `lib/core/network/connectivity_checker.dart`
  (research.md R8): wraps `Connectivity().onConnectivityChanged`'s own broadcast stream, mapping "any result
  `!= ConnectivityResult.none`" → `true` — the exact same predicate `hasConnection()` already uses. The existing
  synchronous `hasConnection()` method is unchanged (R8's own write-path pre-check still calls it directly).

- [X] T005 [P] Create `lib/features/chat/domain/entities/chat_session.dart`: `enum ChatPersona { analitico,
  empatico, socratico }`; `class ChatSession extends Equatable` with `required` fields `id` (`String`), `title`
  (`String`), `personaSnapshot` (`ChatPersona` — read-only here, FR-014, never written back), `userMessageCount`
  (`int`), `lastUserMessageAt` (`DateTime?` — "nullable per schema; in practice always non-null once listed"),
  `createdAt`/`updatedAt` (`DateTime`); `props` over all seven fields (data-model.md).

- [X] T006 [P] Create `lib/features/chat/domain/entities/chat_message.dart`: `enum ChatRole { user, assistant
  }`; `enum ChatMessageStatus { streaming, complete, failed }`; `class ChatMessage extends Equatable` with
  `required` fields `id` (`String` — `'local-<timestamp>'`-prefixed until reconciled with the server's real id,
  research.md R5), `sessionId`, `role`, `content` (grows incrementally while `status == streaming`), `seq`
  (`int`), `status`, `retryCount` (`int`), `createdAt`; `bool get isOptimistic => id.startsWith('local-')`;
  `props` over `[id, sessionId, role, content, seq, status, retryCount, createdAt]` (data-model.md).

- [X] T007 [P] Create `lib/features/chat/domain/entities/chat_sessions_page.dart`: `class ChatSessionsPage
  extends Equatable` with `final List<ChatSession> sessions` and `final String? nextCursor` (`meta.nextCursor`
  verbatim; `null` = last page) — directly mirrors `EntriesPage`'s own shape. Depends on T005.

- [X] T008 [P] Create `lib/features/chat/domain/entities/chat_stream_event.dart`: `sealed class ChatStreamEvent
  extends Equatable`; `MessageCreated({required String userMessageId, required String assistantMessageId})`;
  `ContextReceived()` (no fields); `TokenReceived(String delta)`; `StreamDone({required String
  assistantMessageId, required String content, required DateTime createdAt})`. No `ErrorEvent` variant — both a
  business-level `error` SSE frame and a transport-level `DioException` become a `Left(Failure)` on the same
  `Stream<Either<Failure, ChatStreamEvent>>` (data-model.md, research.md R2).

- [X] T009 [P] Create `lib/features/chat/domain/entities/chat_title_deriver.dart`: `class ChatTitleDeriver`
  with a private constructor, `static const _maxLength = 48`, and `static String derive(String
  firstMessageText)` — collapses internal whitespace/newlines to single spaces via `replaceAll(RegExp(r'\s+'),
  ' ')`, trims, and when the result's length exceeds 48 returns `'${collapsed.substring(0, 48)}…'`, otherwise
  the collapsed string unchanged. Pure, total; never returns an empty string for non-empty input; no
  `package:flutter` import, no I/O (research.md R6, Principle V).

- [X] T010 Create `lib/features/chat/domain/repositories/chat_repository.dart`: abstract `ChatRepository` with
  `Future<Either<Failure, ChatSession>> createSession({required String title})`; `Future<Either<Failure,
  ChatSessionsPage>> listSessions({String? cursor, int? limit})`; `List<ChatSession> get cachedSessions`;
  `Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId)`; `List<ChatMessage>?
  cachedMessages(String sessionId)` (`null` = this session's history was never fetched while online); `Future<void>
  setLastActiveSessionId(String? sessionId)`; `Future<String?> get lastActiveSessionId`; `Stream<Either<Failure,
  ChatStreamEvent>> sendMessage({required String sessionId, required String content})`;
  `Stream<Either<Failure, ChatStreamEvent>> retryMessage({required String sessionId, required String
  userMessageId})` — exactly data-model.md's interface. Depends on T005, T006, T007, T008.

- [X] T011 [P] Create `lib/features/chat/data/chat_local_cache.dart` (research.md R4): Keychain-backed
  (`FlutterSecureStorage`, JSON-encoded, same pattern `EntriesLocalCache` already establishes), three
  **independent** storage keys so one write never clobbers another — `chatSessionsLocalCache` (a JSON array,
  upsert-by-id merge — `readSessions()`/`writeSessions(List<ChatSession>)`), `chatMessagesLocalCache` (a JSON
  object keyed by `sessionId`, replace-whole-list-per-session since `chat-messages-list` always returns the
  complete ordered history — `readAllMessages()` returning `Map<String, List<ChatMessage>>` /
  `writeMessagesForSession(String sessionId, List<ChatMessage> messages)`), `chatLastActiveSessionId` (a bare
  JSON string, or the key absent when no session exists yet — `readLastActiveSessionId()`/
  `writeLastActiveSessionId(String? sessionId)`). Depends on T005, T006.

- [X] T012 [P] Create `lib/features/chat/data/chat_remote_data_source.dart` per contracts/chat-repository.md:
  `ChatRemoteDataSource(this._apiClient)`; `createSession({required title})` → `_apiClient.call
  ('chat-sessions-create', method: 'POST', body: {'title': title})`; `listSessions({cursor, limit})` →
  `_apiClient.call('chat-sessions-list', method: 'GET', queryParameters: {'cursor': ?cursor, 'limit':
  ?limit?.toString()}, unwrapData: false)`; `listMessages(sessionId)` → `_apiClient.call('chat-messages-list',
  method: 'GET', pathSegments: [sessionId], unwrapData: false)`; `sendMessage({sessionId, content})` →
  `_apiClient.sseStream('chat-messages-send', method: 'POST', pathSegments: [sessionId], body: {'content':
  content})`; `retryMessage({sessionId, userMessageId})` → `_apiClient.sseStream('chat-messages-retry', method:
  'POST', pathSegments: [sessionId, userMessageId], body: const {})`; both streaming methods piped through a
  `_mapFrame` helper mapping `message_created` → `Right(MessageCreated(...))`, `context` → `null` (filtered
  out, ignored per research.md R2), `token` → `Right(TokenReceived(decoded['delta']))`, `done` →
  `Right(StreamDone(...))`, the backend-named `error` event → `Left(ErrorMapper.fromResponse(decoded))` (same
  error envelope `{code, message, retryable}` every other endpoint already uses), any unrecognized event name →
  `null` (forward-compatible, never thrown); `_parseSession`/`_parseSessionsPage`/`_parseMessagesList` field-
  for-field against `ChatSession`/`ChatMessage`, same `try`/`on TypeError`/`on FormatException` shape
  `entries_remote_data_source.dart`'s `_parseEntry`/`_parseEntriesPage` already use. Depends on T001, T002,
  T005, T006, T007, T008.

- [X] T013 Create `lib/features/chat/data/chat_repository_impl.dart` implementing `ChatRepository`, per
  contracts/chat-repository.md: constructor `(this._remoteDataSource, {required this._sessionRepository,
  required this._localCache})`; `_ensureLocalCacheLoaded()` lazily loads `_cachedSessions`/`_cachedMessages`
  from `ChatLocalCache` exactly once per process; `createSession`/`listSessions`/`listMessages` each go through
  `_retryAfterSilentRefreshIfExpired` (exactly one retry on `AuthExpiredFailure`, identical shape to
  `EntriesRepositoryImpl._retryAfterSilentRefresh`) and write successful results through to `ChatLocalCache`
  (`_upsertSession` for sessions; replace-whole-list for a session's messages); `cachedSessions`/
  `cachedMessages(sessionId)` read the in-memory maps (unmodifiable list for the former); `setLastActiveSessionId`/
  `lastActiveSessionId` delegate straight to the cache; `sendMessage`/`retryMessage` wrap `_streamWithAuthRetry`
  (research.md R3 — retries the **whole call** exactly once, only when the very first stream item is
  `Left(AuthExpiredFailure)`, i.e. before any `ChatStreamEvent` was ever emitted; once any event has been
  emitted, a later `AuthExpiredFailure` is yielded as-is, no retry attempted). Depends on T010, T011, T012.

- [X] T014 [P] Create `lib/features/chat/presentation/bloc/chat_event.dart`: `sealed class ChatEvent`;
  `ChatStarted()`; `ConversationSelected(String sessionId)`; `NewConversationRequested()`;
  `MessageSubmitted(String text)`; `MessageRetryRequested(String userMessageId)`; internal
  `_ConnectivityChanged(bool isOnline)` (data-model.md's event table).

- [X] T015 [P] Create `lib/features/chat/presentation/bloc/chat_state.dart`: `sealed class ChatState`;
  `ChatLoading()` (only while resuming `lastActiveSessionId` on `ChatStarted`); `ChatReady` with `required`
  fields `sessionId` (`String?` — `null` = empty conversation, no session created yet), `messages`
  (`List<ChatMessage>`), `isOffline` (`bool`), `awaitingResponse` (`bool`), and nullable `loadFailure`
  (`Failure?` — set only when selecting an existing session's history failed outright **and** nothing is
  cached for it); `bool get canSend => !isOffline && !awaitingResponse && loadFailure == null`; a
  `copyWith(...)` covering every field. Depends on T006.

- [X] T016 Create `lib/features/chat/presentation/bloc/chat_bloc.dart` (skeleton + "load a conversation"
  machinery) per contracts/chat-bloc.md: constructor `({required ChatRepository chatRepository, required
  ConnectivityChecker connectivityChecker})`, `super(const ChatLoading())`; registers all six `on<...>()`
  handlers (`MessageSubmitted`/`MessageRetryRequested` as stub no-op bodies for now, implemented in US1/US3);
  subscribes to `connectivityChecker.onConnectivityChanged` in the constructor, dispatching
  `_ConnectivityChanged`; `_onStarted` (resumes `lastActiveSessionId` via `_loadSession`, or emits the empty
  `ChatReady(sessionId: null, messages: const [], ...)` state when none is stored);
  `_onConversationSelected`/`_onNewConversationRequested` (the latter calls `setLastActiveSessionId(null)` and
  emits the empty state without discarding any other conversation, FR-010); the shared `_loadSession(sessionId,
  emit, {required isOffline})` helper — on a failed `listMessages` fetch with nothing cached, emits
  `ChatReady(..., loadFailure: failure)` (Edge Cases' "standard no-connection state", Clarification 3); on a
  failed fetch with a cache, emits the cached messages with no `loadFailure`; on success, persists
  `lastActiveSessionId` and emits the fetched messages; `_onConnectivityChanged` updates `ChatReady.isOffline`
  live (research.md R8); exposes `Stream<void> get reauthRequired`; `close()` cancels the connectivity
  subscription and closes `_reauthController`. Depends on T004, T010, T014, T015.

- [X] T017 [P] Create `lib/features/chat/presentation/widgets/chat_message_bubble.dart`: one widget branching
  on `ChatMessage.role`/`.status` — user bubble (`DesignTokens.colorChatBubbleUser`, `radiusMd`, straight
  bottom-right corner) vs. assistant bubble (`DesignTokens.colorSurfaceElevated` + `elevation1`, `radiusMd`,
  straight bottom-left corner); `status == streaming` → a pulsing-cursor indicator, **not** tappable; `status
  == complete` → final text + timestamp, no indicator; `status == failed` → `colorError` "Falha ao gerar
  resposta — toque para tentar novamente" rendered **in place of** the timestamp, tappable **only** in this
  state, invoking an `onRetryTap` callback (data-model.md, FR-004/FR-006). Depends on T006.

- [X] T018 Register Chat's data/repository/bloc layer in `lib/core/di/service_locator.dart`, per data-model.md's
  DI section: `getIt.registerLazySingleton<ChatLocalCache>(ChatLocalCache.new)`;
  `getIt.registerLazySingleton<ChatRemoteDataSource>(() => ChatRemoteDataSource(getIt<ApiClient>()))`;
  `getIt.registerLazySingleton<ChatRepository>(() => ChatRepositoryImpl(getIt<ChatRemoteDataSource>(),
  sessionRepository: getIt<SessionRepository>(), localCache: getIt<ChatLocalCache>()))`;
  `getIt.registerFactory<ChatBloc>(() => ChatBloc(chatRepository: getIt<ChatRepository>(), connectivityChecker:
  getIt<ConnectivityChecker>()))`. Depends on T011, T012, T013, T016.

- [X] T019 Change `lib/core/routing/app_router.dart`'s `AppRoutes.home` route builder from the current bare
  `const HomeChatShellPage()` to `MultiBlocProvider(providers: [BlocProvider<ChatBloc>(create: (_) =>
  getIt<ChatBloc>()..add(const ChatStarted()))], child: const HomeChatShellPage())` — `AppRoutes.home` itself
  stays `'/home'`, unparameterized (research.md R7). Depends on T016, T018.

- [X] T020 Extend `lib/features/home/presentation/pages/home_chat_shell_page.dart`: convert
  `HomeChatShellPage` to a `StatefulWidget`; wrap the body in `BlocBuilder<ChatBloc, ChatState>`, rendering
  `ChatReady.messages` in a `ListView` with one `ChatMessageBubble` (T017) per message; in `initState`,
  subscribe to `context.read<ChatBloc>().reauthRequired`, forwarding each event to
  `context.read<SessionBloc>().add(const AuthExpiredDetected())` — the same cross-bloc touch-point shape
  `RecordsPage` already establishes (research.md R3/R7) — cancelling the subscription in `dispose()`. The
  existing `_ComposerBar` stays as today's fully-disabled scaffold for now (US1 replaces it). Depends on T016,
  T017, T019.

**Checkpoint**: Foundation ready — opening `/home` resumes the last conversation (or shows the empty state),
switching conversations and reloading after a restart both work, and messages render in their three visual
states. No message can be sent yet.

---

## Phase 3: User Story 1 - Getting an answer grounded in your own journal (Priority: P1) 🎯 MVP

**Goal**: send a message into a conversation (creating its session lazily on the first send, FR-010), stream a
RAG-grounded response, and have the full exchange persist across a restart — without ever creating a journal
entry (FR-001/FR-002/FR-003).

**Independent Test**: seed a prior entry on a specific topic, send a chat message that references that topic
without quoting it, and confirm the agent's response reflects that entry's content; confirm the exchange
survives leaving the screen and a full app restart; confirm "Meus Registros" gained no new entry from it.

### Implementation for User Story 1

- [X] T021 [US1] Implement `_onMessageSubmitted(MessageSubmitted event, Emitter<ChatState> emit)` in
  `lib/features/chat/presentation/bloc/chat_bloc.dart` per contracts/chat-bloc.md: no-op when `current is! ChatReady
  || !current.canSend`, or when `!await _connectivityChecker.hasConnection()` (FR-012, blocked client-side);
  otherwise, within one synchronous `emit`, append an optimistic `ChatMessage(role: user, status: complete, id:
  'local-<DateTime.now().microsecondsSinceEpoch>', seq: current.messages.length, ...)` and a paired
  `ChatMessage(role: assistant, status: streaming, id: '<same>-response', content: '', seq:
  current.messages.length + 1, ...)` and set `awaitingResponse: true` (RNF01's "<100 ms local reflection",
  research.md R5); when `current.sessionId == null`, call `createSession(title:
  ChatTitleDeriver.derive(event.text))` first (lazy creation, FR-010) and, on failure, replace both optimistic
  placeholders via a new `_failTurn` helper (sets the assistant placeholder's `status: failed`, `awaitingResponse:
  false`) without ever calling `sendMessage`; on success, call `setLastActiveSessionId(sessionId)`; dispatch
  `sendMessage(sessionId: ..., content: event.text)` into `_consumeTurn` (T022). Depends on T009, T016.

- [X] T022 [US1] Implement the shared `_consumeTurn(stream, emit, {required generation, required sessionId,
  required optimisticUserId, required optimisticAssistantId})` helper (plus small, pure, independently-
  testable `ChatReady → ChatReady` helpers `_reconcileIds`/`_appendToken`/`_completeMessage`/`_applyFailure`) in
  the same file, per contracts/chat-bloc.md: drives `emit.forEach` over the `Stream<Either<Failure,
  ChatStreamEvent>>`, guarded by `if (generation != _turnGeneration || latest is! ChatReady) return latest;`
  (defensive, research.md R9); `MessageCreated` reconciles both optimistic ids in place with the real
  `userMessageId`/`assistantMessageId` (same list position, same content); `ContextReceived` is a no-op;
  `TokenReceived(delta)` appends `delta` to the matched assistant message's `content`; `StreamDone(content:
  ...)` **replaces** `content` with the server's own authoritative final text (not the locally-concatenated
  tokens), sets `status: complete`, `awaitingResponse: false`; a `Left(failure)` (transport- or business-level)
  sets the matched message's `status: failed` while **keeping whatever partial `content` had already
  accumulated** (FR-005 — never removed, hidden, or blanked), `awaitingResponse: false`, firing
  `_reauthController.add(null)` first when the failure is `AuthExpiredFailure`. Depends on T021.

- [X] T023 [US1] Create `lib/features/chat/presentation/widgets/chat_composer.dart`, replacing `_ComposerBar`:
  owns its own `TextEditingController` (never part of `ChatState` — research.md's "composer text is local"
  choice, so nothing typed is ever lost on any failure); `TextField` with `maxLength: 8000` (the exact value
  `chat.messages.send`'s request schema declares — research.md R12, so the field simply stops accepting the
  8001st character); `enabled`/send-button-tappable bound to `ChatReady.canSend` **and** non-empty trimmed
  text; dispatches `MessageSubmitted(text)` on send and clears the controller only on that dispatch. Depends on
  T015.

- [X] T024 [US1] Wire `ChatComposer` into `lib/features/home/presentation/pages/home_chat_shell_page.dart` in
  place of `_ComposerBar`. Depends on T020, T023.

### Tests for User Story 1

- [X] T025 [P] [US1] Unit tests for `ChatTitleDeriver.derive()` in
  `test/features/chat/domain/entities/chat_title_deriver_test.dart`: collapses internal whitespace/newlines to
  single spaces and trims; returns the input unchanged at or under 48 characters; truncates to exactly 48
  characters + `'…'` when longer; never returns an empty string for any non-empty input. Depends on T009.

- [X] T026 [P] [US1] Data-source tests in
  `test/features/chat/data/chat_remote_data_source_test.dart`: `createSession(title: ...)` calls
  `chat-sessions-create` with `{"title": ...}` verbatim; `sendMessage(...)` calls `chat-messages-send` via
  `sseStream` with `pathSegments: [sessionId]`, `body: {'content': ...}`; frame-mapping — `message_created` →
  `MessageCreated`, `context` → filtered out (never emitted), `token` → `TokenReceived(delta)`, `done` →
  `StreamDone`, `error` → `Left(ErrorMapper.fromResponse(...))`, an unrecognized event name → filtered out,
  never thrown. Depends on T012.

- [X] T027 [P] [US1] Repository tests in `test/features/chat/data/chat_repository_impl_test.dart` — contract
  scenarios #1 (`createSession` upserts the parsed session into `cachedSessions`), #2 (`listSessions` →
  `AuthExpiredFailure` on first call → exactly one `SessionRepository.refresh()` → one retry → `Right`), #5
  (`sendMessage`'s stream: first item `Left(AuthExpiredFailure)`, refresh succeeds, re-called stream then
  succeeds — exactly one refresh call, caller sees only the retry's items), #6 (`Right(MessageCreated(...))`
  already emitted, *then* `Left(AuthExpiredFailure)` → yielded as-is, no retry attempted), #7 (first item
  `Left(AuthExpiredFailure)` and the refresh call itself also fails → the original failure is yielded once,
  stream closes, no infinite loop), #8 (a `message_created` frame followed by a connection-drop → both
  `Right(MessageCreated(...))` then `Left(NetworkOfflineFailure)` reach the caller, in order). Depends on T013.

- [X] T028 [P] [US1] `bloc_test` cases in `test/features/chat/presentation/bloc/chat_bloc_test.dart` — contract
  scenarios #1 (`ChatStarted` with no stored `lastActiveSessionId` → `ChatReady(sessionId: null, messages:
  [])`, no repository call beyond that one read), #5 (`MessageSubmitted` on an empty conversation → the
  optimistic user+assistant pair is appended within the same synchronous `emit`, *then* `createSession` is
  called with the derived title, *then* `sendMessage`), #7 (a full successful turn — `MessageCreated` →
  `TokenReceived` × N → `StreamDone` — the assistant message's `content` grows incrementally per token, then is
  replaced by `StreamDone.content` exactly, `status: complete`, `awaitingResponse: false`). Depends on T022.

- [X] T029 [P] [US1] Widget test in `test/features/chat/presentation/widgets/chat_composer_test.dart` (new
  file): typing non-empty text and tapping send dispatches `MessageSubmitted(text)` to a mocked `ChatBloc` and
  clears the controller afterward; typing only whitespace keeps the send control inactive and dispatches
  nothing (Edge Cases). Depends on T024.

**Checkpoint**: A message can be sent into a brand-new or existing conversation, its RAG-grounded response
streams in and persists, and no journal entry is ever created from it. User Story 1 is independently testable
and shippable as the MVP.

---

## Phase 4: User Story 2 - Always knowing what the agent is doing (Priority: P1)

**Goal**: the three response states (streaming / complete / error) are always visually distinguishable, and a
response interrupted mid-stream never disappears (FR-004/FR-005/FR-007).

**Independent Test**: send a message and observe the UI progress through the streaming indicator into complete
or error; force a connection drop mid-response and confirm the partial text stays visible with a failure
indication instead of disappearing.

> The three-state rendering (`chat_message_bubble.dart`, T017) and the partial-content-preserving failure path
> (`_applyFailure` inside `_consumeTurn`, T022) are already built as shared Foundational/US1 infrastructure —
> `_consumeTurn` is one function handling both the success and failure branches of a turn, so it cannot be
> split across phases. This phase's own job is the scenario-specific tests that prove each contract, exactly
> as this story's own Acceptance Scenarios describe observing already-built behavior rather than new code.

### Tests for User Story 2

- [X] T030 [P] [US2] Widget tests for `lib/features/chat/presentation/widgets/chat_message_bubble.dart` in
  `test/features/chat/presentation/widgets/chat_message_bubble_test.dart` (new file): a `streaming` message
  renders a pulsing-cursor indicator and is not tappable; a `complete` message renders its final text +
  timestamp with no indicator; a `failed` message renders "Falha ao gerar resposta" in `colorError` in place of
  the timestamp. Depends on T017.

- [X] T031 [P] [US2] `bloc_test` case in `test/features/chat/presentation/bloc/chat_bloc_test.dart` — contract
  scenario #8: a turn interrupted by `Left(NetworkOfflineFailure)` after 2 `TokenReceived` events keeps the
  assistant message's 2-tokens-worth of partial content, sets `status: failed`, `awaitingResponse: false`
  (FR-005) — the message is never removed, hidden, or blanked. Depends on T022.

- [X] T032 [P] [US2] Widget test confirming `ChatComposer`'s disabled rendering while `ChatReady
  .awaitingResponse` is `true`, in `test/features/chat/presentation/widgets/chat_composer_test.dart`: the send
  control is visibly disabled for the whole duration of a turn, re-enabling only once it reaches
  `complete`/`failed` — so a single conversation never has two responses in flight at once (FR-007, research.md
  R9). Depends on T023.

**Checkpoint**: US1 + US2 — the core conversational loop (send, stream, complete/fail, never ambiguous) is
proven end-to-end and independently verified.

---

## Phase 5: User Story 3 - Recovering from a failed response without losing the conversation (Priority: P2)

**Goal**: a failed message is tappable to retry, regenerating the response to the same original question
without duplicating it, with no limit on attempts, regardless of how much later conversation exists (FR-006).

**Independent Test**: force a response failure, tap the failed message, confirm a fresh attempt starts and the
original question still appears exactly once; force the retry to fail again and confirm the same retry
affordance remains; retry an older failed message (not the most recent) and confirm only that one changes.

### Implementation for User Story 3

- [X] T033 [US3] Implement `_onMessageRetryRequested(MessageRetryRequested event, Emitter<ChatState> emit)` in
  `lib/features/chat/presentation/bloc/chat_bloc.dart` per contracts/chat-bloc.md: no-op when `current is! ChatReady
  || current.awaitingResponse || current.sessionId == null`; find the matched `failed` assistant message's
  **index** (not just its id) via a `_userMessageIdFor` position-matching helper (research.md R10 — matching by
  list position, since neither the OpenAPI contract nor `error-taxonomy.md` states whether a retry's
  `assistantMessageId` reuses the original failed message's id); no-op when `!await _connectivityChecker
  .hasConnection()` (FR-012); replace that index in place with a fresh `streaming` placeholder (`id:
  'local-<timestamp>-retry'`, `retryCount: previous.retryCount + 1`, same `seq`), emit with `awaitingResponse:
  true`; dispatch `retryMessage(sessionId: ..., userMessageId: event.userMessageId)` into the existing
  `_consumeTurn` helper (T022) with `optimisticUserId: null` (a retry never targets an optimistic question —
  only an already-persisted one from a prior turn). Depends on T022.

- [X] T034 [US3] Wire `ChatMessageBubble.onRetryTap` (already defined on the widget's constructor, T017) in
  `lib/features/home/presentation/pages/home_chat_shell_page.dart`'s message list to dispatch
  `MessageRetryRequested(userMessageId)`, where `userMessageId` is the preceding `user`-role message's id in
  `messages` — the same position-matching convention T033 relies on. Depends on T020, T033.

### Tests for User Story 3

- [X] T035 [P] [US3] `bloc_test` cases in `test/features/chat/presentation/bloc/chat_bloc_test.dart` — contract
  scenarios #9 (`MessageRetryRequested` on a `failed` message **not** the most recent in the conversation →
  only that one index is replaced, every later message untouched), #10 (two
  `MessageRetryRequested` dispatched back-to-back for the same message → the second dispatch is a no-op, since
  `awaitingResponse` is already `true` from the first), and #13 (`ConversationSelected`/`NewConversationRequested`
  dispatched while a turn is mid-stream for the conversation being left → the abandoned turn's later
  `TokenReceived`/`StreamDone`/`Left` items are ignored, since `_turnGeneration` was bumped on the switch, so the
  newly-loaded conversation's state is never mutated by it). Depends on T033.

- [X] T036 [P] [US3] Widget test for tap-to-retry in
  `test/features/chat/presentation/widgets/chat_message_bubble_test.dart`: tapping a `failed` bubble invokes
  `onRetryTap` exactly once; tapping a `streaming`/`complete` bubble invokes nothing. Depends on T017, T034.

**Checkpoint**: Stories 1–3 — a failed response can always be retried, any number of times, without
duplicating the original question or disturbing later messages.

---

## Phase 6: User Story 4 - Organizing conversations from the side menu (Priority: P2)

**Goal**: the side menu's "CONVERSAS" section lists past conversations by title/recency, paginated via
`cursor`, with a working "Novo Chat" action that never discards an existing conversation (FR-008/FR-009).

**Independent Test**: with at least one existing conversation, open the side menu, confirm it lists sessions
with title + timestamp; tap "Novo Chat", confirm an empty conversation appears and the prior one is unchanged
when reopened; on an account with more sessions than one backend page, scroll to confirm the next page loads.

### Implementation for User Story 4

- [X] T037 [P] [US4] Create `lib/features/chat/presentation/bloc/chat_sessions_event.dart`: `sealed class
  ChatSessionsEvent`; `SessionsStarted()`; `SessionsRefreshRequested()`; `SessionsNextPageRequested()`;
  `SessionsPageLoadRetried()` (data-model.md's event table).

- [X] T038 [P] [US4] Create `lib/features/chat/presentation/bloc/chat_sessions_state.dart`: `sealed class
  ChatSessionsState`; `ChatSessionsLoading()`; `ChatSessionsLoadFailure(Failure failure)`; `ChatSessionsLoaded`
  with `required` fields `sessions` (`List<ChatSession>`), `nextCursor` (`String?`), `isLoadingMore` (`bool`),
  nullable `pageLoadFailure` (`Failure?`); `bool get hasReachedEnd => nextCursor == null`; a `copyWith(...)`
  covering every field. Depends on T005.

- [X] T039 [US4] Create `lib/features/chat/presentation/bloc/chat_sessions_bloc.dart` per
  contracts/chat-sessions-bloc.md — mirrors `RecordsBloc`'s first-page/next-page/retry shape (RF07), depending
  only on `ChatRepository` (never `ChatBloc`, `SessionBloc`, or `ConnectivityChecker` — research.md R7):
  `_onStarted`/`_onRefreshRequested` both load page 1 via a shared `_loadFirstPage` (the latter never regresses
  an already-populated `ChatSessionsLoaded` back to `ChatSessionsLoading` while it refetches underneath);
  `_loadFirstPage` falls back to `cachedSessions` on an outright failure when non-empty (Clarification 3/FR-011)
  rather than surfacing `ChatSessionsLoadFailure`; `_onNextPageRequested` is generation-guarded and a no-op
  when `hasReachedEnd` or `isLoadingMore` is already `true`, appending the new page's sessions without
  duplicates on success; `_onPageLoadRetried` re-runs page 1 from a `ChatSessionsLoadFailure`, or re-dispatches
  `SessionsNextPageRequested` from a `ChatSessionsLoaded.pageLoadFailure`; exposes `Stream<void> get
  reauthRequired` (its own, independent `StreamController`); `close()` closes it. Depends on T010, T037, T038.

- [X] T040 Register `ChatSessionsBloc` factory in `lib/core/di/service_locator.dart`, alongside the Chat
  registrations from T018: `getIt.registerFactory<ChatSessionsBloc>(() =>
  ChatSessionsBloc(chatRepository: getIt<ChatRepository>()))`. Depends on T018, T039.

- [X] T041 Extend `lib/core/routing/app_router.dart`'s `AppRoutes.home` `MultiBlocProvider` (T019) with a second
  provider, `BlocProvider<ChatSessionsBloc>(create: (_) => getIt<ChatSessionsBloc>())`. Depends on T019, T040.

- [X] T042 [US4] Rebuild `lib/features/home/presentation/widgets/app_drawer.dart` as a `StatefulWidget` per
  data-model.md: add a "CONVERSAS" section (`BlocBuilder<ChatSessionsBloc, ChatSessionsState>` + a `ListView`'s
  own `ScrollController`, same scroll-to-bottom-triggers-`SessionsNextPageRequested` shape `RecordsPage`
  already uses for `NextPageRequested`) above the existing "Meus Registros"/"Configurações" items — each row
  showing the session's `title` and a formatted `lastUserMessageAt`/`updatedAt`, dispatching
  `ConversationSelected(session.id)` to the shared `ChatBloc` and closing the drawer; a "Novo Chat" `ListTile`
  dispatching `NewConversationRequested` to `ChatBloc`; subscribes (independently of `ChatBloc`'s own
  subscription) to `ChatSessionsBloc.reauthRequired`, forwarding to `SessionBloc`. Depends on T039, T041.

- [X] T043 Wire `Scaffold.onDrawerChanged` in `lib/features/home/presentation/pages/home_chat_shell_page.dart`
  to dispatch `SessionsRefreshRequested` to `ChatSessionsBloc` every time the drawer transitions from closed to
  open (research.md R7) — so a session created moments earlier by sending a first message is picked up the
  next time the drawer opens. Depends on T020, T042.

### Tests for User Story 4

- [X] T044 [P] [US4] `bloc_test` cases in `test/features/chat/presentation/bloc/chat_sessions_bloc_test.dart`
  (new file) — contract scenarios #1 (`SessionsStarted` with a successful first page → `ChatSessionsLoaded`
  with the backend's own `nextCursor`), #2 (`SessionsStarted` fails outright, nothing cached →
  `ChatSessionsLoadFailure`), #4 (`SessionsRefreshRequested` fired while already `ChatSessionsLoaded`, and the
  refresh itself fails → the existing `sessions` list is untouched, never regresses), #5
  (`SessionsNextPageRequested` when `hasReachedEnd` is already `true` → no repository call), #6
  (`SessionsNextPageRequested` succeeds → `sessions` grows by exactly the new page's items, no duplicates,
  `nextCursor` updated — SC-007), #8 (two `SessionsNextPageRequested` fired back-to-back before the first
  resolves → the second is a no-op while `isLoadingMore` is already `true`). Depends on T039.

- [X] T045 [P] [US4] Widget tests for the "CONVERSAS" section and "Novo Chat" in
  `test/features/home/presentation/widgets/app_drawer_test.dart` (new file): the section lists each loaded
  session with its title + timestamp; tapping a session row dispatches `ConversationSelected(session.id)` and
  closes the drawer; tapping "Novo Chat" dispatches `NewConversationRequested`; scrolling to the bottom of the
  section dispatches `SessionsNextPageRequested`. Depends on T042.

- [X] T046 [P] [US4] `bloc_test` case in `test/features/chat/presentation/bloc/chat_bloc_test.dart` — contract
  scenario #11: `NewConversationRequested` while a previous conversation has in-memory messages leaves that
  previous conversation's own `ChatLocalCache` entry untouched — only `lastActiveSessionId` changes; selecting
  it again later still shows its full history (already-built Foundational behavior, T013/T016; this task is
  test-only). Depends on T013, T016.

**Checkpoint**: Stories 1–4 — the side menu organizes and paginates conversations; "Novo Chat" never discards
an existing one.

---

## Phase 7: User Story 5 - Reading history while offline (Priority: P3)

**Goal**: every previously-opened conversation's history and the side menu's own list stay visible, scrollable,
and switchable offline; the send control is disabled with an explanatory banner; sending resumes automatically
on reconnect (FR-011/FR-012).

**Independent Test**: load a conversation, go offline, confirm history stays visible/scrollable and the
composer is disabled with a banner; switch to a different previously-opened conversation offline and confirm
its own cached history shows correctly; select a never-opened conversation offline and confirm the
no-connection state instead of any content; reconnect and confirm the composer re-enables automatically.

> The offline cache-fallback logic itself (`_loadSession`'s cached/no-cache branching, `ChatSessionsBloc`'s own
> `cachedSessions` fallback) is already built in Foundational (T016, T039) as a direct consequence of
> Clarification 3's scope. This phase's own new work is the offline banner widget and its wiring, plus the
> scenario-specific tests proving multi-conversation offline coverage.

### Implementation for User Story 5

- [X] T047 [P] [US5] Create `lib/features/chat/presentation/widgets/chat_offline_banner.dart`: "Sem conexão —
  histórico disponível, novas mensagens bloqueadas" (prototype-extract.md §2.2), `DesignTokens.colorInfoOffline`
  background per data-model.md's token-reuse table.

- [X] T048 [US5] Render `ChatOfflineBanner` in `lib/features/home/presentation/pages/home_chat_shell_page.dart`
  whenever `ChatReady.isOffline` is `true` (FR-011). Depends on T020, T047.

### Tests for User Story 5

- [X] T049 [P] [US5] Offline cache-fallback tests across multiple previously-opened conversations —
  chat-repository.md contract scenario #4 (`cachedMessages('never-opened')` returns `null`) in
  `test/features/chat/data/chat_repository_impl_test.dart`; chat-bloc.md contract scenarios #3 (`ChatStarted`/
  `_loadSession` with a failed fetch and nothing cached → `loadFailure` set) and #4 (a failed fetch but a cache
  exists → the cached messages are shown, no `loadFailure`) in
  `test/features/chat/presentation/bloc/chat_bloc_test.dart` — together proving SC-006/Clarification 3. Depends
  on T013, T016.

- [X] T050 [P] [US5] `bloc_test` case for `ChatSessionsBloc`'s own offline fallback in
  `test/features/chat/presentation/bloc/chat_sessions_bloc_test.dart` — contract scenario #3: `SessionsStarted`
  fails but `cachedSessions` is non-empty → `ChatSessionsLoaded(sessions: <cached>, nextCursor: null)`,
  satisfying FR-011's "the side menu's own CONVERSAS list" staying browsable offline. Depends on T039.

- [X] T051 [P] [US5] Widget test confirming `ChatComposer`'s disabled rendering while `ChatReady.isOffline` is
  `true`, and that it re-enables automatically (no manual action) once `isOffline` flips back to `false` —
  "within one interaction of connectivity returning" (SC-006) — in
  `test/features/chat/presentation/widgets/chat_composer_test.dart`. Depends on T023.

**Checkpoint**: All five user stories are independently functional — the full RF04 scope works end-to-end.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: the project's own verification gates (RNF06/RNF07, quickstart.md).

- [X] T052 Run `fvm flutter analyze` and `dart test/architecture/no_bloc_imports_bloc_test.dart` plus `dart
  test/architecture/domain_purity_test.dart`, confirming both continue to pass unmodified against the new
  `lib/features/chat/` folder — `chat/domain/` imports only `equatable`/`fpdart`, and `ChatBloc`/
  `ChatSessionsBloc` neither import each other nor `SessionBloc` (manually re-confirmed, since the architecture
  test only mechanically enforces cross-*feature* imports — quickstart.md "Automated checks"). Depends on all
  prior tasks.

- [X] T053 Run `fvm flutter test --coverage`, then `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o
  coverage/domain.info` and `genhtml coverage/domain.info -o coverage/domain-html`; confirm ≥80% domain
  coverage (RNF07 gate) including `chat_title_deriver.dart`, `ChatMessage`'s status-transition shape, and
  `ChatStreamEvent`'s sealed variants. Depends on T052.

- [ ] T054 Execute quickstart.md's manual verification walkthrough on a device/Simulator — Stories 1–5 plus
  "Edge cases worth exercising manually at least once" (empty/whitespace message, the 8000-character cap,
  double-send-while-awaiting, session-expiry mid-stream, navigate-away-mid-stream, zero-conversations
  first-ever use) — using a seeded prior entry
  (`docs/input/backend/fixtures/seeded-search-entries.md`) and an account with more sessions than one
  `chat-sessions-list` page. Depends on T053.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: no dependencies — can start immediately. **BLOCKS** every user story phase (every
  story needs `ChatBloc`'s "load a conversation" machinery at minimum).
- **User Story 1 (Phase 3)**: depends on Foundational only. MVP.
- **User Story 2 (Phase 4)**: depends on Foundational **and** US1's `_consumeTurn` (T022) — its failure-handling
  branch is built as part of that same function and cannot be split; this phase is otherwise test-only.
- **User Story 3 (Phase 5)**: depends on Foundational and US1's `_consumeTurn` (T022), which it reuses verbatim
  for the retry's own stream consumption.
- **User Story 4 (Phase 6)**: depends on Foundational only — independent of US1/US2/US3's own tasks (no shared
  code with `ChatBloc`'s turn-consumption machinery).
- **User Story 5 (Phase 7)**: depends on Foundational's `_loadSession`/`ChatSessionsBloc` cache-fallback logic
  (already built there) and on `ChatComposer` (T023, US1) for its own offline-disabling test.
- **Polish (Phase 8)**: depends on all five user stories being complete.

### Within Each Phase

- Tasks touching the *same* file (`chat_bloc.dart`, `home_chat_shell_page.dart`, `app_drawer.dart`,
  `service_locator.dart`, `app_router.dart`) are listed in the sequential order they must be applied.
- Tasks creating a *new* file with no dependency on that phase's other new files are marked `[P]`.
- Test tasks are marked `[P]` relative to each other (distinct test files); each still depends on its
  corresponding implementation task(s) existing to pass.

### Parallel Opportunities

- T001, T004–T009, T014, T015, T017 (Foundational's entities/events/states/widgets/transport) can all run in
  parallel — ten independent files with no cross-dependencies among them.
- T011 and T012 (local cache, remote data source) can run in parallel with each other once T001–T009 land.
- All test tasks within a single user story phase can run in parallel with each other.
- User Story 4 (side menu) can be implemented in parallel with User Stories 1–3 (the live conversation) by a
  second developer, since neither `ChatSessionsBloc` nor `AppDrawer`'s "CONVERSAS" section shares any code path
  with `ChatBloc`'s turn-consumption machinery.

---

## Parallel Example: Foundational Phase

```bash
# Launch the independent entity/transport/widget files together:
Task: "Create SseFrame in lib/core/network/sse_frame.dart"
Task: "Add onConnectivityChanged to lib/core/network/connectivity_checker.dart"
Task: "Create ChatSession/ChatPersona in lib/features/chat/domain/entities/chat_session.dart"
Task: "Create ChatRole/ChatMessageStatus/ChatMessage in lib/features/chat/domain/entities/chat_message.dart"
Task: "Create ChatStreamEvent in lib/features/chat/domain/entities/chat_stream_event.dart"
Task: "Create ChatTitleDeriver in lib/features/chat/domain/entities/chat_title_deriver.dart"
Task: "Create ChatEvent in lib/features/chat/presentation/bloc/chat_event.dart"
Task: "Create ChatMessageBubble in lib/features/chat/presentation/widgets/chat_message_bubble.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (transport, data layer, entities, `ChatBloc`'s conversation-loading core).
2. Complete Phase 3: User Story 1 (lazy session creation, send, stream, persist, no entry created).
3. **STOP and VALIDATE**: seed a prior entry, send a related message, confirm the grounded response (SC-001);
   restart the app and confirm the exchange persists (SC-005).
4. Demo/ship if ready — this alone delivers RF04's "entire premise" (spec.md, User Story 1's "Why this
   priority").

### Incremental Delivery

1. Foundational → User Story 1 (MVP: grounded, persisted conversation).
2. + User Story 2 (the three-state visual contract — mostly tests over already-built engine behavior).
3. + User Story 3 (tap-to-retry on a failed response).
4. + User Story 4 (side menu: list, paginate, "Novo Chat") — independently buildable in parallel with 2–3.
5. + User Story 5 (offline banner + multi-conversation offline coverage).
6. + Polish (verification gates, manual walkthrough).

Each stage adds value without breaking the previous one, matching spec.md's own stated priority order (P1, P1,
P2, P2, P3).

---

## Phase 9: Convergence

- [X] T055 Render the "standard no-connection state" in
  `lib/features/home/presentation/pages/home_chat_shell_page.dart` when `ChatReady.loadFailure` is set: the
  `BlocBuilder<ChatBloc, ChatState>` currently renders the same empty `ListView` for this case as it does for a
  brand-new, zero-message conversation, with nothing distinguishing "nothing was ever cached for this
  conversation while offline" from "this conversation genuinely has no messages yet" — violating the Edge
  Cases' "shows the standard no-connection state (no cached data to fall back to) rather than any content,
  distinct from the normal offline case of browsing an already-cached conversation" and quickstart.md's Story 5
  step 4 manual-test expectation. Add a dedicated failure view (mirroring `RecordsPage`'s own
  `_LoadFailureView` pattern already established in this codebase), showing `loadFailure!.message` and a retry
  action that re-dispatches `ConversationSelected(sessionId)` for the current `state.sessionId`. per FR-011
  (partial)

- [X] T056 Dispatch `SessionsStarted` once when `ChatSessionsBloc` is constructed, in
  `lib/core/routing/app_router.dart`'s `/home` route builder: change
  `BlocProvider<ChatSessionsBloc>(create: (_) => getIt<ChatSessionsBloc>())` to also
  `..add(const SessionsStarted())`, matching `chat_sessions_event.dart`'s own doc comment on `SessionsStarted`
  ("Dispatched once when `ChatSessionsBloc` is constructed (the drawer's very first open)") and the sibling
  `ChatBloc` provider's own `..add(const ChatStarted())` pattern immediately above it. Currently `SessionsStarted`
  is never dispatched anywhere in production code — only from unit tests — leaving `ChatSessionsBloc` in its
  initial `ChatSessionsLoading()` state indefinitely until the drawer happens to be opened for the first time.
  per plan: ChatSessionsBloc initialization (data-model.md's event table) (missing)

---

## Phase 10: Convergence

- [X] T057 Fix the dead-end retry on a failed lazy-session-creation turn in
  `lib/features/chat/presentation/bloc/chat_bloc.dart`: when `_onMessageSubmitted`'s `createSession` call fails
  (`current.sessionId == null` at submit time), `_failTurn` correctly marks the optimistic assistant placeholder
  `ChatMessageStatus.failed`, but `_onMessageRetryRequested`'s very first guard (`current.sessionId == null`)
  then makes tapping that bubble's "Falha ao gerar resposta - toque para tentar novamente" affordance
  (`chat_message_bubble.dart`'s `onRetryTap`, wired in `home_chat_shell_page.dart`) a silent no-op: no retry is
  attempted, no new failure is shown, nothing happens. This violates FR-006 ("A message in the error state MUST
  be tappable to trigger a retry... MUST remain available on any message in the error state") for the one
  failure path that precedes a session ever existing - a `createSession` failure is a real, reachable outcome
  of FR-010's own lazy-creation design, and neither `contracts/chat-bloc.md`'s own scenario table (#1-13) nor
  `test/features/chat/presentation/bloc/chat_bloc_test.dart` covers this case today. Fix by detecting, in
  `_onMessageRetryRequested` (or a small new branch ahead of its current guard), that the matched failed
  message's preceding user message is still optimistic (`ChatMessage.isOptimistic`, i.e. the turn never got a
  real session) and, in that case, retrying by re-running the lazy-creation path -
  `createSession(title: ChatTitleDeriver.derive(originalUserMessage.content))` then `sendMessage(...)` - using
  the original user message's own `content`, reusing `_consumeTurn` exactly as `_onMessageSubmitted` already
  does, rather than calling `ChatRepository.retryMessage` (which has no session/persisted message to target).
  per FR-006 (missing)

- [X] T058 Render `ChatSessionsLoaded.isLoadingMore`'s loading indicator and `.pageLoadFailure`'s retry
  affordance in `lib/features/home/presentation/widgets/app_drawer.dart`'s "CONVERSAS" section: the
  `ChatSessionsLoaded` branch of the `BlocBuilder<ChatSessionsBloc, ChatSessionsState>` switch currently builds
  a bare `ListView.builder(itemCount: sessions.length, ...)` with no footer for either field, even though
  `ChatSessionsState` (T038) and `ChatSessionsBloc` (T039) both already produce and update them on every
  `SessionsNextPageRequested` call. `lib/features/records/presentation/pages/records_page.dart` (around lines
  171-185) establishes this codebase's own pattern for the identical shape - a `CircularProgressIndicator`
  while `isLoadingMore`, and a retry view (dispatching `PageLoadRetried`) when `pageLoadFailure != null` -
  which `contracts/chat-sessions-bloc.md`/T039's own task description explicitly says `ChatSessionsBloc`
  "mirrors `RecordsBloc`'s first-page/next-page/retry shape" for exactly this reason. Without it, a failed
  next-page fetch gives the user no feedback and no visible way to retry (the only way it currently recovers is
  incidentally, by the user scrolling away from and back to the bottom, re-triggering the scroll listener) -
  undermining FR-008's "so every conversation stays reachable." Add an extra item at the end of the
  `ListView.builder` (or a trailing `Column` child) rendering a spinner for `isLoadingMore` and a message plus
  a "Tentar novamente" `TextButton` dispatching `const SessionsPageLoadRetried()` for `pageLoadFailure`,
  matching `records_page.dart`'s own retry-banner treatment. per FR-008 (partial)

- [X] T059 Keep `ChatRepositoryImpl`'s in-memory `_cachedSessions` ordered by `lastUserMessageAt` descending
  after every mutation, in `lib/features/chat/data/chat_repository_impl.dart`: `_upsertSession` (called from
  both `createSession` and `listSessions`) either replaces an existing session at its current index or appends
  a genuinely new one to the end, but never repositions it - so a session that just became the most recently
  active one (a brand-new conversation via `createSession`, or an existing one whose `lastUserMessageAt` moved
  forward via a fresh `listSessions` page) is not moved to the front. This only surfaces through the
  `cachedSessions` getter - the fallback `ChatSessionsBloc._loadFirstPage` reads when a `listSessions` call
  fails outright and the cache is non-empty (Clarification 3/FR-011's offline path) - since the online,
  successful path already renders the backend's own correctly-ordered `page.sessions` directly and never
  touches `_cachedSessions`'s order. `data-model.md`'s own repository interface doc comment says `listSessions`
  is "ordered by `lastUserMessageAt` desc (FR-008)" with no such order guarantee documented for `cachedSessions`
  - but FR-008's own requirement text ("listing the user's existing conversations... ordered by most recent
  activity") is not scoped to the online case only, and `ChatLocalCache.readSessions()`/`writeSessions()`
  (T011) perform no sorting of their own either. Fix by re-sorting `_cachedSessions` by `lastUserMessageAt`
  (descending, nulls last) immediately after `_upsertSession` runs, in both `createSession` and `listSessions`.
  per FR-008 (partial)

---

## Phase 11: Convergence

- [X] T060 Add the missing `bloc_test` case for `contracts/chat-sessions-bloc.md`'s scenario #7 in
  `test/features/chat/presentation/bloc/chat_sessions_bloc_test.dart`: `SessionsNextPageRequested` dispatched
  from a `ChatSessionsLoaded` state whose `listSessions(cursor: ...)` call resolves to
  `Left(AuthExpiredFailure(...))` — assert `ChatSessionsBloc.reauthRequired` emits exactly once and the
  resulting state is `ChatSessionsLoaded` with `sessions`/`nextCursor` unchanged from before the dispatch,
  `isLoadingMore: false`, and `pageLoadFailure: null` (not the failure itself — `AuthExpiredFailure` takes the
  silent, overlay-driven path per `_onNextPageRequested`'s existing `if (failure is AuthExpiredFailure)`
  branch in `lib/features/chat/presentation/bloc/chat_sessions_bloc.dart`, distinct from scenario #7's sibling
  #6/#8 already covered by `test/features/chat/presentation/bloc/chat_sessions_bloc_test.dart`). This is the
  one of `chat-sessions-bloc.md`'s 8 documented scenarios that neither T044 nor T050 (nor any later
  Convergence task) was ever assigned to covering — `_onNextPageRequested`'s `AuthExpiredFailure` branch is
  already correctly implemented (verified by reading the code), but is currently exercised by zero tests, so a
  regression there (e.g. accidentally surfacing the failure via `pageLoadFailure` instead of the silent
  reauth-overlay path, or failing to fire `reauthRequired`) would go undetected — the same test-completeness
  standard `tasks.md`'s own "Tests" section states for every other contract scenario in this feature
  ("every file under `contracts/` carries its own 'Test scenarios this contract owns' table... this is this
  feature's own design material requesting test tasks"). per contracts/chat-sessions-bloc.md scenario #7
  (partial)

---

## Phase 12: Convergence

- [X] T061 Add defensive parsing to `ChatRemoteDataSource._mapFrame` in
  `lib/features/chat/data/chat_remote_data_source.dart` (around lines 103-131): the body currently does
  `jsonDecode(frame.data) as Map<String, dynamic>` followed by unguarded field casts
  (`decoded['userMessageId'] as String`, `decoded['content'] as String`, `DateTime.parse(...)`, etc.) with no
  `try`/`catch` around any of it — the one parse path in this file that lacks the defensive shape every sibling
  method here already has. `_parseSession`/`_parseSessionsPage`/`_parseMessagesList` (same file) each wrap their
  own field-for-field parsing in `try { ... } on TypeError { return const Left(_malformedChatFailure); } on
  FormatException { return const Left(_malformedChatFailure); }` — `_mapFrame` has neither. If any SSE frame's
  `data` is malformed JSON (`jsonDecode` throws `FormatException`, reachable even for a frame with an `event:`
  line but an empty/missing `data:` line, which `ApiClient._parseFrame` happily yields as `data: ''`) or is
  missing/mistyped an expected key (e.g. a `done` frame without `content` → `decoded['content'] as String`
  throws `TypeError` since the map lookup returns `null`), the exception propagates out of the `Stream.map()`
  callback as an uncaught stream error, not a `Left(Failure)` value. `ChatBloc._consumeTurn`
  (`lib/features/chat/presentation/bloc/chat_bloc.dart`) drives this stream via `emit.forEach(stream, onData:
  ...)` with no `onError` supplied, so that error is never turned into a state emission — the assistant
  message stays in `ChatMessageStatus.streaming` indefinitely, with no "Falha ao gerar resposta" tap-to-retry
  affordance ever appearing (that only renders for `status == failed`), violating FR-004's "A response MUST
  always end in one of these three states — streaming, complete, or error — never left ambiguous" and the
  constitution's RNF09 ("every write endpoint MUST handle timeout, malformed response, and no-connection
  failures, each covered by mocktail tests") for this unit's own streaming write endpoint —
  `plan.md`'s Constitution Check claims this endpoint's "3 required failure scenarios (timeout, malformed
  response, no-connection)" are "exercised at the transport layer... exactly as rigorously as any single-shot
  write endpoint's," but neither `contracts/sse-transport-extension.md`'s 5-scenario table nor
  `test/core/network/api_client_sse_test.dart` (T003) nor
  `test/features/chat/data/chat_remote_data_source_test.dart` ever exercises a malformed-JSON-payload-within-a-
  successful-frame case (only SSE framing edge cases — chunk splitting, multi-line `data:`, unrecognized event
  names — are covered; a frame that parses as a valid `SseFrame` but whose `data` is bad JSON or missing a
  field is not). Fix by wrapping `_mapFrame`'s inner `(frame) { ... }` closure body in the same
  `try`/`on TypeError`/`on FormatException` → `Left(_malformedChatFailure)` shape the file's other three parse
  methods already use, and add a test in `chat_remote_data_source_test.dart` asserting that a `done` (or
  `token`/`message_created`) frame with malformed/missing JSON fields yields `Left(_malformedChatFailure)`
  rather than throwing. per FR-004 / RNF09 (partial)

---

## Phase 13: Convergence

- [X] T062 Add the missing `bloc_test` case for `contracts/chat-bloc.md`'s scenario #8 in
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`: a `MessageSubmitted`-started turn whose
  `sendMessage` stream yields `Right(MessageCreated(...))`, then two `Right(TokenReceived(...))` items, then
  `Left(NetworkOfflineFailure(...))` - assert the assistant message keeps its two-tokens-worth of accumulated
  `content` (not removed, hidden, or blanked), `status` becomes `ChatMessageStatus.failed`, and
  `awaitingResponse` becomes `false`. `chat_bloc_test.dart` currently has 14 `blocTest` cases covering scenarios
  `#1`-`#7`, `#9`-`#15` (verified by reading the file), but no case for `#8` - the one scenario that exercises
  `_consumeTurn`'s `Left(failure)` branch (`lib/features/chat/presentation/bloc/chat_bloc.dart`'s
  `_applyFailure`) on a turn that already received live tokens, as opposed to `#15`'s coverage of a failure
  during lazy `createSession` (no tokens ever received) or `#9`/`#10`'s seeded-already-failed states (never
  exercising `_applyFailure` at all). This is the one contract scenario `tasks.md`'s own T031 claims to have
  added (and is marked `[X]` complete) but does not actually exist in the test file - the production code path
  itself (`_applyFailure` preserving `m.content` while only changing `status`) was verified correct by reading
  `chat_bloc.dart`, but FR-005 ("the system MUST keep whatever partial text had already arrived visible... MUST
  NOT remove, hide, or blank out a partial message") and SC-003 ("in 100% of forced stream-interruption
  scenarios, the partial response text remains visible... never disappearing") - both explicitly P1/US2
  acceptance criteria - have no automated regression coverage for this exact path, violating RNF09's "every
  write endpoint... each covered by mocktail tests" standard this feature's own design material (contracts/
  chat-bloc.md's scenario table) already calls for. per FR-005 (partial)

---

## Phase 14: Convergence

- [X] T063 Add `test/features/home/presentation/pages/home_chat_shell_page_test.dart`, a widget test file for
  `lib/features/home/presentation/pages/home_chat_shell_page.dart` — the one screen-level file in this feature
  with zero test coverage above the bloc-unit level (confirmed absent: no file anywhere under `test/`
  references `HomeChatShellPage`), unlike its sibling `lib/features/records/presentation/pages/records_page.dart`
  (covered by `test/features/records/presentation/pages/records_page_test.dart`) and this same feature's own
  `app_drawer.dart` (covered by `test/features/home/presentation/widgets/app_drawer_test.dart`). Mirroring
  `records_page_test.dart`'s shape (a mocked bloc pumped with each relevant state via `whenListen`/`MockChatBloc`),
  cover: (1) `ChatReady(loadFailure: ...)` renders `_ChatLoadFailureView` showing `loadFailure!.message` and a
  "Tentar novamente" action that dispatches `ConversationSelected(state.sessionId)` (T055's fix,
  `home_chat_shell_page.dart:120-142`) rather than the same empty `ListView` a genuinely-empty conversation
  renders; (2) `ChatReady(isOffline: true)` renders `ChatOfflineBanner` (FR-011) while `ChatReady(isOffline:
  false)` does not; (3) the composer's enabled/disabled rendering follows `ChatReady.canSend` end-to-end as
  wired in this page (not just at the `ChatComposer` widget-test level already covered by T029/T032/T051 —
  this file's own `BlocBuilder` branch wiring); (4) tapping a `failed` message bubble's retry affordance
  dispatches `MessageRetryRequested(precedingUserMessage.id)` with the correct preceding-user-message id from
  `itemBuilder` (T034's wiring, not previously exercised above the `chat_message_bubble_test.dart`
  widget-in-isolation level); (5) a `reauthRequired` stream event from `ChatBloc` is forwarded to
  `context.read<SessionBloc>().add(const AuthExpiredDetected())` (FR-013, T020's `initState` subscription). per
  FR-011 / FR-007 / FR-013 / FR-006 (missing)
