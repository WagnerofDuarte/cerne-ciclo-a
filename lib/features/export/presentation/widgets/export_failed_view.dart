import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// FR-007 / the resolved Clarification — the generic, job-independent
/// failure state: shown the same way regardless of the backend's specific
/// error code, no download control of any kind. Its copy is deliberately
/// distinct from `export_narrative_failed_view.dart`'s.
class ExportFailedView extends StatelessWidget {
  const ExportFailedView({super.key, required this.onClosePressed});

  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: DesignTokens.spacing2xl,
            color: DesignTokens.colorError,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text(
            'Não foi possível gerar a exportação. Nenhum dado foi produzido.',
            style: DesignTokens.textBodyLg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          TextButton(onPressed: onClosePressed, child: const Text('Fechar')),
        ],
      ),
    );
  }
}
