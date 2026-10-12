import 'package:local_auth/local_auth.dart';

/// Thin wrapper over `local_auth`'s [LocalAuthentication] — the only file in
/// this unit allowed to import `local_auth` types (RNF06). `VaultRepositoryImpl`
/// maps its results into [BiometricCapability]/[BiometricAuthOutcome] before
/// they ever reach `domain/` (data-model.md).
class LocalAuthBiometricDataSource {
  LocalAuthBiometricDataSource({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  Future<bool> canCheckBiometrics() => _localAuth.canCheckBiometrics;

  Future<bool> isDeviceSupported() => _localAuth.isDeviceSupported();

  Future<List<BiometricType>> getAvailableBiometrics() =>
      _localAuth.getAvailableBiometrics();

  /// `authenticate(biometricOnly: true)` (research.md R1) — never falls back
  /// to the iOS device passcode, only this app's own PIN (FR-004).
  Future<bool> authenticate() => _localAuth.authenticate(
        localizedReason: 'Toque para desbloquear',
        options: const AuthenticationOptions(biometricOnly: true),
      );
}
