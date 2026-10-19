import 'package:cerne/features/entries/data/entries_local_cache.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

Entry _buildEntry({String id = 'entry-1'}) => Entry(
  id: id,
  content: 'hello',
  source: EntrySource.audio,
  chatMessageId: null,
  occurredAt: DateTime.utc(2026, 1, 1, 12),
  tags: const [EntryTag(id: 'tag-1', name: 'rotina')],
  piiStatus: PiiStatus.flagged,
  piiSpans: const [PiiSpan(start: 0, end: 3, type: 'name')],
  embeddingStatus: EmbeddingStatus.ready,
  mediaDurationSeconds: 42,
  serverRevision: 3,
  createdAt: DateTime.utc(2026, 1, 1, 12),
  updatedAt: DateTime.utc(2026, 1, 1, 12, 5),
  similarity: 0.87,
);

void main() {
  late MockFlutterSecureStorage storage;
  late EntriesLocalCache cache;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    storage = MockFlutterSecureStorage();
    cache = EntriesLocalCache(storage: storage);
  });

  test('readAll() returns an empty list when nothing has been written yet', () async {
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);

    expect(await cache.readAll(), isEmpty);
  });

  test('readAll() returns an empty list for a corrupted stored value', () async {
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => 'not json');

    expect(await cache.readAll(), isEmpty);
  });

  test('writeAll() then readAll() round-trips every Entry field, including a '
      'null similarity', () async {
    String? stored;
    when(
      () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
    ).thenAnswer((invocation) async {
      stored = invocation.namedArguments[#value] as String;
    });
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => stored);

    final withSimilarity = _buildEntry();
    final withoutSimilarity = Entry(
      id: 'entry-2',
      content: 'plain',
      source: EntrySource.manual,
      chatMessageId: 'chat-1',
      occurredAt: DateTime.utc(2026, 2, 2),
      tags: const [],
      piiStatus: PiiStatus.clean,
      piiSpans: const [],
      embeddingStatus: EmbeddingStatus.pending,
      mediaDurationSeconds: null,
      serverRevision: 1,
      createdAt: DateTime.utc(2026, 2, 2),
      updatedAt: DateTime.utc(2026, 2, 2),
    );

    await cache.writeAll([withSimilarity, withoutSimilarity]);
    final roundTripped = await cache.readAll();

    expect(roundTripped, [withSimilarity, withoutSimilarity]);
  });
}
