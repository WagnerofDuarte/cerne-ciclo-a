import 'package:cerne/features/entries/domain/entities/entry.dart';

/// Implements spec.md's resolved dedupe-by-ID Clarification: on a shared id,
/// `primary`'s copy wins — satisfied by always calling [merge] with the
/// fresher data as `primary` (research.md R3).
class EntryMerger {
  const EntryMerger._();

  static List<Entry> merge({
    required List<Entry> primary,
    required List<Entry> secondary,
  }) {
    final byId = <String, Entry>{};
    for (final entry in secondary) {
      byId[entry.id] = entry;
    }
    for (final entry in primary) {
      byId[entry.id] = entry;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return merged;
  }
}
