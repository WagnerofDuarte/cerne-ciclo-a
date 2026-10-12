import 'dart:async';

import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/determine_vault_entry_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_biometrics_preference_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_pin_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/verify_pin_usecase.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cerne/features/vault/presentation/pages/vault_page.dart';
import 'package:cerne/features/vault/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

class MockBiometricsPreferenceRepository extends Mock
    implements BiometricsPreferenceRepository {}

void main() {
  late MockVaultRepository repository;

  setUp(() {
    repository = MockVaultRepository();
    when(() => repository.hasPinConfigured()).thenAnswer((_) async => true);
  });

  VaultBloc buildBloc() => VaultBloc(
        determineVaultEntryUseCase: DetermineVaultEntryUseCase(repository),
        verifyPinUseCase: VerifyPinUseCase(repository),
        savePinUseCase: SavePinUseCase(repository),
        saveBiometricsPreferenceUseCase: SaveBiometricsPreferenceUseCase(
          vaultRepository: repository,
          biometricsPreferenceRepository: MockBiometricsPreferenceRepository(),
        ),
        repository: repository,
      );

  Future<GoRouter> pumpVault(
    WidgetTester tester, {
    required bool biometricAvailable,
  }) async {
    when(() => repository.checkBiometricCapability()).thenAnswer(
      (_) async => biometricAvailable
          ? BiometricCapability.available
          : BiometricCapability.noHardware,
    );
    when(() => repository.isBiometricPreferenceEnabled())
        .thenAnswer((_) async => biometricAvailable);
    // Never resolves — keeps the biometric-prompting state on screen long
    // enough for this test to inspect it, rather than racing the fallback.
    when(() => repository.attemptBiometricAuth())
        .thenAnswer((_) => Completer<BiometricAuthOutcome>().future);

    final router = GoRouter(
      initialLocation: AppRoutes.vault,
      routes: [
        GoRoute(
          path: AppRoutes.vault,
          builder: (context, state) => BlocProvider<VaultBloc>(
            create: (_) => buildBloc(),
            child: const VaultPage(mode: VaultMode.gatekeeper),
          ),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Scaffold(body: Text('Login screen')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets(
    'the "usar e-mail e senha" link is present and pushes AppRoutes.login from the PIN-entry state',
    (tester) async {
      await pumpVault(tester, biometricAvailable: false);

      expect(find.text('usar e-mail e senha'), findsOneWidget);

      await tester.ensureVisible(find.text('usar e-mail e senha'));
      await tester.tap(find.text('usar e-mail e senha'));
      await tester.pumpAndSettle();

      expect(find.text('Login screen'), findsOneWidget);
    },
  );

  testWidgets(
    'the "usar e-mail e senha" link is present and pushes AppRoutes.login from the biometric-prompting state',
    (tester) async {
      await pumpVault(tester, biometricAvailable: true);

      expect(find.text('usar e-mail e senha'), findsOneWidget);

      await tester.ensureVisible(find.text('usar e-mail e senha'));
      await tester.tap(find.text('usar e-mail e senha'));
      await tester.pumpAndSettle();

      expect(find.text('Login screen'), findsOneWidget);
    },
  );

  testWidgets(
    'the biometric-prompting state matches "Tela 0.1": subtitle, '
    '"Usar PIN" link, and switching to PIN entry on tap',
    (tester) async {
      await pumpVault(tester, biometricAvailable: true);

      expect(find.text('Toque para desbloquear'), findsOneWidget);
      expect(
        find.text('Use Face ID ou Touch ID para continuar'),
        findsOneWidget,
      );
      expect(find.text('Usar PIN'), findsOneWidget);

      await tester.tap(find.text('Usar PIN'));
      await tester.pumpAndSettle();

      expect(find.byType(PinKeypad), findsOneWidget);
      expect(find.text('Digite seu PIN'), findsOneWidget);
    },
  );
}
