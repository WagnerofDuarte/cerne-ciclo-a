import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Renders [SettingsState.narrativeText] when `loaded`; a distinct
/// "narrativa indisponível" message when `unavailable` — never conflated
/// with the zero-entries empty state (FR-006); nothing when
/// `notRequested`/`loading` (a loading affordance only).
class NarrativeView extends StatelessWidget {
  const NarrativeView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        switch (state.narrativeStatus) {
          case NarrativeStatus.notRequested:
            return const SizedBox.shrink();
          case NarrativeStatus.loading:
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
              child: Center(child: CircularProgressIndicator()),
            );
          case NarrativeStatus.loaded:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
              child: Text(state.narrativeText ?? '', style: DesignTokens.textBodyMd),
            );
          case NarrativeStatus.unavailable:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
              child: Text(
                'A narrativa está indisponível no momento.',
                style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
              ),
            );
        }
      },
    );
  }
}
