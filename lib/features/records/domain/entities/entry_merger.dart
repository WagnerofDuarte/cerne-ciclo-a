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

  /// N equal-weight sources (one per selected entry type, research.md R1),
  /// deduped by id (last write wins; in practice no two sources ever share
  /// an id, since every entry has exactly one `source`), sorted either by
  /// `similarity` (an active search term) or by `occurredAt` (no search
  /// term) — FR-005's "re-sorted ... by relevance when a search term is
  /// active, otherwise reverse-chronological."
  static List<Entry> mergeMany({
    required List<List<Entry>> sources,
    required bool byRelevance,
  }) {
    final byId = <String, Entry>{};
    for (final list in sources) {
      for (final entry in list) {
        byId[entry.id] = entry;
      }
    }
    final merged = byId.values.toList();
    merged.sort(
      byRelevance
          ? (a, b) => (b.similarity ?? 0).compareTo(a.similarity ?? 0)
          : (a, b) => b.occurredAt.compareTo(a.occurredAt),
    );
    return merged;
  }
}
