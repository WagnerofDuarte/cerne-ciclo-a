import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/usecases/confirm_entry_save_usecase.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockCreateEntryUseCase extends Mock implements CreateEntryUseCase {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

Entry _buildEntry(EntrySource source) => Entry(
  id: 'entry-1',
  content: 'hello world',
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
  late MockCreateEntryUseCase createEntryUseCase;
  late MockConnectivityChecker connectivityChecker;
  late ConfirmEntrySaveUseCase useCase;

  setUpAll(() {
    registerFallbackValue(EntrySource.audio);
  });

  setUp(() {
    createEntryUseCase = MockCreateEntryUseCase();
    connectivityChecker = MockConnectivityChecker();
    useCase = ConfirmEntrySaveUseCase(
      createEntryUseCase: createEntryUseCase,
      connectivityChecker: connectivityChecker,
    );
  });

  test('offline short-circuit before CreateEntryUseCase is ever called', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => false);

    final result = await useCase('hello world', EntrySource.audio);

    expect(
      result,
      const Left<ConfirmEntrySaveFailure, Entry>(ConfirmEntrySaveOffline()),
    );
    verifyNever(() => createEntryUseCase(any(), any()));
  });

  test('CreateEntryUseCase Right(entry) passes through unchanged', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    final entry = _buildEntry(EntrySource.photo);
    when(() => createEntryUseCase('hello world', EntrySource.photo))
        .thenAnswer((_) async => Right(entry));

    final result = await useCase('hello world', EntrySource.photo);

    expect(result, Right<ConfirmEntrySaveFailure, Entry>(entry));
  });

  test('CreateEntryUseCase Left(failure) maps to ConfirmEntrySaveCreationFailed', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const entryFailure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    when(() => createEntryUseCase('hello world', EntrySource.audio))
        .thenAnswer((_) async => const Left(entryFailure));

    final result = await useCase('hello world', EntrySource.audio);

    final failure = result.getLeft().toNullable();
    expect(failure, isA<ConfirmEntrySaveCreationFailed>());
    expect((failure! as ConfirmEntrySaveCreationFailed).failure, entryFailure);
  });
}
