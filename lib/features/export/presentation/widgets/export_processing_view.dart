import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// FR-004/FR-010 — an indeterminate bar, since the backend never reports a
/// percentage (research.md R3).
class ExportProcessingView extends StatelessWidget {
  const ExportProcessingView({super.key, required this.onClosePressed});

  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Gerando resumo com IA...',
            style: DesignTokens.textBodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          const LinearProgressIndicator(color: DesignTokens.colorAccent),
          const SizedBox(height: DesignTokens.spacingMd),
          TextButton(
            onPressed: onClosePressed,
            child: Text(
              'Fechar',
              style: DesignTokens.textMonoCaption.copyWith(
                fontSize: 11,
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
