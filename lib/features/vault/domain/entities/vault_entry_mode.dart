/// Which branch of the vault screen `VaultPage` should show, computed once
/// per open by `DetermineVaultEntryUseCase` (data-model.md Vault Lock State).
enum VaultEntryMode { pinSetupRequired, unlockBiometricFirst, unlockPinOnly }
