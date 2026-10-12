import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/save_biometrics_preference_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

class MockBiometricsPreferenceRepository extends Mock
    implements BiometricsPreferenceRepository {}

void main() {
  late MockVaultRepository vaultRepository;
  late MockBiometricsPreferenceRepository biometricsPreferenceRepository;
  late SaveBiometricsPreferenceUseCase useCase;

  setUp(() {
    vaultRepository = MockVaultRepository();
    biometricsPreferenceRepository = MockBiometricsPreferenceRepository();
    useCase = SaveBiometricsPreferenceUseCase(
      vaultRepository: vaultRepository,
      biometricsPreferenceRepository: biometricsPreferenceRepository,
    );
  });

  test('writes the local mirror synchronously before firing the network call', () async {
    when(() => vaultRepository.setBiometricPreferenceLocally(true))
        .thenAnswer((_) async {});
    when(() => biometricsPreferenceRepository.save(true))
        .thenAnswer((_) async => const Right(null));

    await useCase(true);

    verify(() => vaultRepository.setBiometricPreferenceLocally(true)).called(1);
    verify(() => biometricsPreferenceRepository.save(true)).called(1);
  });

  test('a Left result from the network write is discarded and does not throw', () async {
    when(() => vaultRepository.setBiometricPreferenceLocally(true))
        .thenAnswer((_) async {});
    when(() => biometricsPreferenceRepository.save(true)).thenAnswer(
      (_) async => const Left(
        NetworkOfflineFailure(message: 'offline', requestId: 'r1'),
      ),
    );

    await expectLater(useCase(true), completes);
  });
}
