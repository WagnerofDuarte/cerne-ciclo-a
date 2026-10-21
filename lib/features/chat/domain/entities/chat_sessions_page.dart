import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:equatable/equatable.dart';

/// The shape of one `GET /chat/sessions` response. Directly mirrors
/// `EntriesPage` (RF01/RF07) — same shape, same "null `nextCursor` = last
/// page" convention.
class ChatSessionsPage extends Equatable {
  const ChatSessionsPage({required this.sessions, required this.nextCursor});

  /// Ordered by `lastUserMessageAt` desc (FR-008; backend-ordered).
  final List<ChatSession> sessions;

  /// `meta.nextCursor` verbatim; `null` means this was the last page.
  final String? nextCursor;

  @override
  List<Object?> get props => [sessions, nextCursor];
}
