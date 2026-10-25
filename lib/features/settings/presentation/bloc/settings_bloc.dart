import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/settings/domain/entities/account_profile.dart';
import 'package:cerne/features/settings/domain/repositories/account_deletion_repository.dart';
import 'package:cerne/features/settings/domain/repositories/account_profile_repository.dart';
import 'package:cerne/features/settings/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/settings/domain/usecases/save_settings_biometric_preference_usecase.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Screen-scoped (`get_it` `registerFactory`, contracts/settings-bloc.md) —
/// a fresh instance per `AppRoutes.settings` visit, never a singleton,
/// since FR-008/FR-023 require a fresh fetch on every open rather than a
/// resumed prior state. Depends on `EntriesRepository`/`ChatRepository`
/// (beyond contracts/settings-bloc.md's own listed set) because account
/// deletion's "any other locally held user data" clear (FR-019,
/// research.md R9) has no other seam to call `clearLocalData()` through;
/// and on `SecureTokenStorage` for [SettingsState.email], the same
/// no-network JWT-decode `AppDrawer` already uses (research.md R13) —
/// `SessionRepository`'s own interface exposes no cached-session accessor
/// that could serve this without a network round-trip.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required this._dashboardRepository,
    required this._accountProfileRepository,
    required this._accountDeletionRepository,
    required this._authRepository,
    required this._sessionRepository,
    required this._saveSettingsBiometricPreferenceUseCase,
    required this._vaultRepository,
    required this._entriesRepository,
    required this._chatRepository,
    required this._secureTokenStorage,
  }) : super(const SettingsState()) {
    on<SettingsOpened>(_onSettingsOpened);
    on<DashboardRetryRequested>(_onDashboardRetryRequested);
    on<NameEditStarted>(_onNameEditStarted);
    on<NameDraftChanged>(_onNameDraftChanged);
    on<NameEditCancelled>(_onNameEditCancelled);
    on<NameEditSubmitted>(_onNameEditSubmitted);
    on<BiometricToggleChanged>(_onBiometricToggleChanged);
    on<SignOutRequested>(_onSignOutRequested);
    on<DeleteAccountDialogOpened>(_onDeleteAccountDialogOpened);
    on<DeleteAccountDialogCancelled>(_onDeleteAccountDialogCancelled);
    on<DeleteAccountConfirmed>(_onDeleteAccountConfirmed);
  }

  final DashboardRepository _dashboardRepository;
  final AccountProfileRepository _accountProfileRepository;
  final AccountDeletionRepository _accountDeletionRepository;
  final AuthRepository _authRepository;
  final SessionRepository _sessionRepository;
  final SaveSettingsBiometricPreferenceUseCase _saveSettingsBiometricPreferenceUseCase;
  final VaultRepository _vaultRepository;
  final EntriesRepository _entriesRepository;
  final ChatRepository _chatRepository;
  final SecureTokenStorage _secureTokenStorage;

  final _reauthController = StreamController<void>.broadcast();

  /// A one-shot side effect, not a state (research.md R11) —
  /// `SettingsPage` listens to this to raise the "Sessão expirada" overlay.
  /// Fired only once a repository's own single silent-refresh retry has
  /// already been exhausted.
  Stream<void> get reauthRequired => _reauthController.stream;

  Future<void> _onSettingsOpened(SettingsOpened event, Emitter<SettingsState> emit) async {
    await _loadProfile(emit);
    await _loadBiometricState(emit);
    await _loadDashboard(emit);
  }

  Future<void> _onDashboardRetryRequested(
    DashboardRetryRequested event,
    Emitter<SettingsState> emit,
  ) async {
    await _loadDashboard(emit);
  }

  // --- Profile + biometric loads (SettingsOpened only) ---

  Future<void> _loadProfile(Emitter<SettingsState> emit) async {
    final email = await _secureTokenStorage.readAccountEmail() ?? '';
    // An in-progress name edit is never clobbered by a re-dispatched
    // SettingsOpened (research.md R15 — "any in-progress edit... not
    // silently lost").
    if (state.nameEditStatus != NameEditStatus.viewing) {
      emit(state.copyWith(email: email));
      return;
    }
    final cached = await _accountProfileRepository.readCachedDisplayName();
    final displayName =
        cached ?? (email.isEmpty ? '' : AccountProfile.defaultDisplayNameFromEmail(email));
    emit(state.copyWith(email: email, displayName: displayName));
  }

  Future<void> _loadBiometricState(Emitter<SettingsState> emit) async {
    final capability = await _vaultRepository.checkBiometricCapability();
    final visible = capability == BiometricCapability.available;
    final enabled = visible ? await _vaultRepository.isBiometricPreferenceEnabled() : false;
    emit(state.copyWith(biometricToggleVisible: visible, biometricEnabled: enabled));
  }

  // --- Dashboard + narrative (research.md R1) ---

  Future<void> _loadDashboard(Emitter<SettingsState> emit) async {
    emit(
      state.copyWith(
        dashboardStatus: DashboardStatus.loading,
        narrativeStatus: NarrativeStatus.notRequested,
        narrativeText: null,
        dashboardFailure: null,
      ),
    );

    final aggregateResult = await _dashboardRepository.fetchAggregate();
    await aggregateResult.match(
      (failure) async {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        emit(
          state.copyWith(
            dashboardStatus: DashboardStatus.loadFailure,
            dashboardFailure: failure,
          ),
        );
      },
      (aggregate) async {
        emit(
          state.copyWith(
            dashboardStatus: DashboardStatus.loaded,
            aggregate: aggregate,
            dashboardFailure: null,
          ),
        );
        // Only fetch the narrative once the aggregate resolves Right AND
        // its own total is >= 2 (FR-003/FR-004/FR-005/FR-006) — the bloc
        // inspects the already-resolved aggregate's own total, never a
        // second round-trip to "find out" the count.
        if (aggregate.totals.count < 2) return;
        emit(state.copyWith(narrativeStatus: NarrativeStatus.loading));
        final narrativeResult = await _dashboardRepository.fetchNarrative();
        narrativeResult.match(
          (failure) {
            if (failure is AuthExpiredFailure) _reauthController.add(null);
            emit(state.copyWith(narrativeStatus: NarrativeStatus.unavailable));
          },
          (narrative) {
            emit(
              state.copyWith(
                narrativeStatus: NarrativeStatus.loaded,
                narrativeText: narrative.text,
              ),
            );
          },
        );
      },
    );
  }

  // --- Profile name editing (FR-009/FR-010/FR-011/FR-012) ---

  void _onNameEditStarted(NameEditStarted event, Emitter<SettingsState> emit) {
    emit(
      state.copyWith(
        nameEditStatus: NameEditStatus.editing,
        nameDraft: state.displayName,
        nameEditFailureMessage: null,
      ),
    );
  }

  void _onNameDraftChanged(NameDraftChanged event, Emitter<SettingsState> emit) {
    emit(state.copyWith(nameDraft: event.value));
  }

  void _onNameEditCancelled(NameEditCancelled event, Emitter<SettingsState> emit) {
    emit(
      state.copyWith(
        nameEditStatus: NameEditStatus.viewing,
        nameDraft: '',
        nameEditFailureMessage: null,
      ),
    );
  }

  Future<void> _onNameEditSubmitted(
    NameEditSubmitted event,
    Emitter<SettingsState> emit,
  ) async {
    if (!AccountProfile.isValidDisplayName(state.nameDraft)) {
      // FR-011 — no backend call is made on an invalid draft.
      emit(
        state.copyWith(
          nameEditStatus: NameEditStatus.editing,
          nameEditFailureMessage: 'Informe um nome de até 80 caracteres.',
        ),
      );
      return;
    }

    emit(state.copyWith(nameEditStatus: NameEditStatus.saving, nameEditFailureMessage: null));
    final result = await _accountProfileRepository.updateDisplayName(state.nameDraft.trim());
    result.match(
      (failure) {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        // FR-012 — stays editing, nameDraft intact, retryable message.
        emit(
          state.copyWith(
            nameEditStatus: NameEditStatus.editing,
            nameEditFailureMessage: failure.message,
          ),
        );
      },
      (confirmedName) {
        emit(
          state.copyWith(
            displayName: confirmedName,
            nameEditStatus: NameEditStatus.viewing,
            nameDraft: '',
            nameEditFailureMessage: null,
          ),
        );
      },
    );
  }

  // --- Biometric toggle (contracts/biometric-preference-settings-extension.md) ---

  Future<void> _onBiometricToggleChanged(
    BiometricToggleChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final previousValue = state.biometricEnabled;
    // Optimistic flip (RNF01, <100ms) — reverted below on failure.
    emit(
      state.copyWith(
        biometricEnabled: event.value,
        biometricSaving: true,
        biometricFailureMessage: null,
      ),
    );
    final result = await _saveSettingsBiometricPreferenceUseCase(event.value);
    result.match(
      (failure) {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        emit(
          state.copyWith(
            biometricEnabled: previousValue,
            biometricSaving: false,
            biometricFailureMessage: failure.message,
          ),
        );
      },
      (_) {
        emit(state.copyWith(biometricSaving: false, biometricFailureMessage: null));
      },
    );
  }

  // --- Sign-out (contracts/account-session-actions.md) ---

  Future<void> _onSignOutRequested(
    SignOutRequested event,
    Emitter<SettingsState> emit,
  ) async {
    if (state.isSigningOut) return; // FR-022
    emit(state.copyWith(isSigningOut: true));

    // Awaited so the request completes before local state is wiped, but
    // never branched on — FR-016's own wording clears the local session
    // "regardless of whether that call succeeds or fails".
    await _authRepository.logout();
    await _sessionRepository.clear();
    await _accountProfileRepository.clearCachedDisplayName();

    // Always login, never vault — the vault PIN/biometric gate only
    // protects an *existing* session (VaultPage's unlock blindly goes to
    // Home); sign-out has just cleared the session, so there is nothing
    // left for the vault to gate (correction to research.md R10).
    emit(state.copyWith(isSigningOut: false, signedOut: true));
  }

  // --- Account deletion (contracts/account-deletion-repository.md) ---

  void _onDeleteAccountDialogOpened(
    DeleteAccountDialogOpened event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(deleteDialogOpen: true, deleteFailureMessage: null));
  }

  void _onDeleteAccountDialogCancelled(
    DeleteAccountDialogCancelled event,
    Emitter<SettingsState> emit,
  ) {
    // FR-021 — no backend call on cancel.
    emit(state.copyWith(deleteDialogOpen: false, deleteFailureMessage: null));
  }

  Future<void> _onDeleteAccountConfirmed(
    DeleteAccountConfirmed event,
    Emitter<SettingsState> emit,
  ) async {
    if (state.isDeletingAccount) return; // FR-022
    emit(state.copyWith(isDeletingAccount: true, deleteFailureMessage: null));

    final result = await _accountDeletionRepository.deleteAccount();
    await result.match(
      (failure) async {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        emit(state.copyWith(isDeletingAccount: false, deleteFailureMessage: failure.message));
      },
      (_) async {
        // research.md R9 — account deletion clears strictly more than
        // sign-out: session + cached profile (both actions) plus every
        // other locally held user data (deletion only).
        await _sessionRepository.clear();
        await _accountProfileRepository.clearCachedDisplayName();
        await _entriesRepository.clearLocalData();
        await _chatRepository.clearLocalData();

        // Always login, never vault — same correction as sign-out above:
        // the account no longer exists, so there is nothing left for a
        // vault unlock to gate into.
        emit(
          state.copyWith(
            isDeletingAccount: false,
            deleteDialogOpen: false,
            accountDeleted: true,
          ),
        );
      },
    );
  }

  @override
  Future<void> close() {
    unawaited(_reauthController.close());
    return super.close();
  }
}
