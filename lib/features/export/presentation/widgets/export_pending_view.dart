import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/widgets/capture_status_views.dart';
import 'package:flutter/material.dart';

/// FR-004/FR-010 — shown the instant the download icon is tapped, before
/// the `POST` even resolves.
class ExportPendingView extends StatelessWidget {
  const ExportPendingView({super.key, required this.onClosePressed});

  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CaptureLoadingIndicator(size: DesignTokens.sizeStatusIcon),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text(
            'Preparando exportação...',
            style: DesignTokens.textBodyMd,
            textAlign: TextAlign.center,
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
