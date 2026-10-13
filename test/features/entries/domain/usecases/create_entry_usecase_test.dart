import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockEntriesRepository extends Mock implements EntriesRepository {}

Entry _buildEntry({EntrySource source = EntrySource.manual}) => Entry(
  id: 'entry-1',
  content: 'hello',
  source: source,
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
  late MockEntriesRepository repository;
  late CreateEntryUseCase useCase;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    repository = MockEntriesRepository();
    useCase = CreateEntryUseCase(repository);
  });

  test('delegates with the exact content/source given', () async {
    final entry = _buildEntry(source: EntrySource.audio);
    when(
      () => repository.create(content: 'hello', source: EntrySource.audio),
    ).thenAnswer((_) async => Right(entry));

    await useCase('hello', EntrySource.audio);

    verify(
      () => repository.create(content: 'hello', source: EntrySource.audio),
    ).called(1);
  });

  test('Right(entry) passes through unchanged', () async {
    final entry = _buildEntry();
    when(
      () => repository.create(content: any(named: 'content'), source: any(named: 'source')),
    ).thenAnswer((_) async => Right(entry));

    final result = await useCase('hello', EntrySource.manual);

    expect(result, Right<Failure, Entry>(entry));
  });

  test('Left(failure) passes through unchanged', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    when(
      () => repository.create(content: any(named: 'content'), source: any(named: 'source')),
    ).thenAnswer((_) async => const Left(failure));

    final result = await useCase('hello', EntrySource.manual);

    expect(result, const Left<Failure, Entry>(failure));
  });
}
