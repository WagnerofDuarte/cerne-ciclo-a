import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:cerne/features/settings/presentation/widgets/dashboard_bar_chart.dart';
import 'package:cerne/features/settings/presentation/widgets/narrative_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Switches between the dashboard's states (contracts/dashboard-repository.md,
/// data-model.md): `loading`, the zero-entries empty state (FR-003), the
/// one-entry state (FR-004), the multi-bar state (FR-005), and
/// `loadFailure` (FR-007). The zero/one/multi distinction reads
/// `aggregate.totals.count` directly, never bar/UI appearance, so it can't
/// be misread as applying to bucket count instead. Every state renders
/// inside the same light rounded card (prototype-extract Tela 6) — the
/// multi-bar state's card also holds `NarrativeView`, since the prototype
/// nests the narrative paragraph inside the chart's own card, directly
/// under the bars, rather than as a separate block below it.
class DashboardCard extends StatelessWidget {
  const DashboardCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        switch (state.dashboardStatus) {
          case DashboardStatus.loading:
            return const _LoadingState();
          case DashboardStatus.loadFailure:
            return _FailureState(message: state.dashboardFailure!.message);
          case DashboardStatus.loaded:
            final aggregate = state.aggregate!;
            if (aggregate.totals.count == 0) return const _EmptyState();
            if (aggregate.totals.count == 1) return const _SingleEntryState();
            return _MultiBarState(bars: aggregate.tenBars());
        }
      },
    );
  }
}

class _EvolutionCard extends StatelessWidget {
  const _EvolutionCard({required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        boxShadow: DesignTokens.elevation1,
      ),
      child: child,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return _EvolutionCard(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: const SizedBox(
        height: DesignTokens.sizeChartBarMaxHeight,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _EvolutionCard(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          TextButton(
            onPressed: () =>
                context.read<SettingsBloc>().add(const DashboardRetryRequested()),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return _EvolutionCard(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.trending_up,
            size: DesignTokens.spacingXl - DesignTokens.spacingXs,
            color: DesignTokens.colorChartPlaceholder,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            'Comece a registrar para ver sua evolução aqui',
            style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Exactly one entry: a short bar spanning the card's full width (never the
/// generic 10-slot `DashboardBarChart`, which would place it at that one
/// bucket's chronological slot — narrow and off-center — and scale its
/// height relative to itself, i.e. always to 100%).
class _SingleEntryState extends StatelessWidget {
  const _SingleEntryState();

  static const _barHeight = DesignTokens.sizeChartBarMaxHeight * 0.2;

  @override
  Widget build(BuildContext context) {
    return _EvolutionCard(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: DesignTokens.sizeChartBarMaxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    height: _barHeight,
                    decoration: const BoxDecoration(
                      color: DesignTokens.colorAccent,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(DesignTokens.radiusSm / 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            'Ainda é cedo pra ver um padrão — volte em alguns dias.',
            style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MultiBarState extends StatelessWidget {
  const _MultiBarState({required this.bars});

  final List<int> bars;

  @override
  Widget build(BuildContext context) {
    return _EvolutionCard(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardBarChart(bars: bars),
          const NarrativeView(),
        ],
      ),
    );
  }
}
