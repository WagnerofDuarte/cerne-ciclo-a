/// On-device biometric hardware/enrollment state (data-model.md Biometric
/// Capability). No `local_auth` type crosses into `domain/` — `VaultRepositoryImpl`
/// maps its result into this enum (RNF06).
enum BiometricCapability { available, noHardware, notEnrolled, osDisabled }
