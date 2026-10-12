import 'package:equatable/equatable.dart';

sealed class VaultEvent extends Equatable {
  const VaultEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched once per `VaultPage` mount (`initState`), mirroring
/// `SplashPage`'s `AppStarted` precedent.
class VaultOpened extends VaultEvent {
  const VaultOpened();
}

/// The manual "Toque para desbloquear" retry affordance.
class BiometricAuthRequested extends VaultEvent {
  const BiometricAuthRequested();
}

/// The manual "Usar PIN" link on the biometric-prompting screen — skips
/// straight to PIN entry without waiting for a biometric failure.
class UsePinRequested extends VaultEvent {
  const UsePinRequested();
}

class PinDigitEntered extends VaultEvent {
  const PinDigitEntered(this.digit);

  final String digit;

  @override
  List<Object?> get props => [digit];
}

class PinBackspacePressed extends VaultEvent {
  const PinBackspacePressed();
}

/// Self-dispatched by `VaultBloc` once the 4th digit is entered (no
/// separate "submit" button on the keypad).
class PinSubmitted extends VaultEvent {
  const PinSubmitted();
}

class BiometricOptInToggled extends VaultEvent {
  const BiometricOptInToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

/// "usar e-mail e senha" — handled by `VaultPage` navigating directly
/// (contracts: no bloc state change beyond the navigation side effect).
class UseEmailPasswordRequested extends VaultEvent {
  const UseEmailPasswordRequested();
}
