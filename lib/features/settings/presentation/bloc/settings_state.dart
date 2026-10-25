import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:equatable/equatable.dart';

enum DashboardStatus { loading, loaded, loadFailure }

enum NarrativeStatus { notRequested, loading, loaded, unavailable }

enum NameEditStatus { viewing, editing, saving, error }

/// One flat composite state, not a sealed per-mode hierarchy (research.md
/// R4) — Settings' concerns (dashboard, narrative, profile/name-edit,
/// biometric toggle, sign-out, account-deletion) load and update
/// independently of one another on the same screen at the same time.
class SettingsState extends Equatable {
  const SettingsState({
    this.dashboardStatus = DashboardStatus.loading,
    this.aggregate,
    this.dashboardFailure,
    this.narrativeStatus = NarrativeStatus.notRequested,
    this.narrativeText,
    this.displayName = '',
    this.email = '',
    this.nameEditStatus = NameEditStatus.viewing,
    this.nameDraft = '',
    this.nameEditFailureMessage,
    this.biometricToggleVisible = false,
    this.biometricEnabled = false,
    this.biometricSaving = false,
    this.biometricFailureMessage,
    this.isSigningOut = false,
    this.isDeletingAccount = false,
    this.deleteDialogOpen = false,
    this.deleteFailureMessage,
    this.signedOut = false,
    this.accountDeleted = false,
  });

  final DashboardStatus dashboardStatus;
  final DashboardAggregate? aggregate;
  final Failure? dashboardFailure;

  /// `notRequested` for the zero/one-entry cases (FR-003/004); never
  /// transitions once there (FR-006's distinctness).
  final NarrativeStatus narrativeStatus;
  final String? narrativeText;

  /// The name actually shown — cached/edited value or the email-derived
  /// default once email is known.
  final String displayName;

  /// From `SecureTokenStorage`'s already-authenticated session (no network
  /// call) — read-only display (FR-009).
  final String email;

  final NameEditStatus nameEditStatus;

  /// The in-progress edit field's text — preserved across a failed save
  /// (FR-012).
  final String nameDraft;

  /// Validation (FR-011) or network (FR-012) message; cleared on
  /// re-entering edit mode.
  final String? nameEditFailureMessage;

  /// `true` only when `VaultRepository.checkBiometricCapability() ==
  /// available` (FR-013's "hidden entirely" rule).
  final bool biometricToggleVisible;
  final bool biometricEnabled;
  final bool biometricSaving;

  /// Set on a reverted save (FR-014); cleared on the next toggle attempt.
  final String? biometricFailureMessage;

  /// FR-022 guard.
  final bool isSigningOut;

  /// FR-022 guard.
  final bool isDeletingAccount;

  /// Presentation-only flag the page uses to show/hide the confirmation
  /// dialog (FR-017/FR-021) — no backend call is implied by this alone.
  final bool deleteDialogOpen;

  /// FR-020; shown inside the still-open dialog.
  final String? deleteFailureMessage;

  /// A one-shot signal — `SettingsPage`'s `BlocListener` navigates to login
  /// on `true` and the bloc never emits `false` again after.
  final bool signedOut;

  /// Same shape as [signedOut], for the deletion success path.
  final bool accountDeleted;

  static const _unset = Object();

  /// Every nullable field that must be explicitly clearable to `null` uses
  /// the `RecordsLoaded`-style `_unset` sentinel default, distinguishing
  /// "not passed" from "passed as null" (research.md R4).
  SettingsState copyWith({
    DashboardStatus? dashboardStatus,
    Object? aggregate = _unset,
    Object? dashboardFailure = _unset,
    NarrativeStatus? narrativeStatus,
    Object? narrativeText = _unset,
    String? displayName,
    String? email,
    NameEditStatus? nameEditStatus,
    String? nameDraft,
    Object? nameEditFailureMessage = _unset,
    bool? biometricToggleVisible,
    bool? biometricEnabled,
    bool? biometricSaving,
    Object? biometricFailureMessage = _unset,
    bool? isSigningOut,
    bool? isDeletingAccount,
    bool? deleteDialogOpen,
    Object? deleteFailureMessage = _unset,
    bool? signedOut,
    bool? accountDeleted,
  }) {
    return SettingsState(
      dashboardStatus: dashboardStatus ?? this.dashboardStatus,
      aggregate: identical(aggregate, _unset)
          ? this.aggregate
          : aggregate as DashboardAggregate?,
      dashboardFailure: identical(dashboardFailure, _unset)
          ? this.dashboardFailure
          : dashboardFailure as Failure?,
      narrativeStatus: narrativeStatus ?? this.narrativeStatus,
      narrativeText: identical(narrativeText, _unset)
          ? this.narrativeText
          : narrativeText as String?,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      nameEditStatus: nameEditStatus ?? this.nameEditStatus,
      nameDraft: nameDraft ?? this.nameDraft,
      nameEditFailureMessage: identical(nameEditFailureMessage, _unset)
          ? this.nameEditFailureMessage
          : nameEditFailureMessage as String?,
      biometricToggleVisible: biometricToggleVisible ?? this.biometricToggleVisible,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricSaving: biometricSaving ?? this.biometricSaving,
      biometricFailureMessage: identical(biometricFailureMessage, _unset)
          ? this.biometricFailureMessage
          : biometricFailureMessage as String?,
      isSigningOut: isSigningOut ?? this.isSigningOut,
      isDeletingAccount: isDeletingAccount ?? this.isDeletingAccount,
      deleteDialogOpen: deleteDialogOpen ?? this.deleteDialogOpen,
      deleteFailureMessage: identical(deleteFailureMessage, _unset)
          ? this.deleteFailureMessage
          : deleteFailureMessage as String?,
      signedOut: signedOut ?? this.signedOut,
      accountDeleted: accountDeleted ?? this.accountDeleted,
    );
  }

  @override
  List<Object?> get props => [
    dashboardStatus,
    aggregate,
    dashboardFailure,
    narrativeStatus,
    narrativeText,
    displayName,
    email,
    nameEditStatus,
    nameDraft,
    nameEditFailureMessage,
    biometricToggleVisible,
    biometricEnabled,
    biometricSaving,
    biometricFailureMessage,
    isSigningOut,
    isDeletingAccount,
    deleteDialogOpen,
    deleteFailureMessage,
    signedOut,
    accountDeleted,
  ];
}
