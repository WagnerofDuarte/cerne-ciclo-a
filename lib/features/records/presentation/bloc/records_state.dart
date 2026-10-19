import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:equatable/equatable.dart';

sealed class RecordsState extends Equatable {
  const RecordsState();

  @override
  List<Object?> get props => [];
}

class RecordsLoading extends RecordsState {
  const RecordsLoading();
}

class RecordsLoadFailure extends RecordsState {
  const RecordsLoadFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

class RecordsLoaded extends RecordsState {
  const RecordsLoaded({
    required this.entries,
    required this.nextCursor,
    required this.isLoadingMore,
    this.pageLoadFailure,
    this.searchQuery = '',
    this.dateRange = DateRangeOption.allTime,
    this.entryTypes = const {},
    this.isApplyingCriteria = false,
    this.criteriaLoadFailure,
  });

  /// Merged + deduped, newest-to-oldest.
  final List<Entry> entries;
  final String? nextCursor;
  final bool isLoadingMore;

  /// A further-page (unbounded-mode) fetch failed; `entries` above stay
  /// intact, retryable.
  final Failure? pageLoadFailure;

  final String searchQuery;
  final DateRangeOption dateRange;
  final Set<EntrySource> entryTypes;

  /// A criteria-change fetch is in flight (RNF01's >300ms affordance).
  final bool isApplyingCriteria;

  /// A criteria-change fetch failed; `entries`/criteria fields stay
  /// unchanged, retryable.
  final Failure? criteriaLoadFailure;

  bool get hasReachedEnd => nextCursor == null;
  bool get isEmpty => entries.isEmpty;

  bool get isSearchActive => searchQuery.isNotEmpty;
  bool get hasActiveFilters => dateRange != DateRangeOption.allTime || entryTypes.isNotEmpty;
  bool get hasAnyActiveCriteria => isSearchActive || hasActiveFilters;

  List<ActiveFilterChip> get activeChips =>
      ActiveFilterChips.derive(dateRange: dateRange, entryTypes: entryTypes);

  /// FR-009 — distinct from `isEmpty` alone: only true when narrowing (not a
  /// true zero-entries account) produced the empty result.
  bool get isEmptyForCriteria => isEmpty && hasAnyActiveCriteria;

  static const _unset = Object();

  /// `pageLoadFailure`/`criteriaLoadFailure`/`nextCursor` are themselves
  /// nullable and must be explicitly clearable to `null` (e.g. a successful
  /// criteria-change fetch clears `criteriaLoadFailure`) — a sentinel
  /// default distinguishes "not passed" from "passed as null", which a
  /// plain `??` default cannot.
  RecordsLoaded copyWith({
    List<Entry>? entries,
    Object? nextCursor = _unset,
    bool? isLoadingMore,
    Object? pageLoadFailure = _unset,
    String? searchQuery,
    DateRangeOption? dateRange,
    Set<EntrySource>? entryTypes,
    bool? isApplyingCriteria,
    Object? criteriaLoadFailure = _unset,
  }) {
    return RecordsLoaded(
      entries: entries ?? this.entries,
      nextCursor: identical(nextCursor, _unset) ? this.nextCursor : nextCursor as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      pageLoadFailure: identical(pageLoadFailure, _unset)
          ? this.pageLoadFailure
          : pageLoadFailure as Failure?,
      searchQuery: searchQuery ?? this.searchQuery,
      dateRange: dateRange ?? this.dateRange,
      entryTypes: entryTypes ?? this.entryTypes,
      isApplyingCriteria: isApplyingCriteria ?? this.isApplyingCriteria,
      criteriaLoadFailure: identical(criteriaLoadFailure, _unset)
          ? this.criteriaLoadFailure
          : criteriaLoadFailure as Failure?,
    );
  }

  @override
  List<Object?> get props => [
    entries,
    nextCursor,
    isLoadingMore,
    pageLoadFailure,
    searchQuery,
    dateRange,
    entryTypes,
    isApplyingCriteria,
    criteriaLoadFailure,
  ];
}
