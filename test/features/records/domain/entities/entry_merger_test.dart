import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/entry_merger.dart';
import 'package:test/test.dart';

Entry _buildEntry({
  required String id,
  required DateTime occurredAt,
  String content = 'content',
  double? similarity,
}) => Entry(
  id: id,
  content: content,
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: occurredAt,
  tags: const [],
  piiStatus: PiiStatus.pending,
  piiSpans: const [],
  embeddingStatus: EmbeddingStatus.pending,
  mediaDurationSeconds: null,
  serverRevision: 1,
  createdAt: occurredAt,
  updatedAt: occurredAt,
  similarity: similarity,
);

void main() {
  group('EntryMerger.merge', () {
    test('an entry present in only one of the two lists passes through unchanged', () {
      final onlyInPrimary = _buildEntry(id: 'p1', occurredAt: DateTime(2026, 10, 10));
      final onlyInSecondary = _buildEntry(id: 's1', occurredAt: DateTime(2026, 10, 9));

      final merged = EntryMerger.merge(
        primary: [onlyInPrimary],
        secondary: [onlyInSecondary],
      );

      expect(merged, containsAll([onlyInPrimary, onlyInSecondary]));
      expect(merged, hasLength(2));
    });

    test('an id present in both lists is shown exactly once, using primary\'s '
        'copy of that entry\'s fields', () {
      final staleCopy = _buildEntry(
        id: 'shared',
        occurredAt: DateTime(2026, 10, 10),
        content: 'stale',
      );
      final freshCopy = _buildEntry(
        id: 'shared',
        occurredAt: DateTime(2026, 10, 10),
        content: 'fresh',
      );

      final merged = EntryMerger.merge(primary: [freshCopy], secondary: [staleCopy]);

      expect(merged, hasLength(1));
      expect(merged.single.content, 'fresh');
    });

    test('the merged result is sorted newest-to-oldest by occurredAt even when '
        'the two inputs are supplied in a different or mixed order', () {
      final oldest = _buildEntry(id: 'a', occurredAt: DateTime(2026, 10, 1));
      final middle = _buildEntry(id: 'b', occurredAt: DateTime(2026, 10, 10));
      final newest = _buildEntry(id: 'c', occurredAt: DateTime(2026, 10, 20));

      final merged = EntryMerger.merge(
        primary: [oldest, newest],
        secondary: [middle],
      );

      expect(merged, [newest, middle, oldest]);
    });
  });

  group('EntryMerger.mergeMany', () {
    test('an id present in two of three sources lists is shown exactly once '
        '(last-write-wins)', () {
      final stale = _buildEntry(id: 'shared', occurredAt: DateTime(2026, 10, 1), content: 'stale');
      final fresh = _buildEntry(id: 'shared', occurredAt: DateTime(2026, 10, 1), content: 'fresh');
      final other = _buildEntry(id: 'other', occurredAt: DateTime(2026, 10, 2));

      final merged = EntryMerger.mergeMany(
        sources: [
          [stale],
          [fresh, other],
          [],
        ],
        byRelevance: false,
      );

      expect(merged, hasLength(2));
      expect(merged.firstWhere((e) => e.id == 'shared').content, 'fresh');
    });

    test('byRelevance: true sorts descending by similarity (null treated as 0)', () {
      final high = _buildEntry(id: 'a', occurredAt: DateTime(2026, 10, 1), similarity: 0.9);
      final low = _buildEntry(id: 'b', occurredAt: DateTime(2026, 10, 2), similarity: 0.2);
      final none = _buildEntry(id: 'c', occurredAt: DateTime(2026, 10, 3));

      final merged = EntryMerger.mergeMany(sources: [[low], [high], [none]], byRelevance: true);

      expect(merged, [high, low, none]);
    });

    test('byRelevance: false sorts descending by occurredAt', () {
      final oldest = _buildEntry(id: 'a', occurredAt: DateTime(2026, 10, 1));
      final newest = _buildEntry(id: 'b', occurredAt: DateTime(2026, 10, 20));

      final merged = EntryMerger.mergeMany(sources: [[oldest], [newest]], byRelevance: false);

      expect(merged, [newest, oldest]);
    });

    test('a single-element sources list still dedupes/sorts (the trivial path)', () {
      final a = _buildEntry(id: 'a', occurredAt: DateTime(2026, 10, 1));
      final b = _buildEntry(id: 'b', occurredAt: DateTime(2026, 10, 10));

      final merged = EntryMerger.mergeMany(sources: [[a, b]], byRelevance: false);

      expect(merged, [b, a]);
    });
  });
}
