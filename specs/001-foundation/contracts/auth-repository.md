# Contract: `AuthRepository` (`lib/features/auth/domain/repositories/auth_repository.dart`)

Domain-layer interface; `AuthBloc` (presentation) depends on this and on nothing in `auth/data/`
directly (RNF06).

```dart
abstract class AuthRepository {
  Future<Either<Failure, Session>> signUp({required String email, required String password});
  Future<Either<Failure, Session>> login({required String email, required String password});
}
```

- **`signUp`** → calls `auth-signup` (`AuthMode.anonKey`). Maps to FR-006. On `Right`, the use case
  persists the returned `Session` via `SecureTokenStorage` before the bloc emits its authenticated
  state — sign-up and login leave the app in an identical post-condition (spec.md User Story 2).
- **`login`** → calls `auth-login` (`AuthMode.anonKey`). Maps to FR-007. Same persistence step.
- Both return `Left(ValidationFailure)` for a malformed submission, `Left(AuthInvalidFailure)` for
  wrong credentials / already-registered email, `Left(NetworkTimeoutFailure)` /
  `Left(NetworkOfflineFailure)` for connectivity problems — never a thrown exception (FR-003).
- Empty-field submissions never reach this interface at all — the presentation layer validates and
  blocks the call before invoking it (Edge Cases: "no network call made").

## Use cases wrapping this repository

- `SignUpUseCase(AuthRepository)` / `LoginUseCase(AuthRepository)` — thin pass-throughs today, kept
  as separate classes (not inlined into the bloc) so later units' tests and the domain-coverage
  gate (RNF07) have a single, directly-testable unit per operation, independent of bloc wiring.

## Who depends on this

`AuthBloc` only, in this unit. The interface is intentionally narrow (no `logout`, no
`refresh` — those belong to `SessionRepository` below, since they are session-lifecycle concerns
rather than "an account submits credentials") — this keeps the boundary RF10's note about "a shared
interface / use case, never a directly imported repository" generalizes to: every feature talks to
auth/session through these two interfaces, never through each other's `data/` classes.
