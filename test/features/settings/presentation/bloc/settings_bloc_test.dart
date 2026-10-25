import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_narrative.dart';
import 'package:cerne/features/settings/domain/repositories/account_deletion_repository.dart';
import 'package:cerne/features/settings/domain/repositories/account_profile_repository.dart';
import 'package:cerne/features/settings/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/settings/domain/usecases/save_settings_biometric_preference_usecase.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockAccountProfileRepository extends Mock implements AccountProfileRepository {}

class MockAccountDeletionRepository extends Mock implements AccountDeletionRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockSaveSettingsBiometricPreferenceUseCase extends Mock
    implements SaveSettingsBiometricPreferenceUseCase {}

class MockVaultRepository extends Mock implements VaultRepository {}

class MockEntriesRepository extends Mock implements EntriesRepository {}

class MockChatRepository extends Mock implements ChatRepository {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

const _zeroSources = DashboardSourceCounts(manual: 0, audio: 0, photo: 0, chat: 0);

DashboardAggregate _aggregateWithCount(int count) => DashboardAggregate(
  buckets: count == 0
      ? const []
      : [AggregateBucket(date: DateTime(2026, 1, 1), count: count, sources: _zeroSources)],
  totals: DashboardTotals(count: count, sources: _zeroSources),
);

void main() {
  late MockDashboardRepository dashboardRepository;
  late MockAccountProfileRepository accountProfileRepository;
  late MockAccountDeletionRepository accountDeletionRepository;
  late MockAuthRepository authRepository;
  late MockSessionRepository sessionRepository;
  late MockSaveSettingsBiometricPreferenceUseCase saveSettingsBiometricPreferenceUseCase;
  late MockVaultRepository vaultRepository;
  late MockEntriesRepository entriesRepository;
  late MockChatRepository chatRepository;
  late MockSecureTokenStorage secureTokenStorage;

  setUp(() {
    dashboardRepository = MockDashboardRepository();
    accountProfileRepository = MockAccountProfileRepository();
    accountDeletionRepository = MockAccountDeletionRepository();
    authRepository = MockAuthRepository();
    sessionRepository = MockSessionRepository();
    saveSettingsBiometricPreferenceUseCase = MockSaveSettingsBiometricPreferenceUseCase();
    vaultRepository = MockVaultRepository();
    entriesRepository = MockEntriesRepository();
    chatRepository = MockChatRepository();
    secureTokenStorage = MockSecureTokenStorage();

    when(() => secureTokenStorage.readAccountEmail())
        .thenAnswer((_) async => 'test@example.com');
    when(() => accountProfileRepository.readCachedDisplayName()).thenAnswer((_) async => null);
    when(() => accountProfileRepository.clearCachedDisplayName()).thenAnswer((_) async {});
    when(() => vaultRepository.checkBiometricCapability())
        .thenAnswer((_) async => BiometricCapability.noHardware);
    when(() => vaultRepository.isBiometricPreferenceEnabled()).thenAnswer((_) async => false);
    when(() => vaultRepository.hasPinConfigured()).thenAnswer((_) async => true);
    when(() => sessionRepository.clear()).thenAnswer((_) async {});
    when(() => authRepository.logout()).thenAnswer((_) async => const Right(unit));
    when(() => entriesRepository.clearLocalData()).thenAnswer((_) async {});
    when(() => chatRepository.clearLocalData()).thenAnswer((_) async {});
    when(() => dashboardRepository.fetchAggregate())
        .thenAnswer((_) async => Right(_aggregateWithCount(0)));
    when(() => dashboardRepository.fetchNarrative()).thenAnswer(
      (_) async => Right(DashboardNarrative(text: 'ok', generatedAt: DateTime(2026, 1, 1))),
    );
  });

  SettingsBloc buildBloc() => SettingsBloc(
    dashboardRepository: dashboardRepository,
    accountProfileRepository: accountProfileRepository,
    accountDeletionRepository: accountDeletionRepository,
    authRepository: authRepository,
    sessionRepository: sessionRepository,
    saveSettingsBiometricPreferenceUseCase: saveSettingsBiometricPreferenceUseCase,
    vaultRepository: vaultRepository,
    entriesRepository: entriesRepository,
    chatRepository: chatRepository,
    secureTokenStorage: secureTokenStorage,
  );

  // Final-state (`verify:`) checks rather than exact `expect:` sequences —
  // `Bloc.emit()` silently drops a state that is value-equal (Equatable) to
  // the one before it (e.g. the biometric-state load is a no-op whenever
  // capability/enabled already match their defaults), which makes the exact
  // emission count brittle to assert on; the terminal state and call counts
  // are what each scenario actually needs to prove.
  group('SettingsOpened/DashboardRetryRequested — dashboard (contracts/dashboard-repository.md)', () {
    blocTest<SettingsBloc, SettingsState>(
      'zero-entry aggregate -> dashboardStatus loaded, narrativeStatus stays notRequested, '
      'fetchNarrative never called (FR-003)',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate())
            .thenAnswer((_) async => Right(_aggregateWithCount(0)));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SettingsOpened()),
      verify: (bloc) {
        expect(bloc.state.dashboardStatus, DashboardStatus.loaded);
        expect(bloc.state.aggregate, _aggregateWithCount(0));
        expect(bloc.state.narrativeStatus, NarrativeStatus.notRequested);
        verifyNever(() => dashboardRepository.fetchNarrative());
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'one-entry aggregate -> narrativeStatus stays notRequested (FR-004)',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate())
            .thenAnswer((_) async => Right(_aggregateWithCount(1)));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SettingsOpened()),
      verify: (bloc) {
        expect(bloc.state.dashboardStatus, DashboardStatus.loaded);
        expect(bloc.state.aggregate, _aggregateWithCount(1));
        expect(bloc.state.narrativeStatus, NarrativeStatus.notRequested);
        verifyNever(() => dashboardRepository.fetchNarrative());
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'two-or-more-entry aggregate -> narrativeStatus loading then loaded on Right (FR-005/006)',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate())
            .thenAnswer((_) async => Right(_aggregateWithCount(5)));
        when(() => dashboardRepository.fetchNarrative()).thenAnswer(
          (_) async => Right(DashboardNarrative(text: 'narrativa', generatedAt: DateTime(2026, 1, 1))),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SettingsOpened()),
      verify: (bloc) {
        expect(bloc.state.dashboardStatus, DashboardStatus.loaded);
        expect(bloc.state.aggregate, _aggregateWithCount(5));
        expect(bloc.state.narrativeStatus, NarrativeStatus.loaded);
        expect(bloc.state.narrativeText, 'narrativa');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'two-or-more-entry aggregate with narrative Left -> narrativeStatus unavailable (FR-006)',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate())
            .thenAnswer((_) async => Right(_aggregateWithCount(5)));
        when(() => dashboardRepository.fetchNarrative()).thenAnswer(
          (_) async =>
              const Left(AiGenerationTimeoutFailure(message: 'timed out', requestId: '')),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SettingsOpened()),
      verify: (bloc) {
        expect(bloc.state.narrativeStatus, NarrativeStatus.unavailable);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'aggregate fetch Left -> dashboardStatus loadFailure, dashboardFailure set, '
      'fetchNarrative never called (FR-007)',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate()).thenAnswer(
          (_) async => const Left(NetworkTimeoutFailure(message: 'timed out', requestId: '')),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SettingsOpened()),
      verify: (bloc) {
        expect(bloc.state.dashboardStatus, DashboardStatus.loadFailure);
        expect(
          bloc.state.dashboardFailure,
          const NetworkTimeoutFailure(message: 'timed out', requestId: ''),
        );
        verifyNever(() => dashboardRepository.fetchNarrative());
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'aggregate fetch Left(AuthExpiredFailure) after a failed silent refresh fires reauthRequired once '
      '(contracts/dashboard-repository.md #7)',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate()).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: '')),
        );
      },
      build: buildBloc,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const SettingsOpened());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      verify: (bloc) {
        expect(bloc.state.dashboardStatus, DashboardStatus.loadFailure);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'DashboardRetryRequested re-runs the aggregate-then-conditional-narrative sequence from a '
      'prior loadFailure state',
      setUp: () {
        when(() => dashboardRepository.fetchAggregate())
            .thenAnswer((_) async => Right(_aggregateWithCount(0)));
      },
      build: buildBloc,
      seed: () => const SettingsState(
        dashboardStatus: DashboardStatus.loadFailure,
        dashboardFailure: NetworkTimeoutFailure(message: 'timed out', requestId: ''),
      ),
      act: (bloc) => bloc.add(const DashboardRetryRequested()),
      verify: (bloc) {
        expect(bloc.state.dashboardStatus, DashboardStatus.loaded);
        expect(bloc.state.aggregate, _aggregateWithCount(0));
        expect(bloc.state.dashboardFailure, isNull);
      },
    );
  });

  group('DeleteAccountConfirmed (contracts/account-deletion-repository.md)', () {
    blocTest<SettingsBloc, SettingsState>(
      'Right result clears session/profile/entries/chat and always resolves accountDeleted '
      '(never the vault, which would unlock into an account that no longer exists)',
      setUp: () {
        when(() => accountDeletionRepository.deleteAccount())
            .thenAnswer((_) async => const Right(unit));
      },
      build: buildBloc,
      seed: () => const SettingsState(deleteDialogOpen: true),
      act: (bloc) => bloc.add(const DeleteAccountConfirmed()),
      verify: (bloc) {
        verify(() => sessionRepository.clear()).called(1);
        verify(() => accountProfileRepository.clearCachedDisplayName()).called(1);
        verify(() => entriesRepository.clearLocalData()).called(1);
        verify(() => chatRepository.clearLocalData()).called(1);
        verifyNever(() => vaultRepository.hasPinConfigured());
        expect(bloc.state.accountDeleted, isTrue);
        expect(bloc.state.deleteDialogOpen, isFalse);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'Left result sets deleteFailureMessage, clears no local state, dialog stays open',
      setUp: () {
        when(() => accountDeletionRepository.deleteAccount()).thenAnswer(
          (_) async => const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
        );
      },
      build: buildBloc,
      seed: () => const SettingsState(deleteDialogOpen: true),
      act: (bloc) => bloc.add(const DeleteAccountConfirmed()),
      verify: (bloc) {
        expect(bloc.state.deleteFailureMessage, 'offline');
        expect(bloc.state.deleteDialogOpen, isTrue);
        verifyNever(() => sessionRepository.clear());
        verifyNever(() => entriesRepository.clearLocalData());
        verifyNever(() => chatRepository.clearLocalData());
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'a second DeleteAccountConfirmed while isDeletingAccount is true triggers no second call '
      '(FR-022, research.md R12)',
      setUp: () {
        when(() => accountDeletionRepository.deleteAccount()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const Right(unit);
        });
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const DeleteAccountConfirmed());
        bloc.add(const DeleteAccountConfirmed());
      },
      wait: const Duration(milliseconds: 100),
      verify: (_) {
        verify(() => accountDeletionRepository.deleteAccount()).called(1);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'Left(AuthExpiredFailure) after a failed silent refresh fires reauthRequired exactly once '
      '(contracts/account-deletion-repository.md #5)',
      setUp: () {
        when(() => accountDeletionRepository.deleteAccount()).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: '')),
        );
      },
      build: buildBloc,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const DeleteAccountConfirmed());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
    );
  });

  group('NameEdit* (FR-009/010/011/012)', () {
    blocTest<SettingsBloc, SettingsState>(
      'empty nameDraft submit -> nameEditFailureMessage set, stays editing, no repository call',
      build: buildBloc,
      seed: () => const SettingsState(
        nameEditStatus: NameEditStatus.editing,
        nameDraft: '',
      ),
      act: (bloc) => bloc.add(const NameEditSubmitted()),
      verify: (bloc) {
        expect(bloc.state.nameEditStatus, NameEditStatus.editing);
        expect(bloc.state.nameEditFailureMessage, isNotNull);
        verifyNever(() => accountProfileRepository.updateDisplayName(any()));
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      '81-char nameDraft submit -> nameEditFailureMessage set, stays editing, no repository call',
      build: buildBloc,
      seed: () => SettingsState(
        nameEditStatus: NameEditStatus.editing,
        nameDraft: 'a' * 81,
      ),
      act: (bloc) => bloc.add(const NameEditSubmitted()),
      verify: (bloc) {
        expect(bloc.state.nameEditStatus, NameEditStatus.editing);
        expect(bloc.state.nameEditFailureMessage, isNotNull);
        verifyNever(() => accountProfileRepository.updateDisplayName(any()));
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'valid submit succeeding -> displayName updates, nameEditStatus -> viewing',
      setUp: () {
        when(() => accountProfileRepository.updateDisplayName('Wagner'))
            .thenAnswer((_) async => const Right('Wagner'));
      },
      build: buildBloc,
      seed: () => const SettingsState(
        nameEditStatus: NameEditStatus.editing,
        nameDraft: 'Wagner',
      ),
      act: (bloc) => bloc.add(const NameEditSubmitted()),
      verify: (bloc) {
        expect(bloc.state.displayName, 'Wagner');
        expect(bloc.state.nameEditStatus, NameEditStatus.viewing);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'valid submit failing -> stays editing with nameDraft intact, retryable message (FR-012)',
      setUp: () {
        when(() => accountProfileRepository.updateDisplayName('Wagner')).thenAnswer(
          (_) async => const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
        );
      },
      build: buildBloc,
      seed: () => const SettingsState(
        nameEditStatus: NameEditStatus.editing,
        nameDraft: 'Wagner',
      ),
      act: (bloc) => bloc.add(const NameEditSubmitted()),
      verify: (bloc) {
        expect(bloc.state.nameEditStatus, NameEditStatus.editing);
        expect(bloc.state.nameDraft, 'Wagner');
        expect(bloc.state.nameEditFailureMessage, 'offline');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'a name-save failure that is specifically Left(AuthExpiredFailure) fires reauthRequired once',
      setUp: () {
        when(() => accountProfileRepository.updateDisplayName('Wagner')).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: '')),
        );
      },
      build: buildBloc,
      seed: () => const SettingsState(
        nameEditStatus: NameEditStatus.editing,
        nameDraft: 'Wagner',
      ),
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const NameEditSubmitted());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
    );
  });

  group('BiometricToggleChanged (FR-013/014)', () {
    blocTest<SettingsBloc, SettingsState>(
      'toggle flip succeeding -> biometricEnabled reflects the new value, mirror updated',
      setUp: () {
        when(() => saveSettingsBiometricPreferenceUseCase.call(true))
            .thenAnswer((_) async => const Right(null));
      },
      build: buildBloc,
      seed: () => const SettingsState(biometricToggleVisible: true, biometricEnabled: false),
      act: (bloc) => bloc.add(const BiometricToggleChanged(true)),
      verify: (bloc) {
        expect(bloc.state.biometricEnabled, isTrue);
        expect(bloc.state.biometricFailureMessage, isNull);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'toggle flip failing -> biometricEnabled reverts to the pre-flip value, failure message set '
      '(FR-014)',
      setUp: () {
        when(() => saveSettingsBiometricPreferenceUseCase.call(true)).thenAnswer(
          (_) async => const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
        );
      },
      build: buildBloc,
      seed: () => const SettingsState(biometricToggleVisible: true, biometricEnabled: false),
      act: (bloc) => bloc.add(const BiometricToggleChanged(true)),
      verify: (bloc) {
        expect(bloc.state.biometricEnabled, isFalse);
        expect(bloc.state.biometricFailureMessage, 'offline');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'a toggle-flip failure that is specifically Left(AuthExpiredFailure) fires reauthRequired once',
      setUp: () {
        when(() => saveSettingsBiometricPreferenceUseCase.call(true)).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: '')),
        );
      },
      build: buildBloc,
      seed: () => const SettingsState(biometricToggleVisible: true, biometricEnabled: false),
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const BiometricToggleChanged(true));
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
    );
  });

  group('SignOutRequested (contracts/account-session-actions.md)', () {
    blocTest<SettingsBloc, SettingsState>(
      'logout(), SessionRepository.clear(), AccountProfileRepository.clearCachedDisplayName() are '
      'all called regardless of logout()\'s own result, then signedOut always resolves to login '
      '(never the vault, which would unlock into a now-cleared session)',
      setUp: () {
        when(() => authRepository.logout()).thenAnswer(
          (_) async => const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SignOutRequested()),
      verify: (bloc) {
        verify(() => authRepository.logout()).called(1);
        verify(() => sessionRepository.clear()).called(1);
        verify(() => accountProfileRepository.clearCachedDisplayName()).called(1);
        verifyNever(() => vaultRepository.hasPinConfigured());
        expect(bloc.state.signedOut, isTrue);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'a second SignOutRequested while isSigningOut is true triggers no second logout() call (FR-022)',
      setUp: () {
        when(() => authRepository.logout()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const Right(unit);
        });
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const SignOutRequested());
        bloc.add(const SignOutRequested());
      },
      wait: const Duration(milliseconds: 100),
      verify: (_) {
        verify(() => authRepository.logout()).called(1);
      },
    );
  });
}
