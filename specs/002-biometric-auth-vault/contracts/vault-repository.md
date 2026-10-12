# Contract: `VaultRepository` (`lib/features/vault/domain/repositories/vault_repository.dart`)

Domain-layer interface owning everything local to the device: PIN storage/verification, biometric
hardware capability, the local biometrics-preference mirror, and the in-memory relock timestamp.
`VaultBloc` and the lifecycle observer depend on this and on nothing in `vault/data/` directly
(RNF06). Registered as a `get_it` `lazySingleton` — one instance for the app's process lifetime,
which is what lets `lastUnlockedAt`/`backgroundedAt` survive navigation without a database
(data-model.md Vault Lock State).

```dart
abstract class VaultRepository {
  // Device PIN
  Future<bool> hasPinConfigured();
  Future<void> savePin(String pin);          // hashes internally (research.md R2); overwrites any prior value
  Future<bool> verifyPin(String pin);         // hashes the input, compares to the stored digest

  // Biometric capability (local_auth never crosses this boundary — see data-model.md)
  Future<BiometricCapability> checkBiometricCapability();
  Future<BiometricAuthOutcome> attemptBiometricAuth();   // success | failed | cancelled | notAvailable

  // Local biometrics-preference mirror (NOT the backend's copy — research.md R6)
  Future<bool> isBiometricPreferenceEnabled();
  Future<void> setBiometricPreferenceLocally(bool enabled);

  // Vault Lock State (in-memory only, data-model.md)
  void recordBackgrounded(DateTime at);
  DateTime? consumeBackgroundedAt();          // reads then clears, so one resume only ever evaluates once
  void markUnlocked(DateTime at);
  DateTime? get lastUnlockedAt;
}
```

- **`hasPinConfigured`/`savePin`/`verifyPin`** → back `DetermineVaultEntryUseCase`,
  `SavePinUseCase`, `VerifyPinUseCase`. None return `Either<Failure, T>` — research.md R5 covers
  why a local hash mismatch or "no PIN yet" is not a backend-taxonomy `Failure`.
- **`checkBiometricCapability`** → called once per `VaultPage` open (not cached across process
  lifetime, since the Edge Cases require detecting an OS-level biometric change *between*
  sessions — e.g. the user disabled Face ID in iOS Settings since the last launch).
- **`attemptBiometricAuth`** → wraps `LocalAuthBiometricDataSource.authenticate(biometricOnly:
  true)` (research.md R1); `cancelled`, `failed`, and `notAvailable` are all routed to the same
  PIN-fallback UI by `VaultBloc` (FR-004 does not distinguish "not recognized" from "user tapped
  away" from "biometrics became unavailable mid-attempt" — e.g. an iOS biometric lockout after
  repeated failures, or the OS capability changing between `DetermineVaultEntryUseCase`'s check and
  the actual `authenticate()` call). `notAvailable` is a real, reachable outcome of this method even
  though `DetermineVaultEntryUseCase` only enters `unlockBiometricFirst` when capability was
  `available` moments earlier — the two calls are not atomic.
- **`isBiometricPreferenceEnabled`/`setBiometricPreferenceLocally`** → the *local* mirror
  `DetermineVaultEntryUseCase` actually reads; kept separate from `BiometricsPreferenceRepository`
  (which only ever writes to the backend, never reads) per research.md R6.
- **`recordBackgrounded`/`consumeBackgroundedAt`** → `VaultLifecycleObserver` calls these directly
  on pause/resume; `consumeBackgroundedAt` clears the stored value so a second rapid resume isn't
  double-counted against a background period that's already been evaluated.
- **`markUnlocked`/`lastUnlockedAt`** → `lastUnlockedAt` exists for observability/tests; the actual
  relock decision only needs `backgroundedAt` vs. "now" (data-model.md's
  `EvaluateBackgroundResumeUseCase`), not a comparison against `lastUnlockedAt` — the background
  gap itself is what's timed, not time-since-unlock, so a user who re-locks, re-unlocks, then
  backgrounds again immediately starts a fresh gap correctly.

## `DetermineVaultEntryUseCase` (orchestration, domain layer)

```dart
Future<VaultEntryMode> call() async {
  if (!await repo.hasPinConfigured()) return VaultEntryMode.pinSetupRequired;

  final capability = await repo.checkBiometricCapability();
  final preferred = await repo.isBiometricPreferenceEnabled();
  return (capability == BiometricCapability.available && preferred)
      ? VaultEntryMode.unlockBiometricFirst
      : VaultEntryMode.unlockPinOnly;
}
```

This is the only place FR-003's "attempt biometrics first when enabled and available, otherwise go
straight to PIN" rule is implemented — `VaultBloc` calls it once per `VaultPage` open and never
re-derives the branching itself.

## Who depends on this

`VaultBloc` (both setup and unlock sub-states), `VaultLifecycleObserver` (background/resume
timing), `SaveBiometricsPreferenceUseCase` (writes the local mirror before firing the backend
call). No `presentation/` widget calls `VaultRepository` directly — always through a usecase or
through `VaultBloc`.
