import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/data/chat_local_cache.dart';
import 'package:cerne/features/chat/data/chat_remote_data_source.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_sessions_page.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/entities/insight_trigger.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps [ChatRemoteDataSource] + [ChatLocalCache] + [SessionRepository]
/// (for the silent-refresh retry, research.md R3) — same constructor shape
/// as `EntriesRepositoryImpl`. Registered as a `get_it` `lazySingleton` so
/// [cachedSessions]/[cachedMessages] survive across screen rebuilds.
class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(
    this._remoteDataSource, {
    required this._sessionRepository,
    required this._localCache,
  });

  final ChatRemoteDataSource _remoteDataSource;
  final SessionRepository _sessionRepository;
  final ChatLocalCache _localCache;

  List<ChatSession> _cachedSessions = [];
  final Map<String, List<ChatMessage>> _cachedMessages = {};
  Map<String, String> _savedMessageEntryIds = {};
  Future<void>? _localCacheLoad;

  Future<void> _ensureLocalCacheLoaded() {
    return _localCacheLoad ??= () async {
      _cachedSessions = await _localCache.readSessions();
      _cachedMessages.addAll(await _localCache.readAllMessages());
      _savedMessageEntryIds = await _localCache.readSavedMessageEntryIds();
    }();
  }

  @override
  Future<Either<Failure, ChatSession>> createSession({
    required String title,
  }) async {
    await _ensureLocalCacheLoaded();
    final result = await _retryAfterSilentRefreshIfExpired(
      () => _remoteDataSource.createSession(title: title),
    );
    return result.match((f) => Left(f), (session) {
      _upsertSession(session);
      unawaited(_localCache.writeSessions(_cachedSessions));
      return Right(session);
    });
  }

  @override
  Future<Either<Failure, ChatSessionsPage>> listSessions({
    String? cursor,
    int? limit,
  }) async {
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
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async {
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
  List<ChatMessage>? cachedMessages(String sessionId) =>
      _cachedMessages[sessionId];

  @override
  Future<void> setLastActiveSessionId(String? sessionId) =>
      _localCache.writeLastActiveSessionId(sessionId);

  @override
  Future<String?> get lastActiveSessionId =>
      _localCache.readLastActiveSessionId();

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage({
    required String sessionId,
    required String content,
  }) => _streamWithAuthRetry(
    () => _remoteDataSource.sendMessage(sessionId: sessionId, content: content),
  );

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage({
    required String sessionId,
    required String userMessageId,
  }) => _streamWithAuthRetry(
    () => _remoteDataSource.retryMessage(
      sessionId: sessionId,
      userMessageId: userMessageId,
    ),
  );

  @override
  String? savedEntryIdFor(String chatMessageId) =>
      _savedMessageEntryIds[chatMessageId];

  @override
  Future<void> recordMessageSaved({
    required String chatMessageId,
    required String entryId,
  }) async {
    _savedMessageEntryIds = {..._savedMessageEntryIds, chatMessageId: entryId};
    await _localCache.writeSavedMessageEntryIds(_savedMessageEntryIds);
  }

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

  /// research.md R3 — retries the whole call once, only if the *first* item
  /// is `AuthExpiredFailure` (i.e. before any `ChatStreamEvent` was ever
  /// emitted). Once any event has been emitted, a later `AuthExpiredFailure`
  /// is yielded as-is, no retry attempted.
  Stream<Either<Failure, ChatStreamEvent>> _streamWithAuthRetry(
    Stream<Either<Failure, ChatStreamEvent>> Function() call,
  ) async* {
    var stream = call();
    var canRetry = true;
    while (true) {
      var sawAnyItem = false;
      var restarted = false;
      await for (final item in stream) {
        if (!sawAnyItem &&
            canRetry &&
            item.match((f) => f is AuthExpiredFailure, (_) => false)) {
          final refreshed = await _sessionRepository.refresh();
          if (refreshed.isLeft()) {
            yield item;
            return;
          }
          canRetry = false;
          stream = call();
          restarted = true;
          break;
        }
        sawAnyItem = true;
        yield item;
      }
      if (!restarted) return;
    }
  }

  /// Keeps `_cachedSessions` ordered by `lastUserMessageAt` descending
  /// (nulls last) after every mutation — the order `cachedSessions`'
  /// offline fallback (`ChatSessionsBloc._loadFirstPage`) relies on, since
  /// the online path renders the backend's own already-ordered page instead
  /// (FR-008).
  void _upsertSession(ChatSession session) {
    final i = _cachedSessions.indexWhere((s) => s.id == session.id);
    if (i >= 0) {
      _cachedSessions[i] = session;
    } else {
      _cachedSessions = [..._cachedSessions, session];
    }
    _cachedSessions.sort((a, b) {
      final aTime = a.lastUserMessageAt;
      final bTime = b.lastUserMessageAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
  }

  @override
  Future<void> clearLocalData() async {
    _cachedSessions = [];
    _cachedMessages.clear();
    _savedMessageEntryIds = {};
    await _localCache.clear();
  }

  // Exactly one retry. If it also comes back `AuthExpiredFailure` (a
  // pathological double-expiry), that is returned as-is — no second refresh
  // attempt, no loop (same shape EntriesRepositoryImpl already uses).
  Future<Either<Failure, T>> _retryAfterSilentRefreshIfExpired<T>(
    Future<Either<Failure, T>> Function() call,
  ) async {
    final result = await call();
    return result.match(
      (f) => f is AuthExpiredFailure
          ? _retryAfterSilentRefresh(call)
          : Future.value(Left(f)),
      (v) => Future.value(Right(v)),
    );
  }

  Future<Either<Failure, T>> _retryAfterSilentRefresh<T>(
    Future<Either<Failure, T>> Function() retry,
  ) async {
    final refreshed = await _sessionRepository.refresh();
    return refreshed.match(
      (_) => Future.value(
        const Left(
          AuthExpiredFailure(
            message: 'Session could not be renewed',
            requestId: '',
          ),
        ),
      ),
      (_) => retry(),
    );
  }
}
