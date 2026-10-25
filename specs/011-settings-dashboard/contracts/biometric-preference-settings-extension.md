# Contract: Settings' biometric toggle (research.md R6) — a new caller, zero changes to `vault/`

`SaveSettingsBiometricPreferenceUseCase` (`features/settings/domain/usecases/`):

```dart
class SaveSettingsBiometricPreferenceUseCase {
  const SaveSettingsBiometricPreferenceUseCase({
    required BiometricsPreferenceRepository biometricsPreferenceRepository, // vault/domain/, unmodified
    required VaultRepository vaultRepository,                               // vault/domain/, unmodified
  });

  Future<Either<Failure, void>> call(bool enabled) async {
    final result = await _biometricsPreferenceRepository.save(enabled);
    return result.match(
      (failure) => Left(failure), // local mirror left untouched — next relock still gates on the old value
      (_) async {
        await _vaultRepository.setBiometricPreferenceLocally(enabled);
        return const Right(null);
      },
    );
  }
}
```

## Reads for the toggle's initial state / visibility (`SettingsBloc`, on `SettingsOpened`)

```dart
final capability = await vaultRepository.checkBiometricCapability();
final visible = capability == BiometricCapability.available;         // FR-013's "hidden entirely" rule
final enabled = visible ? await vaultRepository.isBiometricPreferenceEnabled() : false;
```
`noHardware`/`notEnrolled`/`osDisabled` all resolve to `visible = false` — the same "all non-`available`
outcomes are routed identically" reading `VaultBloc`'s own `BiometricAuthOutcome` handling already
establishes for its own enum (RF03, contracts/vault-repository.md).

## Scenario table

| # | Scenario | `SettingsBloc` reaction |
|---|---|---|
| 1 | `checkBiometricCapability() == available` | Toggle row shown, initial value from `isBiometricPreferenceEnabled()` |
| 2 | `noHardware` / `notEnrolled` / `osDisabled` | Toggle row omitted entirely from `SettingsState` (`biometricToggleVisible = false`) — no disabled/grayed row |
| 3 | User flips the toggle; `save()` → `Right` | UI already shows the flipped value optimistically (RNF01, <100ms); `VaultRepository`'s mirror updated to match — confirmed |
| 4 | User flips the toggle; `save()` → `Left` (timeout/offline/malformed) | UI reverts to the pre-flip value, `biometricFailureMessage` set, mirror left untouched (FR-014) |
| 5 | `save()` returns `Left(AuthExpiredFailure)` after a failed silent refresh | Same revert as #4, plus `reauthRequired` fires |

This usecase is exercised with `mocktail` fakes of `BiometricsPreferenceRepository`/`VaultRepository` — no new
test doubles for `local_auth`/`flutter_secure_storage` are needed, since neither is touched directly here.
