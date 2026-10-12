import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/routing/app_router.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/determine_vault_entry_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_biometrics_preference_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_pin_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/verify_pin_usecase.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cerne/features/vault/presentation/pages/vault_page.dart';
import 'package:cerne/features/vault/presentation/widgets/vault_lifecycle_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

class MockBiometricsPreferenceRepository extends Mock
    implements BiometricsPreferenceRepository {}

void main() {
  late MockVaultRepository repository;

  setUp(() {
    repository = MockVaultRepository();
    when(() => repository.recordBackgrounded(any())).thenReturn(null);
    when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
    when(() => repository.checkBiometricCapability())
        .thenAnswer((_) async => BiometricCapability.noHardware);
    when(() => repository.isBiometricPreferenceEnabled())
        .thenAnswer((_) async => false);

    getIt.registerLazySingleton<VaultRepository>(() => repository);
    getIt.registerFactory<VaultBloc>(
      () => VaultBloc(
        determineVaultEntryUseCase: DetermineVaultEntryUseCase(repository),
        verifyPinUseCase: VerifyPinUseCase(repository),
        savePinUseCase: SavePinUseCase(repository),
        saveBiometricsPreferenceUseCase: SaveBiometricsPreferenceUseCase(
          vaultRepository: repository,
          biometricsPreferenceRepository: MockBiometricsPreferenceRepository(),
        ),
        repository: repository,
      ),
    );
  });

  tearDown(getIt.reset);

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const VaultLifecycleObserver(
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );

  void changeLifecycle(WidgetTester tester, AppLifecycleState state) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }

  testWidgets(
    'a relock push occurs at a >=5-minute gap with lastUnlockedAt != null',
    (tester) async {
      when(() => repository.lastUnlockedAt).thenReturn(DateTime.now());
      when(() => repository.consumeBackgroundedAt()).thenReturn(
        DateTime.now().subtract(const Duration(minutes: 6)),
      );

      await pumpApp(tester);
      changeLifecycle(tester, AppLifecycleState.paused);
      changeLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(VaultPage), findsOneWidget);
    },
  );

  testWidgets(
    'no push occurs under a 5-minute gap',
    (tester) async {
      when(() => repository.lastUnlockedAt).thenReturn(DateTime.now());
      when(() => repository.consumeBackgroundedAt()).thenReturn(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await pumpApp(tester);
      changeLifecycle(tester, AppLifecycleState.paused);
      changeLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(VaultPage), findsNothing);
    },
  );

  testWidgets(
    'no push occurs when lastUnlockedAt is null, even at a >=5-minute gap',
    (tester) async {
      when(() => repository.lastUnlockedAt).thenReturn(null);
      when(() => repository.consumeBackgroundedAt()).thenReturn(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      await pumpApp(tester);
      changeLifecycle(tester, AppLifecycleState.paused);
      changeLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(VaultPage), findsNothing);
    },
  );
}
