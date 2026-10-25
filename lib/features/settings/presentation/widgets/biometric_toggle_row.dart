import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Renders nothing when `biometricToggleVisible == false` (FR-013's
/// "hidden entirely" rule — not a disabled row); a `Switch` bound to
/// `biometricEnabled` dispatching `BiometricToggleChanged` on change,
/// showing `biometricFailureMessage` inline when set.
class BiometricToggleRow extends StatelessWidget {
  const BiometricToggleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        if (!state.biometricToggleVisible) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Face ID / Touch ID', style: DesignTokens.textBodyLg),
                  ),
                  Switch(
                    value: state.biometricEnabled,
                    onChanged: (value) =>
                        context.read<SettingsBloc>().add(BiometricToggleChanged(value)),
                  ),
                ],
              ),
              if (state.biometricFailureMessage != null)
                Text(
                  state.biometricFailureMessage!,
                  style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
                ),
            ],
          ),
        );
      },
    );
  }
}
