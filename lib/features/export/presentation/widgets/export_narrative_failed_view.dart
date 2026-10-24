import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/presentation/widgets/export_concluded_view.dart';
import 'package:flutter/material.dart';

/// FR-006/FR-009/FR-010 — the AI summary failed but the underlying data is
/// still available; exactly one download control, no "Baixar PDF".
class ExportNarrativeFailedView extends StatelessWidget {
  const ExportNarrativeFailedView({
    super.key,
    required this.isDownloadingRaw,
    required this.rawDownloadFailure,
    required this.onRawDataDownloadPressed,
    required this.onClosePressed,
  });

  final bool isDownloadingRaw;
  final Failure? rawDownloadFailure;
  final VoidCallback onRawDataDownloadPressed;
  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber,
            size: DesignTokens.spacing2xl,
            color: DesignTokens.colorError,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text(
            'Não foi possível gerar o resumo com IA, mas seus dados estão '
            'disponíveis para download.',
            style: DesignTokens.textBodyLg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isDownloadingRaw ? null : onRawDataDownloadPressed,
              child: const Text('Baixar dados brutos'),
            ),
          ),
          if (rawDownloadFailure != null)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
              child: ExportDownloadRetryBanner(
                message: rawDownloadFailure!.message,
                onRetry: onRawDataDownloadPressed,
              ),
            ),
          const SizedBox(height: DesignTokens.spacingMd),
          TextButton(onPressed: onClosePressed, child: const Text('Fechar')),
        ],
      ),
    );
  }
}
