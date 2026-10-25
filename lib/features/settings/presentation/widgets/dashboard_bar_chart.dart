import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// A plain `Row` of 10 `Container`s (research.md R3 — no charting
/// package). Each bar's height scales relative to the tallest bar in
/// [bars]; a non-zero bar always renders a minimum visible sliver even
/// when its count is tiny relative to the tallest one. Naturally renders
/// the "single bar" look with no special-case logic whenever only one of
/// the ten indices is populated (the one-entry state, FR-004, and the
/// degenerate same-day-range case, Clarification 1).
class DashboardBarChart extends StatelessWidget {
  const DashboardBarChart({super.key, required this.bars});

  final List<int> bars;

  @override
  Widget build(BuildContext context) {
    final maxBarCount = bars.fold(0, (max, c) => c > max ? c : max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          if (i > 0) const SizedBox(width: DesignTokens.sizeChartBarGap),
          _Bar(count: bars[i], maxCount: maxBarCount),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.count, required this.maxCount});

  final int count;
  final int maxCount;

  static const _minVisibleHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    final height = (fraction * DesignTokens.sizeChartBarMaxHeight).clamp(
      count > 0 ? _minVisibleHeight : 0.0,
      DesignTokens.sizeChartBarMaxHeight,
    );
    return Container(
      width: DesignTokens.sizeChartBarWidth,
      height: height,
      decoration: BoxDecoration(
        color: DesignTokens.colorAccent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm / 2),
      ),
    );
  }
}
