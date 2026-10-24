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

/// App-level backgrounding/resume, drawer open/close, or a Records/Settings
/// push/pop — all treated identically (research.md R10, FR-010).
class ChatForegroundChanged extends ChatEvent {
  const ChatForegroundChanged(this.isForegrounded);

  final bool isForegrounded;

  @override
  List<Object?> get props => [isForegrounded];
}

/// The 2-minute inactivity `Timer` elapsed (research.md R4, FR-001b).
class InsightInactivityTimerFired extends ChatEvent {
  const InsightInactivityTimerFired(this.firedAt);

  final DateTime firedAt;

  @override
  List<Object?> get props => [firedAt];
}

/// Tapping a visible insight card's "x" (FR-008).
class InsightDismissed extends ChatEvent {
  const InsightDismissed();
}
