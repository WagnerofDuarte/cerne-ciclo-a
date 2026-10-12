import 'package:equatable/equatable.dart';

/// Sub-states covering every branch `VaultPage`'s single screen must
/// represent (data-model.md State transitions) — the "32 states collapse
/// into fewer real screens with internal state" shape research.md R4 chose.
sealed class VaultState extends Equatable {
  const VaultState();

  @override
  List<Object?> get props => [];
}

/// Shown briefly while `VaultOpened` resolves `DetermineVaultEntryUseCase`.
class VaultInitial extends VaultState {
  const VaultInitial();
}

/// First-time PIN setup, create step (Story 3). The entered digits are kept
/// here only in memory — nothing is written to storage until the
/// confirmation step matches (FR-012).
class VaultPinSetupCreate extends VaultState {
  const VaultPinSetupCreate({this.enteredDigits = '', this.mismatchMessage});

  final String enteredDigits;

  /// Set only right after a failed confirmation attempt (FR-012: the
  /// mismatched PIN is never saved, and entry restarts here).
  final String? mismatchMessage;

  @override
  List<Object?> get props => [enteredDigits, mismatchMessage];
}

/// First-time PIN setup, confirm step. [firstPin] is the value entered in
/// the create step, held only in memory until this step's digits match it
/// (FR-012). A mismatch re-enters [VaultPinSetupCreate] with its
/// `mismatchMessage` set, rather than carrying the message here.
class VaultPinSetupConfirm extends VaultState {
  const VaultPinSetupConfirm({required this.firstPin, this.enteredDigits = ''});

  final String firstPin;
  final String enteredDigits;

  @override
  List<Object?> get props => [firstPin, enteredDigits];
}

/// Offered once, right after a matching PIN is saved, only when biometric
/// capability is available (FR-013).
class VaultBiometricOptIn extends VaultState {
  const VaultBiometricOptIn();
}

/// The auto-triggered Face ID/Touch ID prompt (Story 1).
class VaultBiometricPrompting extends VaultState {
  const VaultBiometricPrompting();
}

/// PIN entry for an existing PIN — reached directly (`unlockPinOnly`) or
/// after a biometric failure/cancellation/unavailability (Story 2), in
/// which case [errorMessage] carries FR-004's exact fallback text.
class VaultPinEntry extends VaultState {
  const VaultPinEntry({this.enteredDigits = '', this.errorMessage});

  final String enteredDigits;
  final String? errorMessage;

  @override
  List<Object?> get props => [enteredDigits, errorMessage];
}

/// The vault has been passed — `VaultPage` reacts to this by navigating per
/// its `VaultMode` (data-model.md State transitions).
class VaultUnlocked extends VaultState {
  const VaultUnlocked();
}
