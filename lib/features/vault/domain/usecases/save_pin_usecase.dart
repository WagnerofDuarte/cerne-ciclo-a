import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

/// Thin delegation to [VaultRepository.savePin]. The 4-digit value given
/// must already satisfy "exactly 4 digits, each 0-9" (data-model.md Device
/// PIN validation rule) — the bloc enforces this before calling; this
/// usecase does not re-validate.
class SavePinUseCase {
  const SavePinUseCase(this._repository);

  final VaultRepository _repository;

  Future<void> call(String pin) => _repository.savePin(pin);
}
