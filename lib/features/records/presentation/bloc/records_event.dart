import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:equatable/equatable.dart';

sealed class RecordsEvent extends Equatable {
  const RecordsEvent();

  @override
  List<Object?> get props => [];
}

/// `RecordsPage.initState` — triggers the first page fetch.
class RecordsStarted extends RecordsEvent {
  const RecordsStarted();
}

/// The list's `ScrollController` crosses a near-bottom threshold, and
/// `!hasReachedEnd && !isLoadingMore`.
class NextPageRequested extends RecordsEvent {
  const NextPageRequested();
}

/// The user taps "Tentar novamente" on a failed first load
/// (`RecordsLoadFailure`) or a failed further-page load
/// (`RecordsLoaded.pageLoadFailure`).
class PageLoadRetried extends RecordsEvent {
  const PageLoadRetried();
}

/// `RecordsPage`, once the insertion-modal `showModalBottomSheet` future
/// resolves (research.md R10) — re-merges `cachedEntries` into the currently
/// displayed list, no network call.
class RecordsLocalCacheRefreshed extends RecordsEvent {
  const RecordsLocalCacheRefreshed();
}

/// The search bar's `onChanged`, fired on every keystroke.
class SearchTextChanged extends RecordsEvent {
  const SearchTextChanged(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// Fired by the bloc's own `Timer`, 300 ms after the last [SearchTextChanged]
/// with non-empty text; never dispatched directly by any widget.
class SearchDebounceElapsed extends RecordsEvent {
  const SearchDebounceElapsed(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The filter sheet's "Aplicar" button.
class FilterSheetApplied extends RecordsEvent {
  const FilterSheetApplied({required this.dateRange, required this.entryTypes});

  final DateRangeOption dateRange;
  final Set<EntrySource> entryTypes;

  @override
  List<Object?> get props => [dateRange, entryTypes];
}

/// Tapping a single active-filter chip's remove control.
class FilterChipRemoved extends RecordsEvent {
  const FilterChipRemoved(this.chip);

  final ActiveFilterChip chip;

  @override
  List<Object?> get props => [chip];
}

/// "Limpar filtros" — clears date range, entry types, **and** the search
/// text (FR-007).
class FiltersAndSearchCleared extends RecordsEvent {
  const FiltersAndSearchCleared();
}

/// "Tentar novamente" on a failed criteria-change fetch
/// (`criteriaLoadFailure`); re-attempts the same last-applied criteria.
class CriteriaLoadRetried extends RecordsEvent {
  const CriteriaLoadRetried();
}
