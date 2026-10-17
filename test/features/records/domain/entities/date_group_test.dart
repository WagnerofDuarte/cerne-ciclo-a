import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/date_group.dart';
import 'package:test/test.dart';

Entry _buildEntry({required DateTime occurredAt, String id = 'e1'}) => Entry(
  id: id,
  content: 'content',
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
);

void main() {
  final now = DateTime(2026, 10, 17, 15, 30);

  group('DateGrouper.group', () {
    test('an entry occurring today buckets under "Hoje"', () {
      final entry = _buildEntry(occurredAt: DateTime(2026, 10, 17, 9));

      final groups = DateGrouper.group([entry], now: now);

      expect(groups, hasLength(1));
      expect(groups.single.label, 'Hoje');
      expect(groups.single.entries, [entry]);
    });

    test('an entry occurring yesterday buckets under "Ontem"', () {
      final entry = _buildEntry(occurredAt: DateTime(2026, 10, 16, 9));

      final groups = DateGrouper.group([entry], now: now);

      expect(groups, hasLength(1));
      expect(groups.single.label, 'Ontem');
    });

    test('an entry occurring on an older explicit date buckets under '
        '"{day} de {monthName}"', () {
      final entry = _buildEntry(occurredAt: DateTime(2026, 10, 14, 9));

      final groups = DateGrouper.group([entry], now: now);

      expect(groups, hasLength(1));
      expect(groups.single.label, '14 de outubro');
    });

    test('groups come out in the input\'s own newest-to-oldest order, with no '
        're-sorting within or across groups', () {
      final today = _buildEntry(id: 'today', occurredAt: DateTime(2026, 10, 17, 9));
      final yesterday = _buildEntry(id: 'yesterday', occurredAt: DateTime(2026, 10, 16, 9));
      final older = _buildEntry(id: 'older', occurredAt: DateTime(2026, 10, 14, 9));

      final groups = DateGrouper.group([today, yesterday, older], now: now);

      expect(groups.map((g) => g.label).toList(), ['Hoje', 'Ontem', '14 de outubro']);
      expect(groups[0].entries, [today]);
      expect(groups[1].entries, [yesterday]);
      expect(groups[2].entries, [older]);
    });

    test('multiple entries on the same day stay within one group, in their '
        'given order', () {
      final first = _buildEntry(id: 'first', occurredAt: DateTime(2026, 10, 17, 9));
      final second = _buildEntry(id: 'second', occurredAt: DateTime(2026, 10, 17, 8));

      final groups = DateGrouper.group([first, second], now: now);

      expect(groups, hasLength(1));
      expect(groups.single.entries, [first, second]);
    });
  });
}
