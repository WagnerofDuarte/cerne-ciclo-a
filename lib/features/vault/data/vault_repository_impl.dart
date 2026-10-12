import 'package:cerne/features/vault/data/local_auth_biometric_data_source.dart';
import 'package:cerne/features/vault/data/vault_secure_storage.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:flutter/services.dart';

/// Maps [LocalAuthBiometricDataSource]/`local_auth` results into
/// [BiometricCapability]/[BiometricAuthOutcome] before returning (RNF06).
/// `lastUnlockedAt`/`backgroundedAt` are held in-memory only, never
/// persisted (data-model.md Vault Lock State) — this class is registered as
/// a `get_it` `lazySingleton`, one instance for the app's process lifetime.
class VaultRepositoryImpl implements VaultRepository {
  VaultRepositoryImpl({
    required this._secureStorage,
    required this._biometricDataSource,
  });

  final VaultSecureStorage _secureStorage;
  final LocalAuthBiometricDataSource _biometricDataSource;

  DateTime? _backgroundedAt;
  DateTime? _lastUnlockedAt;

  @override
  Future<bool> hasPinConfigured() => _secureStorage.hasPinConfigured();

  @override
  Future<void> savePin(String pin) => _secureStorage.savePin(pin);

  @override
  Future<bool> verifyPin(String pin) => _secureStorage.verifyPin(pin);

  @override
  Future<BiometricCapability> checkBiometricCapability() async {
    final isSupported = await _biometricDataSource.isDeviceSupported();
    final canCheck = await _biometricDataSource.canCheckBiometrics();
    if (!isSupported || !canCheck) return BiometricCapability.noHardware;

    final enrolled = await _biometricDataSource.getAvailableBiometrics();
    if (enrolled.isNotEmpty) return BiometricCapability.available;

    // Hardware is present but nothing is currently enrolled. The local
    // biometrics-preference mirror tells us whether this device previously
    // had biometrics working for this unit (osDisabled) or never did
    // (notEnrolled) — the Edge Cases' "OS-level disable between sessions".
    final wasPreferred = await _secureStorage.readBiometricPreference();
    return wasPreferred
        ? BiometricCapability.osDisabled
        : BiometricCapability.notEnrolled;
  }

  @override
  Future<BiometricAuthOutcome> attemptBiometricAuth() async {
    try {
      final success = await _biometricDataSource.authenticate();
      return success
          ? BiometricAuthOutcome.success
          : BiometricAuthOutcome.failed;
    } on PlatformException {
      // Capability changed between DetermineVaultEntryUseCase's check and
      // this call, or some other platform-level error (contracts/vault-repository.md).
      return BiometricAuthOutcome.notAvailable;
    }
  }

  @override
  Future<bool> isBiometricPreferenceEnabled() =>
      _secureStorage.readBiometricPreference();

  @override
  Future<void> setBiometricPreferenceLocally(bool enabled) =>
      _secureStorage.writeBiometricPreference(enabled);

  @override
  void recordBackgrounded(DateTime at) => _backgroundedAt = at;

  @override
  DateTime? consumeBackgroundedAt() {
    final value = _backgroundedAt;
    _backgroundedAt = null;
    return value;
  }

  @override
  void markUnlocked(DateTime at) => _lastUnlockedAt = at;

  @override
  DateTime? get lastUnlockedAt => _lastUnlockedAt;
}
