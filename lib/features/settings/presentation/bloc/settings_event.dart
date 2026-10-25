import 'package:equatable/equatable.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched once by the route builder (`app_router.dart`), mirroring
/// `RecordsStarted`, and again by `SettingsPage`'s own `didPopNext()`
/// (research.md R15) whenever the reauth page above it is popped.
class SettingsOpened extends SettingsEvent {
  const SettingsOpened();
}

/// FR-007's retry affordance — re-runs the aggregate (and, if it then
/// qualifies, narrative) fetch.
class DashboardRetryRequested extends SettingsEvent {
  const DashboardRetryRequested();
}

class NameEditStarted extends SettingsEvent {
  const NameEditStarted();
}

class NameDraftChanged extends SettingsEvent {
  const NameDraftChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class NameEditCancelled extends SettingsEvent {
  const NameEditCancelled();
}

class NameEditSubmitted extends SettingsEvent {
  const NameEditSubmitted();
}

class BiometricToggleChanged extends SettingsEvent {
  const BiometricToggleChanged(this.value);

  final bool value;

  @override
  List<Object?> get props => [value];
}

class SignOutRequested extends SettingsEvent {
  const SignOutRequested();
}

/// Presentation-only — toggles `deleteDialogOpen`; makes no backend call.
class DeleteAccountDialogOpened extends SettingsEvent {
  const DeleteAccountDialogOpened();
}

/// Presentation-only — toggles `deleteDialogOpen`; makes no backend call
/// (FR-021).
class DeleteAccountDialogCancelled extends SettingsEvent {
  const DeleteAccountDialogCancelled();
}

class DeleteAccountConfirmed extends SettingsEvent {
  const DeleteAccountConfirmed();
}
