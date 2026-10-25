import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A centered destructive confirmation dialog (FR-017/FR-020) — the same
/// "confirmation dialog" component shape the session-expired overlay
/// already uses, reusing its own tokens.
class DeleteAccountDialog extends StatelessWidget {
  const DeleteAccountDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return AlertDialog(
          backgroundColor: DesignTokens.colorSurfaceElevated,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: DesignTokens.spacingXl,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          title: Text(
            'Apagar sua conta?',
            style: DesignTokens.textTitleLg.copyWith(color: DesignTokens.colorError),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Isso apaga permanentemente todos os seus registros, transcrições '
                'e insights. A ação é irreversível e atende ao seu direito de '
                'eliminação previsto na LGPD.',
                style: DesignTokens.textBodyMd,
              ),
              if (state.deleteFailureMessage != null) ...[
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  state.deleteFailureMessage!,
                  style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
                ),
              ],
            ],
          ),
          actionsOverflowButtonSpacing: DesignTokens.spacingSm,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: DesignTokens.colorError),
                onPressed: state.isDeletingAccount
                    ? null
                    : () =>
                        context.read<SettingsBloc>().add(const DeleteAccountConfirmed()),
                child: state.isDeletingAccount
                    ? const SizedBox(
                        width: DesignTokens.sizeLoadingIndicator,
                        height: DesignTokens.sizeLoadingIndicator,
                        child: CircularProgressIndicator(
                          strokeWidth: DesignTokens.strokeWidthLoadingIndicator,
                          color: DesignTokens.colorOnPrimary,
                        ),
                      )
                    : const Text('Apagar tudo'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: state.isDeletingAccount
                    ? null
                    : () => context
                        .read<SettingsBloc>()
                        .add(const DeleteAccountDialogCancelled()),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        );
      },
    );
  }
}
