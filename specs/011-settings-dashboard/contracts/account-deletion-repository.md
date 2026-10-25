# Contract: `AccountDeletionRepository`

`features/settings/domain/repositories/account_deletion_repository.dart`, implemented by
`AccountDeletionRepositoryImpl` (`features/settings/data/`), backed by
`AccountDeletionRemoteDataSource` calling `account-delete` (`DELETE /account`).

```dart
abstract class AccountDeletionRepository {
  Future<Either<Failure, Unit>> deleteAccount();
}
```

## Behavior

Always sends `{"confirmation": "DELETE"}` — the literal value the backend requires, supplied by the app
itself (FR-018); there is no caller-supplied parameter for it, so it is structurally impossible for this
method to ever send anything else. No retry-on-`AuthExpiredFailure` here: an expired session during the
delete-confirmation dialog is exactly spec.md's own Edge Case ("the session expires while Settings is open...
a confirmation dialog open") — the existing expired-session overlay takes over and the user re-authenticates
before retrying the tap, rather than this method silently refreshing and re-sending a destructive request
behind an overlay the user hasn't acknowledged yet. A plain `AuthExpiredFailure` `Left` surfaces through
`SettingsState.deleteFailureMessage` like any other failure and also fires `reauthRequired`.

## What `SettingsBloc` does around a `Right` result (research.md R9) — not this repository's job

On `Right(unit)`: `SessionRepository.clear()`, `AccountProfileLocalCache.clearCachedDisplayName()`,
`EntriesRepository.clearLocalData()`, `ChatRepository.clearLocalData()`, then set `accountDeleted = true`,
which `SettingsPage` always navigates to `AppRoutes.login` for — never the vault (R10's original
`hasPinConfigured()`-gated vault destination was superseded; see research.md R10's correction note. There is
no account left for a vault unlock to gate into). `VaultSecureStorage`'s PIN hash and biometrics-preference
mirror are deliberately **not** touched (research.md R9).

## Scenario table (RNF09 — new write endpoint)

| # | Scenario | Expected `Either` | Account state after |
|---|---|---|---|
| 1 | 200 `{data: {ok: true}}` | `Right(unit)` | Backend account gone; app clears local state (above) |
| 2 | Dio timeout | `Left(NetworkTimeoutFailure)` | Untouched — dialog shows retryable error (FR-020) |
| 3 | No connection | `Left(NetworkOfflineFailure)` | Untouched |
| 4 | 200 with a malformed body (`data.ok` missing/not `true`) | `Left(ValidationFailure)` | Untouched — never reports success on an ambiguous response |
| 5 | 401 `AUTH_EXPIRED` | `Left(AuthExpiredFailure)`, `reauthRequired` fires | Untouched |

## `SettingsBloc`'s own guard around this call (FR-022)

`isDeletingAccount` is checked and set to `true` before the call; a second `DeleteAccountConfirmed` event
while it is already `true` is dropped without calling this repository a second time (research.md R12) — same
shape as the `isSigningOut` guard around `AuthRepository.logout()`.
