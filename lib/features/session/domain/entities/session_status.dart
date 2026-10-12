import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:equatable/equatable.dart';

/// Derived state consumed by `SessionBloc` (data-model.md Derived state).
/// `networkError` is a 5th variant beyond the 4 named in data-model.md's
/// table — required by contracts/session-repository.md's `CheckSessionUseCase`
/// pseudocode and research.md R7, so a transient connectivity failure during
/// the splash check never gets conflated with "no session" (`unauthenticated`).
sealed class SessionStatus extends Equatable {
  const SessionStatus();

  static const SessionStatus checking = SessionStatusChecking();
  static const SessionStatus unauthenticated = SessionStatusUnauthenticated();
  static const SessionStatus expiredRenewable = SessionStatusExpiredRenewable();

  static SessionStatus authenticated(Session session) =>
      SessionStatusAuthenticated(session);

  static SessionStatus networkError(Failure failure) =>
      SessionStatusNetworkError(failure);
}

class SessionStatusChecking extends SessionStatus {
  const SessionStatusChecking();

  @override
  List<Object?> get props => [];
}

class SessionStatusAuthenticated extends SessionStatus {
  const SessionStatusAuthenticated(this.session);

  final Session session;

  @override
  List<Object?> get props => [session];
}

class SessionStatusExpiredRenewable extends SessionStatus {
  const SessionStatusExpiredRenewable();

  @override
  List<Object?> get props => [];
}

class SessionStatusUnauthenticated extends SessionStatus {
  const SessionStatusUnauthenticated();

  @override
  List<Object?> get props => [];
}

class SessionStatusNetworkError extends SessionStatus {
  const SessionStatusNetworkError(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
