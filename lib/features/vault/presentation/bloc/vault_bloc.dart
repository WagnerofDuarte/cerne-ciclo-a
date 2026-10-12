import 'package:cerne/features/vault/domain/entities/biometric_capability.dart';
import 'package:cerne/features/vault/domain/entities/vault_entry_mode.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/determine_vault_entry_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_biometrics_preference_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_pin_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/verify_pin_usecase.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_event.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _biometricFailureMessage = 'Não foi possível reconhecer — digite seu PIN';

/// Screen-scoped bloc backing the single `VaultPage` (research.md R4):
/// first-time PIN setup, biometric unlock, PIN-fallback unlock, and the
/// biometrics opt-in, all as sub-states of one bloc.
class VaultBloc extends Bloc<VaultEvent, VaultState> {
  VaultBloc({
    required this._determineVaultEntryUseCase,
    required this._verifyPinUseCase,
    required this._savePinUseCase,
    required this._saveBiometricsPreferenceUseCase,
    required this._repository,
  }) : super(const VaultInitial()) {
    on<VaultOpened>(_onVaultOpened);
    on<BiometricAuthRequested>(_onBiometricAuthRequested);
    on<UsePinRequested>(_onUsePinRequested);
    on<PinDigitEntered>(_onPinDigitEntered);
    on<PinBackspacePressed>(_onPinBackspacePressed);
    on<PinSubmitted>(_onPinSubmitted);
    on<BiometricOptInToggled>(_onBiometricOptInToggled);
  }

  final DetermineVaultEntryUseCase _determineVaultEntryUseCase;
  final VerifyPinUseCase _verifyPinUseCase;
  final SavePinUseCase _savePinUseCase;
  final SaveBiometricsPreferenceUseCase _saveBiometricsPreferenceUseCase;
  final VaultRepository _repository;

  Future<void> _onVaultOpened(
    VaultOpened event,
    Emitter<VaultState> emit,
  ) async {
    final mode = await _determineVaultEntryUseCase();
    switch (mode) {
      case VaultEntryMode.pinSetupRequired:
        emit(const VaultPinSetupCreate());
      case VaultEntryMode.unlockBiometricFirst:
        emit(const VaultBiometricPrompting());
        await _performBiometricAuth(emit);
      case VaultEntryMode.unlockPinOnly:
        emit(const VaultPinEntry());
    }
  }

  Future<void> _onBiometricAuthRequested(
    BiometricAuthRequested event,
    Emitter<VaultState> emit,
  ) async {
    emit(const VaultBiometricPrompting());
    await _performBiometricAuth(emit);
  }

  Future<void> _performBiometricAuth(Emitter<VaultState> emit) async {
    final outcome = await _repository.attemptBiometricAuth();
    if (outcome == BiometricAuthOutcome.success) {
      _repository.markUnlocked(DateTime.now());
      emit(const VaultUnlocked());
      return;
    }
    // failed / cancelled / notAvailable are all routed identically (FR-004
    // does not distinguish them) — contracts/vault-repository.md.
    emit(const VaultPinEntry(errorMessage: _biometricFailureMessage));
  }

  void _onUsePinRequested(UsePinRequested event, Emitter<VaultState> emit) {
    emit(const VaultPinEntry());
  }

  void _onPinDigitEntered(PinDigitEntered event, Emitter<VaultState> emit) {
    final current = state;
    switch (current) {
      case VaultPinSetupCreate(:final enteredDigits):
        final next = enteredDigits + event.digit;
        if (next.length < 4) {
          emit(VaultPinSetupCreate(enteredDigits: next));
        } else {
          emit(VaultPinSetupConfirm(firstPin: next));
        }
      case VaultPinSetupConfirm(:final firstPin, :final enteredDigits):
        final next = enteredDigits + event.digit;
        if (next.length < 4) {
          emit(VaultPinSetupConfirm(firstPin: firstPin, enteredDigits: next));
        } else {
          emit(VaultPinSetupConfirm(firstPin: firstPin, enteredDigits: next));
          add(const PinSubmitted());
        }
      case VaultPinEntry(:final enteredDigits, :final errorMessage):
        final next = enteredDigits + event.digit;
        if (next.length < 4) {
          emit(VaultPinEntry(enteredDigits: next, errorMessage: errorMessage));
        } else {
          emit(VaultPinEntry(enteredDigits: next, errorMessage: errorMessage));
          add(const PinSubmitted());
        }
      case VaultInitial():
      case VaultBiometricOptIn():
      case VaultBiometricPrompting():
      case VaultUnlocked():
        break;
    }
  }

  void _onPinBackspacePressed(
    PinBackspacePressed event,
    Emitter<VaultState> emit,
  ) {
    final current = state;
    switch (current) {
      case VaultPinSetupCreate(:final enteredDigits):
        if (enteredDigits.isNotEmpty) {
          emit(
            VaultPinSetupCreate(
              enteredDigits: enteredDigits.substring(
                0,
                enteredDigits.length - 1,
              ),
            ),
          );
        }
      case VaultPinSetupConfirm(:final firstPin, :final enteredDigits):
        if (enteredDigits.isNotEmpty) {
          emit(
            VaultPinSetupConfirm(
              firstPin: firstPin,
              enteredDigits: enteredDigits.substring(
                0,
                enteredDigits.length - 1,
              ),
            ),
          );
        }
      case VaultPinEntry(:final enteredDigits, :final errorMessage):
        if (enteredDigits.isNotEmpty) {
          emit(
            VaultPinEntry(
              enteredDigits: enteredDigits.substring(
                0,
                enteredDigits.length - 1,
              ),
              errorMessage: errorMessage,
            ),
          );
        }
      case VaultInitial():
      case VaultBiometricOptIn():
      case VaultBiometricPrompting():
      case VaultUnlocked():
        break;
    }
  }

  Future<void> _onPinSubmitted(
    PinSubmitted event,
    Emitter<VaultState> emit,
  ) async {
    final current = state;
    switch (current) {
      case VaultPinSetupConfirm(:final firstPin, :final enteredDigits):
        if (enteredDigits != firstPin) {
          emit(
            const VaultPinSetupCreate(
              mismatchMessage: 'Os PINs não coincidem. Tente novamente.',
            ),
          );
          return;
        }
        await _savePinUseCase(firstPin);
        final capability = await _repository.checkBiometricCapability();
        if (capability == BiometricCapability.available) {
          emit(const VaultBiometricOptIn());
        } else {
          _repository.markUnlocked(DateTime.now());
          emit(const VaultUnlocked());
        }
      case VaultPinEntry(:final enteredDigits, :final errorMessage):
        final correct = await _verifyPinUseCase(enteredDigits);
        if (correct) {
          _repository.markUnlocked(DateTime.now());
          emit(const VaultUnlocked());
        } else {
          emit(VaultPinEntry(errorMessage: errorMessage));
        }
      case VaultInitial():
      case VaultPinSetupCreate():
      case VaultBiometricOptIn():
      case VaultBiometricPrompting():
      case VaultUnlocked():
        break;
    }
  }

  Future<void> _onBiometricOptInToggled(
    BiometricOptInToggled event,
    Emitter<VaultState> emit,
  ) async {
    await _saveBiometricsPreferenceUseCase(event.enabled);
    _repository.markUnlocked(DateTime.now());
    emit(const VaultUnlocked());
  }
}
