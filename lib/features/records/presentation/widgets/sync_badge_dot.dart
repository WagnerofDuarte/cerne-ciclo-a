import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/records/domain/entities/sync_badge_state.dart';
import 'package:flutter/material.dart';

const _labels = {
  SyncBadgeState.synchronized: 'sincronizado',
  SyncBadgeState.synchronizing: 'sincronizando',
  SyncBadgeState.error: 'erro de sync',
};

const _colors = {
  SyncBadgeState.synchronized: DesignTokens.colorSuccess,
  SyncBadgeState.synchronizing: DesignTokens.colorWarningSync,
  SyncBadgeState.error: DesignTokens.colorError,
};

/// An 8px colored dot plus a mono-caption label pair (data-model.md's
/// mapping table), reused verbatim from `DesignTokens` — zero new tokens.
class SyncBadgeDot extends StatelessWidget {
  const SyncBadgeDot({super.key, required this.state});

  final SyncBadgeState state;

  @override
  Widget build(BuildContext context) {
    final color = _colors[state]!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: DesignTokens.sizeLoadingDot,
          height: DesignTokens.sizeLoadingDot,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: DesignTokens.spacingXs),
        Text(
          _labels[state]!,
          style: DesignTokens.textMonoCaption.copyWith(color: DesignTokens.colorTextSecondary),
        ),
      ],
    );
  }
}
