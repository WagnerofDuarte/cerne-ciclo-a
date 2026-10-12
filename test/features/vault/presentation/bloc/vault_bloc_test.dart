import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/determine_vault_entry_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_biometrics_preference_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_pin_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/verify_pin_usecase.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_event.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_state.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

class MockBiometricsPreferenceRepository extends Mock
    implements BiometricsPreferenceRepository {}

const _biometricFailureMessage = 'Não foi possível reconhecer — digite seu PIN';

void main() {
  late MockVaultRepository repository;
  late MockBiometricsPreferenceRepository biometricsPreferenceRepository;
  late DetermineVaultEntryUseCase determineVaultEntryUseCase;
  late VerifyPinUseCase verifyPinUseCase;
  late SavePinUseCase savePinUseCase;
  late SaveBiometricsPreferenceUseCase saveBiometricsPreferenceUseCase;

  setUp(() {
    repository = MockVaultRepository();
    biometricsPreferenceRepository = MockBiometricsPreferenceRepository();
    determineVaultEntryUseCase = DetermineVaultEntryUseCase(repository);
    verifyPinUseCase = VerifyPinUseCase(repository);
    savePinUseCase = SavePinUseCase(repository);
    saveBiometricsPreferenceUseCase = SaveBiometricsPreferenceUseCase(
      vaultRepository: repository,
      biometricsPreferenceRepository: biometricsPreferenceRepository,
    );

    when(() => repository.markUnlocked(any())).thenReturn(null);
  });

  VaultBloc buildBloc() => VaultBloc(
        determineVaultEntryUseCase: determineVaultEntryUseCase,
        verifyPinUseCase: verifyPinUseCase,
        savePinUseCase: savePinUseCase,
        saveBiometricsPreferenceUseCase: saveBiometricsPreferenceUseCase,
        repository: repository,
      );

  group('VaultOpened -> unlockPinOnly', () {
    blocTest<VaultBloc, VaultState>(
      'no biometric preference -> PIN-entry state directly, no biometric attempted',
      setUp: () {
        when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
        when(() => repository.checkBiometricCapability())
            .thenAnswer((_) async => BiometricCapability.available);
        when(() => repository.isBiometricPreferenceEnabled())
            .thenAnswer((_) async => false);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const VaultOpened()),
      expect: () => [const VaultPinEntry()],
      verify: (_) {
        verifyNever(() => repository.attemptBiometricAuth());
      },
    );
  });

  group('VaultOpened -> pinSetupRequired', () {
    blocTest<VaultBloc, VaultState>(
      'a re-open before confirmation completes (process killed mid-setup) re-enters the create step',
      setUp: () {
        when(() => repository.hasPinConfigured()).thenAnswer((_) async => false);
      },
      build: buildBloc,
      seed: () => const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '12'),
      act: (bloc) => bloc.add(const VaultOpened()),
      expect: () => [const VaultPinSetupCreate()],
    );
  });

  group('VaultOpened -> unlockBiometricFirst', () {
    blocTest<VaultBloc, VaultState>(
      'biometric success -> unlocked, markUnlocked called',
      setUp: () {
        when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
        when(() => repository.checkBiometricCapability())
            .thenAnswer((_) async => BiometricCapability.available);
        when(() => repository.isBiometricPreferenceEnabled())
            .thenAnswer((_) async => true);
        when(() => repository.attemptBiometricAuth())
            .thenAnswer((_) async => BiometricAuthOutcome.success);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const VaultOpened()),
      expect: () => [
        const VaultBiometricPrompting(),
        const VaultUnlocked(),
      ],
      verify: (_) {
        verify(() => repository.markUnlocked(any())).called(1);
      },
    );
  });

  group('biometric failure -> PIN fallback (US2)', () {
    for (final outcome in [
      BiometricAuthOutcome.failed,
      BiometricAuthOutcome.cancelled,
      BiometricAuthOutcome.notAvailable,
    ]) {
      blocTest<VaultBloc, VaultState>(
        '$outcome -> PIN-entry state with the exact error message',
        setUp: () {
          when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
          when(() => repository.checkBiometricCapability())
              .thenAnswer((_) async => BiometricCapability.available);
          when(() => repository.isBiometricPreferenceEnabled())
              .thenAnswer((_) async => true);
          when(() => repository.attemptBiometricAuth())
              .thenAnswer((_) async => outcome);
        },
        build: buildBloc,
        act: (bloc) => bloc.add(const VaultOpened()),
        expect: () => [
          const VaultBiometricPrompting(),
          const VaultPinEntry(errorMessage: _biometricFailureMessage),
        ],
      );
    }

    blocTest<VaultBloc, VaultState>(
      'correct PIN after a biometric failure -> unlocked AND markUnlocked called',
      setUp: () {
        when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
        when(() => repository.checkBiometricCapability())
            .thenAnswer((_) async => BiometricCapability.available);
        when(() => repository.isBiometricPreferenceEnabled())
            .thenAnswer((_) async => true);
        when(() => repository.attemptBiometricAuth())
            .thenAnswer((_) async => BiometricAuthOutcome.failed);
        when(() => repository.verifyPin('1234')).thenAnswer((_) async => true);
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const VaultOpened());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final digit in '1234'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const VaultBiometricPrompting(),
        const VaultPinEntry(errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '1', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '12', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '123', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '1234', errorMessage: _biometricFailureMessage),
        const VaultUnlocked(),
      ],
      verify: (_) {
        verify(() => repository.markUnlocked(any())).called(1);
      },
    );

    blocTest<VaultBloc, VaultState>(
      'incorrect PIN -> digits cleared, error retained, a later correct attempt still succeeds',
      setUp: () {
        when(() => repository.verifyPin('0000')).thenAnswer((_) async => false);
        when(() => repository.verifyPin('1234')).thenAnswer((_) async => true);
      },
      build: buildBloc,
      seed: () => const VaultPinEntry(errorMessage: _biometricFailureMessage),
      act: (bloc) async {
        for (final digit in '0000'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        for (final digit in '1234'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const VaultPinEntry(enteredDigits: '0', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '00', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '000', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '0000', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(errorMessage: _biometricFailureMessage), // cleared
        const VaultPinEntry(enteredDigits: '1', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '12', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '123', errorMessage: _biometricFailureMessage),
        const VaultPinEntry(enteredDigits: '1234', errorMessage: _biometricFailureMessage),
        const VaultUnlocked(),
      ],
      verify: (_) {
        verify(() => repository.markUnlocked(any())).called(1);
      },
    );
  });

  group('first-time PIN setup (US3)', () {
    blocTest<VaultBloc, VaultState>(
      'matching create/confirm, biometric available -> opt-in step -> toggled -> unlocked',
      setUp: () {
        when(() => repository.hasPinConfigured()).thenAnswer((_) async => false);
        when(() => repository.savePin('1234')).thenAnswer((_) async {});
        when(() => repository.checkBiometricCapability())
            .thenAnswer((_) async => BiometricCapability.available);
        when(() => repository.setBiometricPreferenceLocally(true))
            .thenAnswer((_) async {});
        when(() => biometricsPreferenceRepository.save(true))
            .thenAnswer((_) async => const Right(null));
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const VaultOpened());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final digit in '1234'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final digit in '1234'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const BiometricOptInToggled(true));
      },
      wait: const Duration(milliseconds: 80),
      expect: () => [
        const VaultPinSetupCreate(),
        const VaultPinSetupCreate(enteredDigits: '1'),
        const VaultPinSetupCreate(enteredDigits: '12'),
        const VaultPinSetupCreate(enteredDigits: '123'),
        const VaultPinSetupConfirm(firstPin: '1234'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '1'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '12'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '123'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '1234'),
        const VaultBiometricOptIn(),
        const VaultUnlocked(),
      ],
      verify: (_) {
        verify(() => repository.savePin('1234')).called(1);
        verify(() => biometricsPreferenceRepository.save(true)).called(1);
        verify(() => repository.markUnlocked(any())).called(1);
      },
    );

    blocTest<VaultBloc, VaultState>(
      'matching create/confirm, no biometric capability -> skips opt-in -> unlocked',
      setUp: () {
        when(() => repository.hasPinConfigured()).thenAnswer((_) async => false);
        when(() => repository.savePin('1234')).thenAnswer((_) async {});
        when(() => repository.checkBiometricCapability())
            .thenAnswer((_) async => BiometricCapability.noHardware);
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const VaultOpened());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final digit in '1234'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final digit in '1234'.split('')) {
          bloc.add(PinDigitEntered(digit));
        }
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [
        const VaultPinSetupCreate(),
        const VaultPinSetupCreate(enteredDigits: '1'),
        const VaultPinSetupCreate(enteredDigits: '12'),
        const VaultPinSetupCreate(enteredDigits: '123'),
        const VaultPinSetupConfirm(firstPin: '1234'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '1'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '12'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '123'),
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '1234'),
        const VaultUnlocked(),
      ],
      verify: (_) {
        verify(() => repository.savePin('1234')).called(1);
        verify(() => repository.markUnlocked(any())).called(1);
        verifyNever(() => biometricsPreferenceRepository.save(any()));
      },
    );

    blocTest<VaultBloc, VaultState>(
      'mismatched confirm -> mismatch message, create step re-entered, savePin never called',
      build: buildBloc,
      seed: () => const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '123'),
      act: (bloc) => bloc.add(const PinDigitEntered('9')),
      expect: () => [
        const VaultPinSetupConfirm(firstPin: '1234', enteredDigits: '1239'),
        const VaultPinSetupCreate(
          mismatchMessage: 'Os PINs não coincidem. Tente novamente.',
        ),
      ],
      verify: (_) {
        verifyNever(() => repository.savePin(any()));
      },
    );
  });
}
