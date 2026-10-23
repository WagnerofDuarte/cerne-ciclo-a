import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_status.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:equatable/equatable.dart';

sealed class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

/// Only while resuming `lastActiveSessionId` on `ChatStarted`.
class ChatLoading extends ChatState {
  const ChatLoading();
}

/// Everything else — an existing conversation, the empty "Novo Chat" state,
/// or an outright load failure with nothing cached to fall back to — are all
/// one state shape so the screen never has to discard/rebuild its
/// `Scaffold`/`AppBar` switching between them.
class ChatReady extends ChatState {
  const ChatReady({
    required this.sessionId,
    required this.messages,
    required this.isOffline,
    required this.awaitingResponse,
    this.loadFailure,
    this.bookmarks = const {},
  });

  /// `null` = empty conversation, no session created yet (FR-010).
  final String? sessionId;

  /// `[]` for an empty conversation.
  final List<ChatMessage> messages;
  final bool isOffline;

  /// research.md R9 — gates the composer, true during a send/retry turn.
  final bool awaitingResponse;

  /// Set only when selecting an existing session's history failed outright
  /// **and** nothing is cached for it (Clarification 3's no-content edge
  /// case).
  final Failure? loadFailure;

  /// Per-message bookmark sub-state, keyed by `ChatMessage.id` — an absent
  /// key means `BookmarkStatus.idle` (research.md R5).
  final Map<String, BookmarkStatus> bookmarks;

  bool get canSend => !isOffline && !awaitingResponse && loadFailure == null;

  BookmarkStatus bookmarkStatusFor(String messageId) =>
      bookmarks[messageId] ?? BookmarkStatus.idle;

  static const _unset = Object();

  ChatReady copyWith({
    String? sessionId,
    bool clearSessionId = false,
    List<ChatMessage>? messages,
    bool? isOffline,
    bool? awaitingResponse,
    Object? loadFailure = _unset,
    Map<String, BookmarkStatus>? bookmarks,
  }) {
    return ChatReady(
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      messages: messages ?? this.messages,
      isOffline: isOffline ?? this.isOffline,
      awaitingResponse: awaitingResponse ?? this.awaitingResponse,
      loadFailure: identical(loadFailure, _unset)
          ? this.loadFailure
          : loadFailure as Failure?,
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }

  @override
  List<Object?> get props => [
    sessionId,
    messages,
    isOffline,
    awaitingResponse,
    loadFailure,
    bookmarks,
  ];
}
