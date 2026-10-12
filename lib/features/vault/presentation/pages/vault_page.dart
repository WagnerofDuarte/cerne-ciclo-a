import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_event.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_state.dart';
import 'package:cerne/features/vault/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Which entry point opened `VaultPage` — decides the eventual unlocked
/// transition: `go(home)` for [gatekeeper], `pop()` for [relock]
/// (data-model.md State transitions).
enum VaultMode { gatekeeper, relock }

/// The single vault screen (research.md R4) — internally covers first-time
/// PIN setup, the biometric prompt, PIN-entry unlock/fallback, and the
/// biometrics opt-in as `VaultBloc` sub-states.
class VaultPage extends StatefulWidget {
  const VaultPage({required this.mode, super.key});

  final VaultMode mode;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  @override
  void initState() {
    super.initState();
    context.read<VaultBloc>().add(const VaultOpened());
  }

  void _useEmailPassword() => context.push(AppRoutes.login);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: SafeArea(
        child: BlocConsumer<VaultBloc, VaultState>(
          listenWhen: (previous, current) => current is VaultUnlocked,
          listener: (context, state) {
            if (widget.mode == VaultMode.gatekeeper) {
              context.go(AppRoutes.home);
            } else {
              Navigator.of(context).pop();
            }
          },
          builder: (context, state) {
            return switch (state) {
              VaultInitial() => const _LoadingView(),
              VaultPinSetupCreate() => _PinSetupCreateView(state: state),
              VaultPinSetupConfirm() => _PinSetupConfirmView(state: state),
              VaultBiometricOptIn() => const _BiometricOptInView(),
              VaultBiometricPrompting() => _BiometricPromptingView(
                  onUseEmailPassword: _useEmailPassword,
                ),
              VaultPinEntry() => _PinEntryView(
                  state: state,
                  onUseEmailPassword: _useEmailPassword,
                ),
              VaultUnlocked() => const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _UseEmailPasswordLink extends StatelessWidget {
  const _UseEmailPasswordLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: const Text('usar e-mail e senha'),
    );
  }
}

class _BiometricPromptingView extends StatelessWidget {
  const _BiometricPromptingView({required this.onUseEmailPassword});

  final VoidCallback onUseEmailPassword;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<VaultBloc>();
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingXl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => bloc.add(const BiometricAuthRequested()),
                  child: Container(
                    width: DesignTokens.sizeBiometricIconContainer,
                    height: DesignTokens.sizeBiometricIconContainer,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DesignTokens.colorSurfaceElevated,
                      border: Border.all(
                        color: DesignTokens.colorBorder,
                        width: DesignTokens.borderWidthFocused,
                      ),
                      boxShadow: DesignTokens.elevation1,
                    ),
                    child: Icon(
                      Icons.fingerprint,
                      size: DesignTokens.sizeBiometricIcon,
                      color: DesignTokens.colorPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                Text('Toque para desbloquear', style: DesignTokens.textTitleLg),
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  'Use Face ID ou Touch ID para continuar',
                  textAlign: TextAlign.center,
                  style: DesignTokens.textBodyMd.copyWith(
                    color: DesignTokens.colorTextSecondary,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                TextButton(
                  onPressed: () => bloc.add(const UsePinRequested()),
                  child: Text(
                    'Usar PIN',
                    style: DesignTokens.textMonoCaption.copyWith(
                      color: DesignTokens.colorTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: DesignTokens.spacing2xl,
          child: Center(
            child: _UseEmailPasswordLink(onPressed: onUseEmailPassword),
          ),
        ),
      ],
    );
  }
}

class _PinEntryView extends StatelessWidget {
  const _PinEntryView({required this.state, required this.onUseEmailPassword});

  final VaultPinEntry state;
  final VoidCallback onUseEmailPassword;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<VaultBloc>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Digite seu PIN', style: DesignTokens.textTitleLg),
          if (state.errorMessage != null) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            _PinErrorBand(message: state.errorMessage!),
          ],
          const SizedBox(height: DesignTokens.spacingLg),
          PinKeypad(
            enteredDigits: state.enteredDigits,
            onDigitPressed: (digit) => bloc.add(PinDigitEntered(digit)),
            onBackspacePressed: () =>
                bloc.add(const PinBackspacePressed()),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          _UseEmailPasswordLink(onPressed: onUseEmailPassword),
        ],
      ),
    );
  }
}

class _PinErrorBand extends StatelessWidget {
  const _PinErrorBand({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.colorError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: DesignTokens.spacingMd,
            color: DesignTokens.colorError,
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Flexible(
            child: Text(
              message,
              style: DesignTokens.textLabelMd.copyWith(
                color: DesignTokens.colorError,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinSetupCreateView extends StatelessWidget {
  const _PinSetupCreateView({required this.state});

  final VaultPinSetupCreate state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<VaultBloc>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Crie seu PIN', style: DesignTokens.textTitleSm),
          if (state.mismatchMessage != null) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              state.mismatchMessage!,
              textAlign: TextAlign.center,
              style: DesignTokens.textBodyMd.copyWith(
                color: DesignTokens.colorError,
              ),
            ),
          ],
          const SizedBox(height: DesignTokens.spacingLg),
          PinKeypad(
            enteredDigits: state.enteredDigits,
            onDigitPressed: (digit) => bloc.add(PinDigitEntered(digit)),
            onBackspacePressed: () =>
                bloc.add(const PinBackspacePressed()),
          ),
        ],
      ),
    );
  }
}

class _PinSetupConfirmView extends StatelessWidget {
  const _PinSetupConfirmView({required this.state});

  final VaultPinSetupConfirm state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<VaultBloc>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Confirme seu PIN', style: DesignTokens.textTitleSm),
          const SizedBox(height: DesignTokens.spacingLg),
          PinKeypad(
            enteredDigits: state.enteredDigits,
            onDigitPressed: (digit) => bloc.add(PinDigitEntered(digit)),
            onBackspacePressed: () =>
                bloc.add(const PinBackspacePressed()),
          ),
        ],
      ),
    );
  }
}

class _BiometricOptInView extends StatelessWidget {
  const _BiometricOptInView();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<VaultBloc>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fingerprint,
            size: DesignTokens.spacing2xl * 2,
            color: DesignTokens.colorPrimary,
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          Text('Usar Face ID / Touch ID?', style: DesignTokens.textTitleSm),
          const SizedBox(height: DesignTokens.spacingLg),
          ElevatedButton(
            onPressed: () =>
                bloc.add(const BiometricOptInToggled(true)),
            child: const Text('Ativar'),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          TextButton(
            onPressed: () =>
                bloc.add(const BiometricOptInToggled(false)),
            child: const Text('Agora não'),
          ),
        ],
      ),
    );
  }
}
