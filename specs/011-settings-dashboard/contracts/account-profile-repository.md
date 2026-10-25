# Contract: `AccountProfileRepository`

`features/settings/domain/repositories/account_profile_repository.dart`, implemented by
`AccountProfileRepositoryImpl` (`features/settings/data/`), backed by
`AccountSettingsRemoteDataSource.updateDisplayName()` (`PATCH account-settings-update`, body
`{"displayName": name}` only) and `AccountProfileLocalCache` (Keychain-backed, one key,
`flutter_secure_storage`, same pattern as `VaultSecureStorage`).

```dart
abstract class AccountProfileRepository {
  Future<String?> readCachedDisplayName();
  Future<Either<Failure, String>> updateDisplayName(String name);
  Future<void> clearCachedDisplayName();
}
```

## Behavior

- `readCachedDisplayName()` — local-only, no network, no `Either` (nothing here can fail in a way the caller
  must branch on beyond "was it ever set").
- `updateDisplayName(name)` — client-side validation (`AccountProfile.isValidDisplayName`) happens in
  `SettingsBloc` *before* this is called, per FR-011 ("no backend call is made"); this method itself always
  sends the request. On `Right`, the response's own `data.displayName` (not the caller's input string
  verbatim) is what gets written to `AccountProfileLocalCache` and returned — defensive against the backend
  ever normalizing the value (e.g. trimming), so the cache can never drift from what the server actually
  confirmed.
- `clearCachedDisplayName()` — deletes the one Keychain key; called by both the logout and account-deletion
  flows (research.md R9).

## Scenario table (RNF09 — `account-settings-update` is a write endpoint; this unit extends its existing
coverage, RF03 having already covered the `biometricEnabled`-only body shape)

| # | Scenario | Expected `Either` | Local cache after |
|---|---|---|---|
| 1 | 200, `displayName` 1–80 chars | `Right(name)` | Written |
| 2 | Dio timeout | `Left(NetworkTimeoutFailure)` | Unchanged |
| 3 | No connection | `Left(NetworkOfflineFailure)` | Unchanged |
| 4 | 200 with a malformed body (`displayName` missing from the response) | `Left(ValidationFailure)` | Unchanged |
| 5 | 401 `AUTH_EXPIRED`, silent refresh succeeds | retried call's own result | per retried outcome |
| 6 | 401 `AUTH_EXPIRED`, silent refresh fails | `Left(AuthExpiredFailure)`, `reauthRequired` fires | Unchanged |

`SettingsBloc`'s own handling (not this repository's job) keeps `nameDraft`/edit mode intact on any `Left`
(FR-012) and returns the field to `viewing` mode showing the confirmed name only on a `Right`.
