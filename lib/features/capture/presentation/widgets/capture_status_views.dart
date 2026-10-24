import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// The plain generic loading indicator every Save/recognition call in this
/// unit shows — no dedicated multi-state recognition screen (FR-007).
///
/// A fixed-length arc that only rotates (prototype-extract.md's "Continuous
/// spinner (`spin`, 1 s linear infinite) in every loading state") rather
/// than Material's default indeterminate `CircularProgressIndicator`, whose
/// arc length itself pulses between near-zero and near-full — at the
/// near-zero point it reads as a short dash instead of a ring.
class CaptureLoadingIndicator extends StatefulWidget {
  const CaptureLoadingIndicator({
    super.key,
    this.size = DesignTokens.sizeLoadingIndicator,
  });

  final double size;

  @override
  State<CaptureLoadingIndicator> createState() =>
      _CaptureLoadingIndicatorState();
}

class _CaptureLoadingIndicatorState extends State<CaptureLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: RotationTransition(
          turns: _controller,
          child: const CircularProgressIndicator(
            strokeWidth: DesignTokens.strokeWidthLoadingIndicator,
            value: DesignTokens.valueLoadingIndicatorArc,
          ),
        ),
      ),
    );
  }
}

/// The prototype's actual "Erro" shape (prototype-extract.md §2.3,
/// research.md R4): a warning icon, the exact failure copy, an outline
/// "Tentar novamente" button, and — for Foto's "Salvar só a foto" only — an
/// optional secondary text action. Renders both Áudio's and Foto's "Erro"
/// states.
class RecognitionErrorView extends StatelessWidget {
  const RecognitionErrorView({
    required this.message,
    required this.onRetry,
    this.secondaryAction,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  /// A `(label, onTap)` pair — used only by Foto's "Salvar só a foto"
  /// (US4); left `null` for Áudio.
  final (String, VoidCallback)? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final secondary = secondaryAction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline,
          size: DesignTokens.sizeStatusIcon,
          color: DesignTokens.colorError,
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
              vertical: DesignTokens.spacingSm,
            ),
          ),
          child: const Text('Tentar novamente'),
        ),
        if (secondary != null) ...[
          const SizedBox(height: DesignTokens.spacingSm),
          TextButton(onPressed: secondary.$2, child: Text(secondary.$1)),
        ],
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
