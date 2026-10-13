import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/data/entries_repository_impl.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockEntriesRemoteDataSource extends Mock implements EntriesRemoteDataSource {}

Entry _buildEntry() => Entry(
  id: 'entry-1',
  content: 'hello',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: DateTime(2026, 1, 1),
  tags: const [],
  piiStatus: PiiStatus.pending,
  piiSpans: const [],
  embeddingStatus: EmbeddingStatus.pending,
  mediaDurationSeconds: null,
  serverRevision: 1,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  late MockEntriesRemoteDataSource remoteDataSource;
  late EntriesRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    remoteDataSource = MockEntriesRemoteDataSource();
    repository = EntriesRepositoryImpl(remoteDataSource);
  });

  test('cachedEntries starts empty', () {
    expect(repository.cachedEntries, isEmpty);
  });

  test('a successful create() appends the entry to cachedEntries', () async {
    final entry = _buildEntry();
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => Right(entry));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, Right<Failure, Entry>(entry));
    expect(repository.cachedEntries, [entry]);
  });

  test('timeout failure passes through unchanged and nothing is cached', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => const Left(failure));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, const Left<Failure, Entry>(failure));
    expect(repository.cachedEntries, isEmpty);
  });

  test('offline failure passes through unchanged and nothing is cached', () async {
    const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => const Left(failure));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, const Left<Failure, Entry>(failure));
    expect(repository.cachedEntries, isEmpty);
  });

  test('malformed-response failure passes through unchanged and nothing is cached', () async {
    const failure = ValidationFailure(message: 'malformed', requestId: 'r3');
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => const Left(failure));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, const Left<Failure, Entry>(failure));
    expect(repository.cachedEntries, isEmpty);
  });
}
