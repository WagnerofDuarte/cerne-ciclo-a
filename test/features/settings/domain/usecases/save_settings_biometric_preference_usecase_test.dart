import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/settings/domain/usecases/save_settings_biometric_preference_usecase.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockBiometricsPreferenceRepository extends Mock
    implements BiometricsPreferenceRepository {}

class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockBiometricsPreferenceRepository biometricsPreferenceRepository;
  late MockVaultRepository vaultRepository;
  late SaveSettingsBiometricPreferenceUseCase useCase;

  setUp(() {
    biometricsPreferenceRepository = MockBiometricsPreferenceRepository();
    vaultRepository = MockVaultRepository();
    when(() => vaultRepository.setBiometricPreferenceLocally(any())).thenAnswer((_) async {});
    useCase = SaveSettingsBiometricPreferenceUseCase(
      biometricsPreferenceRepository: biometricsPreferenceRepository,
      vaultRepository: vaultRepository,
    );
  });

  test('save() -> Right calls setBiometricPreferenceLocally and returns Right(null)', () async {
    when(() => biometricsPreferenceRepository.save(true))
        .thenAnswer((_) async => const Right(null));

    final result = await useCase.call(true);

    expect(result, const Right<Failure, void>(null));
    verify(() => vaultRepository.setBiometricPreferenceLocally(true)).called(1);
  });

  test(
    'save() -> Left returns the failure untouched and does not call setBiometricPreferenceLocally',
    () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: '');
      when(() => biometricsPreferenceRepository.save(true))
          .thenAnswer((_) async => const Left(failure));

      final result = await useCase.call(true);

      expect(result, const Left<Failure, void>(failure));
      verifyNever(() => vaultRepository.setBiometricPreferenceLocally(any()));
    },
  );
}
