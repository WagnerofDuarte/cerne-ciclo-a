import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// The prototype's "Tela 1 — Insight" card (research.md R12) — full-width
/// (no 82%-max-width bound, unlike a message bubble), a 3 dp ochre spine on
/// the left edge, an "INSIGHT" label + dismiss glyph row, then the generated
/// text.
class InsightCard extends StatelessWidget {
  const InsightCard({required this.content, required this.onDismiss, super.key});

  final String content;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingXs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          boxShadow: DesignTokens.elevation1,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          child: Stack(
            children: [
              Container(
                color: DesignTokens.colorSurfaceElevated,
                padding: const EdgeInsets.only(
                  left: DesignTokens.spacingInsightPaddingLeft,
                  right: DesignTokens.spacingMd,
                  top: DesignTokens.spacingInsightPaddingVertical,
                  bottom: DesignTokens.spacingInsightPaddingVertical,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'INSIGHT',
                            style: DesignTokens.textMonoCaption.copyWith(
                              color: DesignTokens.colorAccent,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onDismiss,
                          child: const Icon(
                            Icons.close,
                            size: DesignTokens.sizeInsightDismissIcon,
                            color: DesignTokens.colorTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacingInsightHeaderGap),
                    Text(content, style: DesignTokens.textBodyMd),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: DesignTokens.widthInsightSpine,
                  color: DesignTokens.colorAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
