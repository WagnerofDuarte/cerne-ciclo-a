import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/entities/vault_entry_mode.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/determine_vault_entry_usecase.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockVaultRepository repository;
  late DetermineVaultEntryUseCase useCase;

  setUp(() {
    repository = MockVaultRepository();
    useCase = DetermineVaultEntryUseCase(repository);
  });

  test('no PIN configured -> pinSetupRequired', () async {
    when(() => repository.hasPinConfigured()).thenAnswer((_) async => false);

    final result = await useCase();

    expect(result, VaultEntryMode.pinSetupRequired);
    verifyNever(() => repository.checkBiometricCapability());
  });

  test(
    'PIN exists, biometric available, preferred -> unlockBiometricFirst',
    () async {
      when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
      when(() => repository.checkBiometricCapability())
          .thenAnswer((_) async => BiometricCapability.available);
      when(() => repository.isBiometricPreferenceEnabled())
          .thenAnswer((_) async => true);

      final result = await useCase();

      expect(result, VaultEntryMode.unlockBiometricFirst);
    },
  );

  test(
    'PIN exists, biometric available, not preferred -> unlockPinOnly',
    () async {
      when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
      when(() => repository.checkBiometricCapability())
          .thenAnswer((_) async => BiometricCapability.available);
      when(() => repository.isBiometricPreferenceEnabled())
          .thenAnswer((_) async => false);

      final result = await useCase();

      expect(result, VaultEntryMode.unlockPinOnly);
    },
  );

  test('PIN exists, biometric unavailable -> unlockPinOnly', () async {
    when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
    when(() => repository.checkBiometricCapability())
        .thenAnswer((_) async => BiometricCapability.noHardware);
    when(() => repository.isBiometricPreferenceEnabled())
        .thenAnswer((_) async => true);

    final result = await useCase();

    expect(result, VaultEntryMode.unlockPinOnly);
  });
}
