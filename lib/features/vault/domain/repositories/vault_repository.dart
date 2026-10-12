import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';

/// Outcome of a single `attemptBiometricAuth()` call. `failed`, `cancelled`,
/// and `notAvailable` are all routed identically by `VaultBloc` to the PIN
/// fallback (contracts/vault-repository.md) — FR-004 does not distinguish
/// "not recognized" from "user tapped away" from "biometrics became
/// unavailable mid-attempt".
enum BiometricAuthOutcome { success, failed, cancelled, notAvailable }

/// Domain-layer interface owning everything local to the device: PIN
/// storage/verification, biometric hardware capability, the local
/// biometrics-preference mirror, and the in-memory relock timestamp
/// (contracts/vault-repository.md). No `local_auth` or
/// `flutter_secure_storage` type crosses this boundary (RNF06). Registered
/// as a `get_it` `lazySingleton` — one instance for the app's process
/// lifetime, which is what lets `lastUnlockedAt`/`backgroundedAt` survive
/// navigation without a database (data-model.md Vault Lock State).
abstract class VaultRepository {
  // Device PIN
  Future<bool> hasPinConfigured();
  Future<void> savePin(String pin);
  Future<bool> verifyPin(String pin);

  // Biometric capability
  Future<BiometricCapability> checkBiometricCapability();
  Future<BiometricAuthOutcome> attemptBiometricAuth();

  // Local biometrics-preference mirror (NOT the backend's copy — research.md R6)
  Future<bool> isBiometricPreferenceEnabled();
  Future<void> setBiometricPreferenceLocally(bool enabled);

  // Vault Lock State (in-memory only, data-model.md)
  void recordBackgrounded(DateTime at);
  DateTime? consumeBackgroundedAt();
  void markUnlocked(DateTime at);
  DateTime? get lastUnlockedAt;
}
