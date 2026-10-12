import 'package:cerne/features/vault/data/local_auth_biometric_data_source.dart';
import 'package:cerne/features/vault/data/vault_repository_impl.dart';
import 'package:cerne/features/vault/data/vault_secure_storage.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockVaultSecureStorage extends Mock implements VaultSecureStorage {}

class MockLocalAuthBiometricDataSource extends Mock
    implements LocalAuthBiometricDataSource {}

void main() {
  late MockVaultSecureStorage secureStorage;
  late MockLocalAuthBiometricDataSource biometricDataSource;
  late VaultRepositoryImpl repository;

  setUp(() {
    secureStorage = MockVaultSecureStorage();
    biometricDataSource = MockLocalAuthBiometricDataSource();
    repository = VaultRepositoryImpl(
      secureStorage: secureStorage,
      biometricDataSource: biometricDataSource,
    );
  });

  group('PIN', () {
    test('savePin then verifyPin with the same value delegates and returns true', () async {
      when(() => secureStorage.savePin('1234')).thenAnswer((_) async {});
      when(() => secureStorage.verifyPin('1234')).thenAnswer((_) async => true);

      await repository.savePin('1234');
      final result = await repository.verifyPin('1234');

      expect(result, isTrue);
      verify(() => secureStorage.savePin('1234')).called(1);
    });

    test('verifyPin with a different value delegates and returns false', () async {
      when(() => secureStorage.verifyPin('0000')).thenAnswer((_) async => false);

      final result = await repository.verifyPin('0000');

      expect(result, isFalse);
    });
  });

  group('checkBiometricCapability', () {
    test('isDeviceSupported false -> noHardware', () async {
      when(() => biometricDataSource.isDeviceSupported()).thenAnswer((_) async => false);
      when(() => biometricDataSource.canCheckBiometrics()).thenAnswer((_) async => true);

      final result = await repository.checkBiometricCapability();

      expect(result, BiometricCapability.noHardware);
    });

    test('canCheckBiometrics false -> noHardware', () async {
      when(() => biometricDataSource.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => biometricDataSource.canCheckBiometrics()).thenAnswer((_) async => false);

      final result = await repository.checkBiometricCapability();

      expect(result, BiometricCapability.noHardware);
    });

    test('hardware supported, nothing enrolled, never preferred -> notEnrolled', () async {
      when(() => biometricDataSource.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => biometricDataSource.canCheckBiometrics()).thenAnswer((_) async => true);
      when(() => biometricDataSource.getAvailableBiometrics()).thenAnswer((_) async => []);
      when(() => secureStorage.readBiometricPreference()).thenAnswer((_) async => false);

      final result = await repository.checkBiometricCapability();

      expect(result, BiometricCapability.notEnrolled);
    });

    test('hardware supported, nothing enrolled, was previously preferred -> osDisabled', () async {
      when(() => biometricDataSource.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => biometricDataSource.canCheckBiometrics()).thenAnswer((_) async => true);
      when(() => biometricDataSource.getAvailableBiometrics()).thenAnswer((_) async => []);
      when(() => secureStorage.readBiometricPreference()).thenAnswer((_) async => true);

      final result = await repository.checkBiometricCapability();

      expect(result, BiometricCapability.osDisabled);
    });

    test('hardware supported and enrolled -> available', () async {
      when(() => biometricDataSource.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => biometricDataSource.canCheckBiometrics()).thenAnswer((_) async => true);
      when(() => biometricDataSource.getAvailableBiometrics())
          .thenAnswer((_) async => [BiometricType.face]);

      final result = await repository.checkBiometricCapability();

      expect(result, BiometricCapability.available);
    });
  });

  group('attemptBiometricAuth', () {
    test('authenticate() true -> success', () async {
      when(() => biometricDataSource.authenticate()).thenAnswer((_) async => true);

      final result = await repository.attemptBiometricAuth();

      expect(result, BiometricAuthOutcome.success);
    });

    test('authenticate() false -> failed', () async {
      when(() => biometricDataSource.authenticate()).thenAnswer((_) async => false);

      final result = await repository.attemptBiometricAuth();

      expect(result, BiometricAuthOutcome.failed);
    });

    test('authenticate() throws PlatformException -> notAvailable', () async {
      when(() => biometricDataSource.authenticate())
          .thenThrow(PlatformException(code: 'NotAvailable'));

      final result = await repository.attemptBiometricAuth();

      expect(result, BiometricAuthOutcome.notAvailable);
    });
  });

  group('Vault Lock State', () {
    test('recordBackgrounded/consumeBackgroundedAt: one resume evaluates the gap only once', () {
      final at = DateTime(2026, 1, 1, 12);

      repository.recordBackgrounded(at);

      expect(repository.consumeBackgroundedAt(), at);
      expect(repository.consumeBackgroundedAt(), isNull);
    });

    test('markUnlocked/lastUnlockedAt', () {
      expect(repository.lastUnlockedAt, isNull);

      final at = DateTime(2026, 1, 1, 12);
      repository.markUnlocked(at);

      expect(repository.lastUnlockedAt, at);
    });
  });
}
