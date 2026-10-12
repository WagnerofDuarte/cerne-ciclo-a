import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';

/// The only place FR-009's "renew first, then route" rule is implemented
/// (contracts/session-repository.md's `CheckSessionUseCase` pseudocode) —
/// `SplashPage`/`SessionBloc` call this; later units never re-derive it.
class CheckSessionUseCase {
  const CheckSessionUseCase(this._repository);

  final SessionRepository _repository;

  Future<SessionStatus> call() async {
    if (!await _repository.hasStoredSession()) {
      return SessionStatus.unauthenticated;
    }

    final checked = await _repository.checkSession();
    return checked.match(
      (failure) => switch (failure) {
        AuthExpiredFailure() => _tryRefresh(),
        AuthInvalidFailure() => _signOut(),
        _ => SessionStatus.networkError(failure),
      },
      (session) => SessionStatus.authenticated(session),
    );
  }

  Future<SessionStatus> _tryRefresh() async {
    final refreshed = await _repository.refresh();
    if (refreshed.isLeft()) {
      return _signOut();
    }
    return SessionStatus.authenticated(refreshed.toNullable()!);
  }

  // AUTH_INVALID means the token itself is rejected (e.g. the account no
  // longer exists) — unlike AUTH_EXPIRED, refreshing it cannot help, so this
  // goes straight to unauthenticated instead of being left in networkError's
  // "retry" loop, which would repeat the same 401 forever.
  Future<SessionStatus> _signOut() async {
    await _repository.clear();
    return SessionStatus.unauthenticated;
  }
}
