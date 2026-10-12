# Contract: `BiometricsPreferenceRepository`
(`lib/features/vault/domain/repositories/biometrics_preference_repository.dart`)

Domain-layer interface for the one network call this unit makes. Deliberately narrow — a single
method for a single field — rather than a general-purpose account-settings repository; see "Why
this stays narrow" below.

```dart
abstract class BiometricsPreferenceRepository {
  Future<Either<Failure, void>> save(bool enabled);   // PATCH account-settings-update, body: {biometricEnabled: enabled}
}
```

- **`save`** → calls `ApiClient.call('account-settings-update', method: 'PATCH', body: {'biometricEnabled': enabled}, authMode: AuthMode.userSession)`, reusing F000's `ApiClient`/`ErrorMapper` unchanged. The OpenAPI schema for `account-settings-update` accepts `displayName`, `persona`, and `biometricEnabled` as independently-optional fields (`additionalProperties: false`, none individually `required`) — sending only `biometricEnabled` is a valid partial update, not a workaround.
- Return type is `Either<Failure, void>`, not `Either<Failure, Account>`: `SaveBiometricsPreferenceUseCase` (research.md R6) discards the result either way, so there is no reason to decode and carry the full updated-account payload the endpoint returns.
- **Caller discipline** (research.md R6, data-model.md Biometrics Preference): the caller always writes the local mirror *first*, then calls `save()` and ignores both branches of its `Either`. This repository itself does not know that — it is a plain, honestly-typed network call; the "don't block on failure" behavior lives one layer up, in the usecase, where it is independently testable without a fake clock or fake PIN state.

## Data layer

```dart
class BiometricsPreferenceRemoteDataSource {
  BiometricsPreferenceRemoteDataSource(this._apiClient);
  final ApiClient _apiClient;

  Future<Either<Failure, Map<String, dynamic>>> update({required bool biometricEnabled}) =>
      _apiClient.call(
        'account-settings-update',
        method: 'PATCH',
        body: {'biometricEnabled': biometricEnabled},
      );
}

class BiometricsPreferenceRepositoryImpl implements BiometricsPreferenceRepository {
  BiometricsPreferenceRepositoryImpl(this._remote);
  final BiometricsPreferenceRemoteDataSource _remote;

  @override
  Future<Either<Failure, void>> save(bool enabled) async =>
      (await _remote.update(biometricEnabled: enabled)).map((_) {});
}
```

## Test scenarios (contributes toward RNF09's 15/15, data-model.md Backend Failure)

Covered with `mocktail` against `BiometricsPreferenceRepositoryImpl` (mocking `ApiClient`, matching
F000's `auth_repository_impl_test.dart` pattern exactly):

1. `ApiClient.call` returns `Right({...})` → `save()` returns `Right(unit)`.
2. `ApiClient.call` returns `Left(NetworkTimeoutFailure(...))` → `save()` returns the same `Left` unchanged.
3. `ApiClient.call` returns `Left(NetworkOfflineFailure(...))` → `save()` returns the same `Left` unchanged.
4. `ApiClient.call` returns `Left(ValidationFailure(...))` → `save()` returns the same `Left` unchanged (malformed-response case).

## Why this stays narrow

FR-016 bars this unit from building any part of the Settings screen; spec.md's Assumptions say a
"dedicated toggle to change the biometrics preference later... belongs to the Settings screen built
by the RF09 unit." A general `AccountRepository.updateSettings({displayName, persona,
biometricEnabled})` would anticipate that unit's needs (`displayName`/`persona` editing) without
being asked to — the opposite problem from F000's `Failure` hierarchy, where going wide *was*
correct because the error taxonomy is closed and fully known today (F000 research.md R6). Here,
RF09's actual settings-screen shape isn't known yet, so the narrow interface is the version that
can be reused or widened later without this unit having guessed wrong.
