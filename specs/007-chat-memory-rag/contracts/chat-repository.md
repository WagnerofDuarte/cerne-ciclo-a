# Contract: `ChatRemoteDataSource` / `ChatRepositoryImpl` (`lib/features/chat/data/`)

## `ChatRemoteDataSource`

```dart
class ChatRemoteDataSource {
  const ChatRemoteDataSource(this._apiClient);
  final ApiClient _apiClient;

  Future<Either<Failure, ChatSession>> createSession({required String title}) async {
    final result = await _apiClient.call(
      'chat-sessions-create', method: 'POST', body: {'title': title},
    );
    return result.flatMap(_parseSession);
  }

  Future<Either<Failure, ChatSessionsPage>> listSessions({String? cursor, int? limit}) async {
    final result = await _apiClient.call(
      'chat-sessions-list', method: 'GET',
      queryParameters: {'cursor': ?cursor, 'limit': ?limit?.toString()},
      unwrapData: false,   // the response's "data" is an array (meta.nextCursor needed), same shape entries-list uses
    );
    return result.flatMap(_parseSessionsPage);
  }

  Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId) async {
    final result = await _apiClient.call(
      'chat-messages-list', method: 'GET', pathSegments: [sessionId], unwrapData: false,
    );
    return result.flatMap(_parseMessagesList);
  }

  Stream<Either<Failure, ChatStreamEvent>> sendMessage({
    required String sessionId, required String content,
  }) {
    return _apiClient
        .sseStream('chat-messages-send', method: 'POST', pathSegments: [sessionId], body: {'content': content})
        .map(_mapFrame)
        .where((e) => e != null)
        .cast<Either<Failure, ChatStreamEvent>>();
  }

  Stream<Either<Failure, ChatStreamEvent>> retryMessage({
    required String sessionId, required String userMessageId,
  }) {
    return _apiClient
        .sseStream(
          'chat-messages-retry', method: 'POST',
          pathSegments: [sessionId, userMessageId], body: const {},
        )
        .map(_mapFrame)
        .where((e) => e != null)
        .cast<Either<Failure, ChatStreamEvent>>();
  }

  /// `null` for a frame this app ignores outright (`context` — research.md R2); every other
  /// frame maps 1:1 to a `ChatStreamEvent` or, for the backend-named `error` event, to `Left`.
  Either<Failure, ChatStreamEvent>? _mapFrame(Either<Failure, SseFrame> frameResult) {
    return frameResult.match(
      (failure) => Left(failure),   // a transport-level failure from sseStream() itself — passed through as-is
      (frame) {
        final decoded = jsonDecode(frame.data) as Map<String, dynamic>;
        return switch (frame.event) {
          'message_created' => Right(MessageCreated(
              userMessageId: decoded['userMessageId'] as String,
              assistantMessageId: decoded['assistantMessageId'] as String,
            )),
          'context' => null,
          'token' => Right(TokenReceived(decoded['delta'] as String)),
          'done' => Right(StreamDone(
              assistantMessageId: decoded['assistantMessageId'] as String,
              content: decoded['content'] as String,
              createdAt: DateTime.parse(decoded['createdAt'] as String),
            )),
          'error' => Left(ErrorMapper.fromResponse(decoded)),   // business-level failure (research.md R2)
          _ => null,   // forward-compatible: an unrecognized event name is ignored, never thrown (FR-003-style "never an unhandled crash")
        };
      },
    );
  }

  // _parseSession / _parseSessionsPage / _parseMessagesList: same try/on TypeError/on FormatException
  // shape as entries_remote_data_source.dart's _parseEntry/_parseEntriesPage, field-for-field against
  // data-model.md's ChatSession/ChatMessage.
}
```

## `ChatRepositoryImpl`

```dart
class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(this._remoteDataSource, {required this._sessionRepository, required this._localCache});

  final ChatRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;
  final ChatLocalCache _localCache;

  List<ChatSession> _cachedSessions = [];
  final Map<String, List<ChatMessage>> _cachedMessages = {};
  Future<void>? _localCacheLoad;

  Future<void> _ensureLocalCacheLoaded() => _localCacheLoad ??= () async {
    _cachedSessions = await _localCache.readSessions();
    _cachedMessages.addAll(await _localCache.readAllMessages());
  }();

  @override
  Future<Either<Failure, ChatSession>> createSession({required String title}) async {
    await _ensureLocalCacheLoaded();
    final result = await _retryAfterSilentRefreshIfExpired(
      () => _remoteDataSource.createSession(title: title),
    );
    return result.match(
      (f) => Left(f),
      (session) {
        _upsertSession(session);
        return Right(session);
      },
    );
  }

  @override
  Future<Either<Failure, ChatSessionsPage>> listSessions({String? cursor, int? limit}) async {
    await _ensureLocalCacheLoaded();
    final result = await _retryAfterSilentRefreshIfExpired(
      () => _remoteDataSource.listSessions(cursor: cursor, limit: limit),
    );
    return result.match((f) => Left(f), (page) {
      for (final s in page.sessions) {
        _upsertSession(s);
      }
      unawaited(_localCache.writeSessions(_cachedSessions));
      return Right(page);
    });
  }

  @override
  List<ChatSession> get cachedSessions => List.unmodifiable(_cachedSessions);

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId) async {
    await _ensureLocalCacheLoaded();
    final result = await _retryAfterSilentRefreshIfExpired(
      () => _remoteDataSource.listMessages(sessionId),
    );
    return result.match((f) => Left(f), (messages) {
      _cachedMessages[sessionId] = messages;
      unawaited(_localCache.writeMessagesForSession(sessionId, messages));
      return Right(messages);
    });
  }

  @override
  List<ChatMessage>? cachedMessages(String sessionId) => _cachedMessages[sessionId];

  @override
  Future<void> setLastActiveSessionId(String? sessionId) =>
      _localCache.writeLastActiveSessionId(sessionId);

  @override
  Future<String?> get lastActiveSessionId => _localCache.readLastActiveSessionId();

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage({
    required String sessionId, required String content,
  }) => _streamWithAuthRetry(() => _remoteDataSource.sendMessage(sessionId: sessionId, content: content));

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage({
    required String sessionId, required String userMessageId,
  }) => _streamWithAuthRetry(
    () => _remoteDataSource.retryMessage(sessionId: sessionId, userMessageId: userMessageId),
  );

  /// research.md R3 — retries the whole call once only if the *first* item is AuthExpiredFailure.
  Stream<Either<Failure, ChatStreamEvent>> _streamWithAuthRetry(
    Stream<Either<Failure, ChatStreamEvent>> Function() call,
  ) async* {
    var isFirst = true;
    var retried = false;
    var stream = call();
    while (true) {
      await for (final item in stream) {
        if (isFirst && !retried && item.isLeft() &&
            item.match((f) => f is AuthExpiredFailure, (_) => false)) {
          final refreshed = await _sessionRepository.refresh();
          if (refreshed.isLeft()) {
            yield item;   // refresh itself failed — surface the original AuthExpiredFailure
            return;
          }
          retried = true;
          stream = call();
          break;   // restart the outer while(true) with the fresh stream
        }
        isFirst = false;
        yield item;
      }
      if (!retried || isFirst == false) return;
    }
  }

  void _upsertSession(ChatSession session) {
    final i = _cachedSessions.indexWhere((s) => s.id == session.id);
    if (i >= 0) {
      _cachedSessions[i] = session;
    } else {
      _cachedSessions = [..._cachedSessions, session];
    }
  }

  Future<Either<Failure, T>> _retryAfterSilentRefreshIfExpired<T>(
    Future<Either<Failure, T>> Function() call,
  ) async {
    final result = await call();
    return result.match(
      (f) => f is AuthExpiredFailure ? _retryAfterSilentRefresh(call) : Future.value(Left(f)),
      (v) => Future.value(Right(v)),
    );
  }

  // _retryAfterSilentRefresh: identical to EntriesRepositoryImpl's own (exactly one retry, no loop).
}
```

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `createSession` with title "Como lidar com ansiedade antes de apresentações" | `chat-sessions-create` called with `{"title": "..."}` verbatim; parsed `ChatSession` upserted into `cachedSessions` |
| 2 | `listSessions()` → `AuthExpiredFailure` on first call, success on the retry | exactly one `SessionRepository.refresh()` call, then one more `listSessions` call; final result is `Right` |
| 3 | `listMessages('s1')` succeeds | `cachedMessages('s1')` returns that exact list afterward; `ChatLocalCache.writeMessagesForSession('s1', ...)` called once |
| 4 | `cachedMessages('never-opened')` | returns `null` (Clarification 3's "nothing cached for it") |
| 5 | `sendMessage(...)` stream: first item is `Left(AuthExpiredFailure)`, refresh succeeds, re-called stream then succeeds normally | exactly one refresh call; the caller sees only the second call's items (the first `AuthExpiredFailure` is swallowed, not yielded) |
| 6 | `sendMessage(...)` stream: `Right(MessageCreated(...))` already emitted, *then* `Left(AuthExpiredFailure)` | the `AuthExpiredFailure` is yielded as-is (no retry attempted) — research.md R3 |
| 7 | `sendMessage(...)` stream: first item is `Left(AuthExpiredFailure)`, and the refresh call itself also fails | the original `AuthExpiredFailure` is yielded once, stream closes — no infinite loop |
| 8 | A `message_created` frame followed immediately by a connection-drop `DioException` | `Right(MessageCreated(...))`, then `Left(NetworkOfflineFailure)` — both reach the caller, in order |
