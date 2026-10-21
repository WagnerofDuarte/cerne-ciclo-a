import 'package:equatable/equatable.dart';

sealed class ChatSessionsEvent extends Equatable {
  const ChatSessionsEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched once when `ChatSessionsBloc` is constructed (the drawer's very
/// first open).
class SessionsStarted extends ChatSessionsEvent {
  const SessionsStarted();
}

/// `Scaffold.onDrawerChanged(true)` on every subsequent open (research.md
/// R7) — refetches page 1, keeps any already-loaded further pages' sessions
/// merged in by id.
class SessionsRefreshRequested extends ChatSessionsEvent {
  const SessionsRefreshRequested();
}

/// Scroll-to-bottom of the "CONVERSAS" section (FR-008).
class SessionsNextPageRequested extends ChatSessionsEvent {
  const SessionsNextPageRequested();
}

/// The inline retry affordance on a failed page-list fetch.
class SessionsPageLoadRetried extends ChatSessionsEvent {
  const SessionsPageLoadRetried();
}
