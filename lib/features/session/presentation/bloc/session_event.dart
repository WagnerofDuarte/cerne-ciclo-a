import 'package:equatable/equatable.dart';

sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched by `SplashPage` on launch — drives FR-009's check-then-route.
class AppStarted extends SessionEvent {
  const AppStarted();
}

/// Raised by any authenticated call elsewhere in the app that comes back
/// `AUTH_EXPIRED` (FR-013, User Story 5).
class AuthExpiredDetected extends SessionEvent {
  const AuthExpiredDetected();
}
