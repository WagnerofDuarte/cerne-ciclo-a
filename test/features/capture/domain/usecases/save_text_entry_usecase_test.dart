import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/usecases/save_text_entry_usecase.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockCreateEntryUseCase extends Mock implements CreateEntryUseCase {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

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
  late MockCreateEntryUseCase createEntryUseCase;
  late MockConnectivityChecker connectivityChecker;
  late SaveTextEntryUseCase useCase;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    createEntryUseCase = MockCreateEntryUseCase();
    connectivityChecker = MockConnectivityChecker();
    useCase = SaveTextEntryUseCase(
      createEntryUseCase: createEntryUseCase,
      connectivityChecker: connectivityChecker,
    );
  });

  test('offline -> Left(NetworkOfflineFailure) without calling CreateEntryUseCase', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => false);

    final result = await useCase('hello');

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<NetworkOfflineFailure>());
    verifyNever(() => createEntryUseCase(any(), any()));
  });

  test('CreateEntryUseCase failure passes through unchanged', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    when(() => createEntryUseCase('hello', EntrySource.manual))
        .thenAnswer((_) async => const Left(failure));

    final result = await useCase('hello');

    expect(result, const Left<Failure, Entry>(failure));
  });

  test('happy path -> Right(entry) with source: manual', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    final entry = _buildEntry();
    when(() => createEntryUseCase('hello', EntrySource.manual))
        .thenAnswer((_) async => Right(entry));

    final result = await useCase('hello');

    expect(result, Right<Failure, Entry>(entry));
    verify(() => createEntryUseCase('hello', EntrySource.manual)).called(1);
  });
}
