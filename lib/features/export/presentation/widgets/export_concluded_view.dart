import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:flutter/material.dart';

/// FR-005/FR-008/FR-009/FR-010/FR-011.
class ExportConcludedView extends StatelessWidget {
  const ExportConcludedView({
    super.key,
    required this.isDownloadingPdf,
    required this.isDownloadingRaw,
    required this.pdfDownloadFailure,
    required this.rawDownloadFailure,
    required this.onPdfDownloadPressed,
    required this.onRawDataDownloadPressed,
    required this.onClosePressed,
  });

  final bool isDownloadingPdf;
  final bool isDownloadingRaw;
  final Failure? pdfDownloadFailure;
  final Failure? rawDownloadFailure;
  final VoidCallback onPdfDownloadPressed;
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
            Icons.check_circle_outline,
            size: DesignTokens.sizeStatusIcon,
            color: DesignTokens.colorSuccess,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text('Resumo pronto', style: DesignTokens.textBodyMd),
          const SizedBox(height: DesignTokens.spacingLg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: isDownloadingPdf ? null : onPdfDownloadPressed,
                      child: const Text('Baixar PDF'),
                    ),
                    if (pdfDownloadFailure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
                        child: ExportDownloadRetryBanner(
                          message: pdfDownloadFailure!.message,
                          onRetry: onPdfDownloadPressed,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: isDownloadingRaw ? null : onRawDataDownloadPressed,
                      child: const Text('Baixar dados brutos'),
                    ),
                    if (rawDownloadFailure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
                        child: ExportDownloadRetryBanner(
                          message: rawDownloadFailure!.message,
                          onRetry: onRawDataDownloadPressed,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
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

/// The shared inline retry affordance both `ExportConcludedView` and
/// `export_narrative_failed_view.dart` show below a failed download button
/// — same shape `records_page.dart`'s own private `_RetryBanner` already
/// established, defined here (rather than importing that file's private
/// class) so both export views can reuse one definition.
class ExportDownloadRetryBanner extends StatelessWidget {
  const ExportDownloadRetryBanner({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(message, style: DesignTokens.textBodyMd, textAlign: TextAlign.center),
        ),
        const SizedBox(width: DesignTokens.spacingSm),
        TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
      ],
    );
  }
}
