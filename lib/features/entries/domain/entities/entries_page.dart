import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:equatable/equatable.dart';

/// The shape of one `GET /entries` response, minus `meta.total` and the
/// `source`/`dateFrom`/`dateTo` filter parameters reserved for RF06
/// (data-model.md).
class EntriesPage extends Equatable {
  const EntriesPage({required this.entries, required this.nextCursor});

  /// The order the backend returns them (newest-occurred-first).
  final List<Entry> entries;

  /// `meta.nextCursor` verbatim; `null` means this was the last page.
  final String? nextCursor;

  @override
  List<Object?> get props => [entries, nextCursor];
}
