import 'package:equatable/equatable.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched once by `app_router.dart`'s `/home` route builder, right after
/// `ChatBloc` is constructed — resumes `lastActiveSessionId`, or shows the
/// empty state if none exists.
class ChatStarted extends ChatEvent {
  const ChatStarted();
}

/// Tapping a past conversation in the side menu.
class ConversationSelected extends ChatEvent {
  const ConversationSelected(this.sessionId);

  final String sessionId;

  @override
  List<Object?> get props => [sessionId];
}

/// Tapping "Novo Chat" — drops `sessionId`/`messages`, shows the empty,
/// ready-to-send state. No repository call (FR-010).
class NewConversationRequested extends ChatEvent {
  const NewConversationRequested();
}

/// The composer's send tap.
class MessageSubmitted extends ChatEvent {
  const MessageSubmitted(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// Tapping a `failed` message bubble.
class MessageRetryRequested extends ChatEvent {
  const MessageRetryRequested(this.userMessageId);

  final String userMessageId;

  @override
  List<Object?> get props => [userMessageId];
}

/// Tapping a user message's bookmark control.
class BookmarkTapped extends ChatEvent {
  const BookmarkTapped(this.messageId);

  final String messageId;

  @override
  List<Object?> get props => [messageId];
}

/// Internal — fired by the `ConnectivityChecker.onConnectivityChanged`
/// subscription `ChatBloc` opens in its constructor (research.md R8).
class ChatConnectivityChanged extends ChatEvent {
  const ChatConnectivityChanged(this.isOnline);

  final bool isOnline;

  @override
  List<Object?> get props => [isOnline];
}
