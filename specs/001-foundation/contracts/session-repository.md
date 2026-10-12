# Contract: `SessionRepository` (`lib/features/session/domain/repositories/session_repository.dart`)

Domain-layer interface owning the session lifecycle: launch-time check, silent refresh, and
reading/clearing the stored session. `SessionBloc` depends on this and on nothing in
`session/data/` or `auth/data/` directly (RNF06).

```dart
abstract class SessionRepository {
  Future<Either<Failure, Session>> checkSession();     // GET auth-session, using the stored accessToken
  Future<Either<Failure, Session>> refresh();           // POST auth-refresh, using the stored refreshToken
  Future<void> persist(Session session);                 // write-through to SecureTokenStorage
  Future<void> clear();                                   // logout / failed-refresh cleanup
  Future<bool> hasStoredSession();                        // true iff a refreshToken is present on device
}
```

- **`checkSession`** → FR-009's first step. `Left(AuthExpiredFailure)` is the expected, non-error
  trigger for the caller (`CheckSessionUseCase`) to then call `refresh()` — not itself a terminal
  failure shown to the user.
- **`refresh`** → FR-009's renewal step, also reused for the silent-refresh-before-overlay path of
  FR-013 (User Story 5) and for any later unit's authenticated call that comes back
  `AUTH_EXPIRED`. On `Right`, calls `persist()` internally before returning.
- **`persist`/`clear`** → thin wrappers over `SecureTokenStorage`; exposed on the repository (not
  the data source) so the domain layer's use cases never import `storage/` directly.
- **`hasStoredSession`** → lets `CheckSessionUseCase` skip the network call entirely when there is
  nothing to check (Edge Cases / User Story 3 scenario 2: no stored session → straight to login,
  no call made).

## `CheckSessionUseCase` (orchestration, domain layer)

```dart
Future<SessionStatus> call() async {
  if (!await repo.hasStoredSession()) return SessionStatus.unauthenticated;
  final checked = await repo.checkSession();
  return checked.match(
    (failure) => failure is AuthExpiredFailure
        ? _tryRefresh()
        : SessionStatus.networkError(failure),      // R7 — splash retry affordance, not a route change
    (session) => SessionStatus.authenticated(session),
  );
}

Future<SessionStatus> _tryRefresh() async {
  final refreshed = await repo.refresh();
  return refreshed.match(
    (failure) async { await repo.clear(); return SessionStatus.unauthenticated; },
    (session) => SessionStatus.authenticated(session),
  );
}
```

This single use case is what `SplashPage`/`SessionBloc` calls — it is the only place FR-009's
"renew first, then route" rule is implemented, so later units never re-derive it.

## Who depends on this

`SessionBloc` (splash routing, FR-010; expired-session overlay trigger, FR-013/FR-014). Every later
unit that makes an authenticated call and receives `AuthExpiredFailure` calls `SessionRepository
.refresh()` the same way, through this interface — never by re-implementing the refresh call.
