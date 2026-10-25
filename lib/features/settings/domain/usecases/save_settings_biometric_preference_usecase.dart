import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Settings' own await-then-mirror-or-revert biometric write path
/// (research.md R6, contracts/biometric-preference-settings-extension.md) —
/// the opposite contract from `vault/`'s own
/// `SaveBiometricsPreferenceUseCase`, which is deliberately fire-and-forget.
/// A new caller of `vault/domain/`'s existing repositories; neither is
/// modified.
class SaveSettingsBiometricPreferenceUseCase {
  const SaveSettingsBiometricPreferenceUseCase({
    required this._biometricsPreferenceRepository,
    required this._vaultRepository,
  });

  final BiometricsPreferenceRepository _biometricsPreferenceRepository;
  final VaultRepository _vaultRepository;

  Future<Either<Failure, void>> call(bool enabled) async {
    final result = await _biometricsPreferenceRepository.save(enabled);
    return result.match(
      // Local mirror left untouched — next relock still gates on the old
      // value.
      (failure) => Future.value(Left(failure)),
      (_) async {
        await _vaultRepository.setBiometricPreferenceLocally(enabled);
        return const Right(null);
      },
    );
  }
}
