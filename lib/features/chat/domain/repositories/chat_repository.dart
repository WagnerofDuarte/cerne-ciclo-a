import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_sessions_page.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:fpdart/fpdart.dart';

/// The shared seam `ChatBloc`/`ChatSessionsBloc` depend on (data-model.md,
/// contracts/chat-repository.md). Registered as a `get_it` `lazySingleton`
/// so [cachedSessions]/[cachedMessages] survive across screen rebuilds.
abstract class ChatRepository {
  /// `POST /chat/sessions` (`chat-sessions-create`). Retries exactly once
  /// through `SessionRepository.refresh()` on `AuthExpiredFailure` (same
  /// shape as every other non-streaming call in this codebase).
  Future<Either<Failure, ChatSession>> createSession({required String title});

  /// `GET /chat/sessions` (`chat-sessions-list`), ordered by
  /// `lastUserMessageAt` desc (FR-008).
  Future<Either<Failure, ChatSessionsPage>> listSessions({
    String? cursor,
    int? limit,
  });

  /// Every session returned by any successful [listSessions] call this
  /// process has made, backed by `ChatLocalCache` so it survives a restart
  /// (research.md R4) — the offline fallback `ChatSessionsBloc` reads when a
  /// fetch fails outright.
  List<ChatSession> get cachedSessions;

  /// `GET /chat/sessions/:id/messages` (`chat-messages-list`), ordered by
  /// `seq`.
  Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId);

  /// The last successfully-fetched message list for [sessionId], or `null`
  /// if this session's history has never been fetched while online
  /// (research.md R4/Clarification 3) — `null` is the signal `ChatBloc` uses
  /// to show the "standard no-connection state" instead of any content when
  /// selecting it while offline.
  List<ChatMessage>? cachedMessages(String sessionId);

  /// Persists which conversation to resume on next app open
  /// (spec.md Assumptions).
  Future<void> setLastActiveSessionId(String? sessionId);
  Future<String?> get lastActiveSessionId;

  /// `POST /chat/sessions/:id/messages` (`chat-messages-send`), SSE. Retries
  /// the whole call exactly once via `SessionRepository.refresh()` only if
  /// the very first emitted item is `AuthExpiredFailure` (research.md R3).
  Stream<Either<Failure, ChatStreamEvent>> sendMessage({
    required String sessionId,
    required String content,
  });

  /// `POST /chat/sessions/:id/messages/:userMessageId/retry`
  /// (`chat-messages-retry`), SSE. Same retry-once-if-first-frame-fails
  /// shape as [sendMessage] (research.md R3).
  Stream<Either<Failure, ChatStreamEvent>> retryMessage({
    required String sessionId,
    required String userMessageId,
  });

  /// FR-008's device-local, best-effort "already saved" record, keyed by
  /// `ChatMessage.id`. Not the source of correctness (research.md R1) — the
  /// backend's own `entries-create` idempotency is. Safe to read only after
  /// this session's local-cache load has resolved, the same guarantee every
  /// other `ChatRepositoryImpl` method already awaits internally.
  String? savedEntryIdFor(String chatMessageId);

  /// Persists [entryId] against [chatMessageId] in the record above — called
  /// once per successful chat-sourced entry creation.
  Future<void> recordMessageSaved({
    required String chatMessageId,
    required String entryId,
  });
}
