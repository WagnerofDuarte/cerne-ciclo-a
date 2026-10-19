import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:equatable/equatable.dart';

/// One removable chip per currently-applied Filter Set criterion (Key
/// Entities: "Active Filter Chip").
sealed class ActiveFilterChip extends Equatable {
  const ActiveFilterChip();
}

class DateRangeChip extends ActiveFilterChip {
  const DateRangeChip(this.option);

  /// Never [DateRangeOption.allTime] — see [ActiveFilterChips.derive].
  final DateRangeOption option;

  @override
  List<Object?> get props => [option];
}

class EntryTypeChip extends ActiveFilterChip {
  const EntryTypeChip(this.source);

  final EntrySource source;

  @override
  List<Object?> get props => [source];
}

class ActiveFilterChips {
  const ActiveFilterChips._();

  /// Pure derivation. The active search term is deliberately NOT a chip here
  /// (FR-006 scopes chips to the Filter Set — date range + entry types — not
  /// the Search Query, a separate Key Entity); "Limpar filtros" still clears
  /// both (FR-007).
  static List<ActiveFilterChip> derive({
    required DateRangeOption dateRange,
    required Set<EntrySource> entryTypes,
  }) => [
    if (dateRange != DateRangeOption.allTime) DateRangeChip(dateRange),
    for (final source in entryTypes) EntryTypeChip(source),
  ];
}
