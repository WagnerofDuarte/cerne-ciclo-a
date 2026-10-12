import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/entities/vault_entry_mode.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

/// FR-003's "attempt biometrics first when enabled and available, otherwise
/// go straight to PIN" rule — the only place this branching is implemented
/// (contracts/vault-repository.md). Called once per `VaultPage` open.
class DetermineVaultEntryUseCase {
  const DetermineVaultEntryUseCase(this._repository);

  final VaultRepository _repository;

  Future<VaultEntryMode> call() async {
    if (!await _repository.hasPinConfigured()) {
      return VaultEntryMode.pinSetupRequired;
    }

    final capability = await _repository.checkBiometricCapability();
    final preferred = await _repository.isBiometricPreferenceEnabled();
    return (capability == BiometricCapability.available && preferred)
        ? VaultEntryMode.unlockBiometricFirst
        : VaultEntryMode.unlockPinOnly;
  }
}
