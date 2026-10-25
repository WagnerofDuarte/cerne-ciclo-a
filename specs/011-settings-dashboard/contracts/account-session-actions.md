# Contract: Sign-out (`AuthRepository.logout()` extension) + shared post-action destination

## `AuthRepository.logout()` — extends an existing interface (research.md R8)

`features/auth/domain/repositories/auth_repository.dart` gains one method, implemented by
`AuthRepositoryImpl` via a new `AuthRemoteDataSource.logout()` calling `auth-logout` (`POST /auth/logout`,
`bearerAuth`, empty body):

```dart
Future<Either<Failure, Unit>> logout();
```

`auth-logout`'s own response is `{data: {ok: true}}`; this method returns `Right(unit)` on 200 regardless of
the `ok` value's content (unlike `account-delete`, a non-`true` `ok` here is not treated as a malformed
response worth blocking on — FR-016 already says the local session is cleared "regardless of whether that
call succeeds or fails"). `AuthRepositoryImpl.logout()` does **not** call `SecureTokenStorage`/
`SessionRepository.clear()` itself — that stays `SettingsBloc`'s job (below), so `AuthRepository` keeps its
existing shape (it has never owned session-clearing; `AuthRepositoryImpl._persistOnSuccess` only ever writes,
never deletes).

## `SettingsBloc`'s sign-out sequence (FR-016)

```
on SignOutRequested, if isSigningOut: ignore (FR-022)
set isSigningOut = true
await authRepository.logout()        // result intentionally discarded either way
await sessionRepository.clear()
await accountProfileRepository.clearCachedDisplayName()
emit SettingsState(..., signedOut: true)   // always login — see research.md R10's correction note
```
Note the `logout()` call's `Either` is awaited (so the request actually completes before local state is
wiped — avoiding a race where the app's own token is already gone when the request tries to attach it) but
never branched on; both `Left` and `Right` fall through to the same unconditional clear-and-navigate sequence
this is the one place in this unit's bloc logic where a `Left` is deliberately not surfaced as an error, per
FR-016's own explicit wording.

## Scenario table

| # | Scenario | Local state after | Navigation |
|---|---|---|---|
| 1 | `logout()` → `Right` | Session + cached name cleared | `AppRoutes.login` (always — never `AppRoutes.vault`; see research.md R10's correction note) |
| 2 | `logout()` → `Left` (timeout/offline/`AUTH_EXPIRED`/malformed) | Session + cached name cleared regardless | Same as #1 — failure never blocks the clear-and-leave sequence |
| 3 | A second `SignOutRequested` arrives while `isSigningOut == true` | No second `logout()` call (FR-022) | No second navigation |

`EntriesLocalCache`/`ChatLocalCache` are **not** cleared on sign-out (research.md R9) — only
`AccountDeletionRepository`'s success path (contracts/account-deletion-repository.md) does that.
