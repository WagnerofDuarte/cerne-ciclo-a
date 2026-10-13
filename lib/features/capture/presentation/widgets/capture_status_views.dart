import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// The plain generic loading indicator every Save/recognition call in this
/// unit shows — no dedicated multi-state recognition screen (FR-007).
class CaptureLoadingIndicator extends StatelessWidget {
  const CaptureLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: DesignTokens.sizeLoadingIndicator,
        height: DesignTokens.sizeLoadingIndicator,
        child: CircularProgressIndicator(
          strokeWidth: DesignTokens.strokeWidthLoadingIndicator,
        ),
      ),
    );
  }
}

/// A plain message plus one generic retry action — deliberately not the
/// prototype's named "Erro" states (research.md R11, FR-009).
class CaptureFailureBand extends StatelessWidget {
  const CaptureFailureBand({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
      ],
    );
  }
}

/// Shown in place of the recording/capture controls (Edge Cases).
class CapturePermissionDeniedMessage extends StatelessWidget {
  const CapturePermissionDeniedMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorTextSecondary,
        ),
      ),
    );
  }
}
