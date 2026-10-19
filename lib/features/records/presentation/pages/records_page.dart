import 'dart:async';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/presentation/widgets/open_insertion_modal.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/date_group.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:cerne/features/records/presentation/widgets/active_filter_chips_row.dart';
import 'package:cerne/features/records/presentation/widgets/filter_sheet.dart';
import 'package:cerne/features/records/presentation/widgets/no_results_for_criteria_view.dart';
import 'package:cerne/features/records/presentation/widgets/record_card.dart';
import 'package:cerne/features/records/presentation/widgets/records_empty_state.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// "Meus Registros" (data-model.md). The `ScrollController` is created once
/// and never recreated across `BlocBuilder` rebuilds, which is what
/// preserves scroll position across state changes (FR-003/FR-007).
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  final _scrollController = ScrollController();
  late final StreamSubscription<void> _reauthSubscription;

  @override
  void initState() {
    super.initState();
    // `RecordsStarted` is dispatched once by the route builder itself
    // (`AppRoutes.records`, app_router.dart) right after `RecordsBloc` is
    // constructed — not here, to avoid double-fetching the first page.
    _scrollController.addListener(_maybeRequestNextPage);
    // The one sanctioned cross-bloc touch point (research.md R5) — lives in
    // this widget, never inside `RecordsBloc` itself.
    _reauthSubscription = context.read<RecordsBloc>().reauthRequired.listen((_) {
      if (!mounted) return;
      context.read<SessionBloc>().add(const AuthExpiredDetected());
    });
  }

  void _maybeRequestNextPage() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      context.read<RecordsBloc>().add(const NextPageRequested());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _reauthSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            _SearchBar(),
            BlocBuilder<RecordsBloc, RecordsState>(
              builder: (context, state) {
                final isOffline = state is RecordsLoaded &&
                    (state.pageLoadFailure is NetworkOfflineFailure ||
                        state.criteriaLoadFailure is NetworkOfflineFailure);
                if (!isOffline) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    0,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingSm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Busca limitada ao que está salvo no aparelho.',
                      style: DesignTokens.textBodyMd.copyWith(
                        color: DesignTokens.colorInfoOffline,
                      ),
                    ),
                  ),
                );
              },
            ),
            BlocBuilder<RecordsBloc, RecordsState>(
              builder: (context, state) {
                if (state is! RecordsLoaded || state.activeChips.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    0,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                  ),
                  child: ActiveFilterChipsRow(chips: state.activeChips),
                );
              },
            ),
            Expanded(
              child: BlocBuilder<RecordsBloc, RecordsState>(
                builder: (context, state) => switch (state) {
                  RecordsLoading() => const Center(child: CircularProgressIndicator()),
                  RecordsLoadFailure(:final failure) => _LoadFailureView(message: failure.message),
                  RecordsLoaded() => _buildLoaded(context, state),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEmptyStateCreate(BuildContext context) async {
    await openInsertionModal(context);
    if (context.mounted) {
      context.read<RecordsBloc>().add(const RecordsLocalCacheRefreshed());
    }
  }

  Widget _buildLoaded(BuildContext context, RecordsLoaded loaded) {
    if (loaded.isEmptyForCriteria) {
      return NoResultsForCriteriaView(
        onAdjustPressed: () =>
            context.read<RecordsBloc>().add(const FiltersAndSearchCleared()),
      );
    }
    if (loaded.isEmpty) {
      return RecordsEmptyState(onCreatePressed: () => _openEmptyStateCreate(context));
    }

    final groups = DateGrouper.group(loaded.entries);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (loaded.isApplyingCriteria)
          const SliverPadding(
            padding: EdgeInsets.all(DesignTokens.spacingMd),
            sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
          ),
        if (loaded.criteriaLoadFailure != null)
          SliverPadding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            sliver: SliverToBoxAdapter(
              child: _RetryBanner(
                message: loaded.criteriaLoadFailure!.message,
                onRetry: () => context.read<RecordsBloc>().add(const CriteriaLoadRetried()),
              ),
            ),
          ),
        for (final group in groups) _dateGroupSliver(group),
        if (loaded.isLoadingMore)
          const SliverPadding(
            padding: EdgeInsets.all(DesignTokens.spacingMd),
            sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
          ),
        if (loaded.pageLoadFailure != null)
          SliverPadding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            sliver: SliverToBoxAdapter(
              child: _RetryBanner(
                message: loaded.pageLoadFailure!.message,
                onRetry: () => context.read<RecordsBloc>().add(const PageLoadRetried()),
              ),
            ),
          ),
      ],
    );
  }

  // Each group's date heading pins to the top only while its own entries
  // scroll underneath it, then gives way to the next group's heading —
  // `SliverMainAxisGroup` scopes the pinned `SliverPersistentHeader` to just
  // the slivers listed here, instead of the whole scroll view.
  Widget _dateGroupSliver(DateGroup group) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _DateHeaderDelegate(label: group.label)),
        SliverList.list(children: [for (final entry in group.entries) RecordCard(entry: entry)]),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, color: DesignTokens.colorTextPrimary),
          ),
          const Expanded(
            child: Text('Meus Registros', style: DesignTokens.textHeadlineMd),
          ),
          // Inert placeholder — no export behavior in this unit (FR-008).
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined, color: DesignTokens.colorTextPrimary),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  static const _pillBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusFull)),
    borderSide: BorderSide(color: DesignTokens.colorBorder),
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RecordsBloc>().state;
    final dateRange = state is RecordsLoaded ? state.dateRange : DateRangeOption.allTime;
    final entryTypes = state is RecordsLoaded ? state.entryTypes : const <EntrySource>{};
    final hasActiveFilters = state is RecordsLoaded && state.hasActiveFilters;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        0,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              enabled: true,
              onChanged: (text) =>
                  context.read<RecordsBloc>().add(SearchTextChanged(text)),
              decoration: const InputDecoration(
                hintText: 'Buscar nos registros...',
                prefixIcon: Icon(
                  Icons.search,
                  size: DesignTokens.spacingMd,
                  color: DesignTokens.colorTextSecondary,
                ),
                border: _pillBorder,
                enabledBorder: _pillBorder,
                disabledBorder: _pillBorder,
                focusedBorder: _pillBorder,
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          IconButton(
            onPressed: () => _openFilterSheet(
              context,
              dateRange: dateRange,
              entryTypes: entryTypes,
            ),
            icon: Icon(
              Icons.filter_alt,
              color: hasActiveFilters
                  ? DesignTokens.colorOnAccent
                  : DesignTokens.colorTextPrimary,
            ),
            style: IconButton.styleFrom(
              backgroundColor: hasActiveFilters
                  ? DesignTokens.colorAccent
                  : DesignTokens.colorSurfaceElevated,
              side: const BorderSide(color: DesignTokens.colorBorder),
              shape: const CircleBorder(),
              fixedSize: const Size(40, 40),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilterSheet(
    BuildContext context, {
    required DateRangeOption dateRange,
    required Set<EntrySource> entryTypes,
  }) async {
    final bloc = context.read<RecordsBloc>();
    final result =
        await showModalBottomSheet<({DateRangeOption dateRange, Set<EntrySource> entryTypes})>(
          context: context,
          isScrollControlled: true,
          builder: (_) =>
              FilterSheet(initialDateRange: dateRange, initialEntryTypes: entryTypes),
        );
    if (result != null) {
      bloc.add(FilterSheetApplied(dateRange: result.dateRange, entryTypes: result.entryTypes));
    }
  }
}

/// A date heading (e.g. "Hoje") pinned to the top of its own group only
/// (data-model.md — pure prototype-fidelity rendering).
class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DateHeaderDelegate({required this.label});

  final String label;

  static const double _extent = 32;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: DesignTokens.colorSurfaceBg,
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        DesignTokens.spacingXs,
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: DesignTokens.textMonoCaption.copyWith(color: DesignTokens.colorTextSecondary),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DateHeaderDelegate oldDelegate) => oldDelegate.label != label;
}

class _LoadFailureView extends StatelessWidget {
  const _LoadFailureView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: DesignTokens.textBodyLg, textAlign: TextAlign.center),
            const SizedBox(height: DesignTokens.spacingMd),
            ElevatedButton(
              onPressed: () => context.read<RecordsBloc>().add(const PageLoadRetried()),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryBanner extends StatelessWidget {
  const _RetryBanner({required this.message, required this.onRetry});

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
