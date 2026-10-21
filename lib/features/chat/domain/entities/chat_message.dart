import 'package:equatable/equatable.dart';

enum ChatRole { user, assistant }

enum ChatMessageStatus { streaming, complete, failed }

/// Matches `chat-messages-list`'s response schema field-for-field
/// (data-model.md). `seq` for an optimistic placeholder is set client-side
/// purely so the list's existing sort-by-`seq` ordering holds before the
/// server's own `seq` is known — overwritten once real data arrives.
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

  /// `'local-<timestamp>'`-prefixed until reconciled with the server's real
  /// id (research.md R5).
  final String id;
  final String sessionId;
  final ChatRole role;

  /// Grows incrementally while `status == streaming` (token deltas appended).
  final String content;
  final int seq;
  final ChatMessageStatus status;
  final int retryCount;
  final DateTime createdAt;

  bool get isOptimistic => id.startsWith('local-');

  @override
  List<Object?> get props => [
    id,
    sessionId,
    role,
    content,
    seq,
    status,
    retryCount,
    createdAt,
  ];
}
