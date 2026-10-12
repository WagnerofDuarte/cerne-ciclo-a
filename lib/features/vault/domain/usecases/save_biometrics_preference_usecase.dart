import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

/// The 3-step write path from data-model.md Biometrics Preference
/// (FR-013/FR-014): the local mirror is written synchronously first, the
/// network write is fired and its `Either` result discarded either way, and
/// this usecase always completes regardless of that outcome — "proceed
/// locally and retry in the background" (Clarifications; research.md R6).
class SaveBiometricsPreferenceUseCase {
  const SaveBiometricsPreferenceUseCase({
    required this._vaultRepository,
    required this._biometricsPreferenceRepository,
  });

  final VaultRepository _vaultRepository;
  final BiometricsPreferenceRepository _biometricsPreferenceRepository;

  Future<void> call(bool enabled) async {
    await _vaultRepository.setBiometricPreferenceLocally(enabled);
    await _biometricsPreferenceRepository.save(enabled);
  }
}
