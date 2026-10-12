import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

/// Thin delegation to [VaultRepository.verifyPin].
class VerifyPinUseCase {
  const VerifyPinUseCase(this._repository);

  final VaultRepository _repository;

  Future<bool> call(String pin) => _repository.verifyPin(pin);
}
