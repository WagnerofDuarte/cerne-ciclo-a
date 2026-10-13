import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:cerne/features/capture/domain/usecases/save_photo_entry_usecase.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockPhotoRecognitionRepository extends Mock
    implements PhotoRecognitionRepository {}

class MockCreateEntryUseCase extends Mock implements CreateEntryUseCase {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

Entry _buildEntry() => Entry(
  id: 'entry-1',
  content: 'recognized text',
  source: EntrySource.photo,
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
  late MockPhotoRecognitionRepository recognitionRepository;
  late MockCreateEntryUseCase createEntryUseCase;
  late MockConnectivityChecker connectivityChecker;
  late SavePhotoEntryUseCase useCase;

  const imagePath = '/tmp/photo.jpg';

  setUpAll(() {
    registerFallbackValue(EntrySource.photo);
  });

  setUp(() {
    recognitionRepository = MockPhotoRecognitionRepository();
    createEntryUseCase = MockCreateEntryUseCase();
    connectivityChecker = MockConnectivityChecker();
    useCase = SavePhotoEntryUseCase(
      recognitionRepository: recognitionRepository,
      createEntryUseCase: createEntryUseCase,
      connectivityChecker: connectivityChecker,
    );
  });

  test('offline short-circuit before recognize() is ever called', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => false);

    final result = await useCase(imagePath);

    expect(result, const Left<SavePhotoFailure, Entry>(SavePhotoOffline()));
    verifyNever(() => recognitionRepository.recognize(any()));
  });

  test('OcrNoTextFailure -> recognition', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const ocrFailure = OcrNoTextFailure(message: 'no text', requestId: 'r1');
    when(() => recognitionRepository.recognize(imagePath))
        .thenAnswer((_) async => const Left(ocrFailure));

    final result = await useCase(imagePath);

    final failure = result.getLeft().toNullable();
    expect(failure, isA<SavePhotoRecognitionFailed>());
    expect((failure! as SavePhotoRecognitionFailed).failure, ocrFailure);
    verifyNever(() => createEntryUseCase(any(), any()));
  });

  test('other recognition failure -> recognition', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const networkFailure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r2');
    when(() => recognitionRepository.recognize(imagePath))
        .thenAnswer((_) async => const Left(networkFailure));

    final result = await useCase(imagePath);

    final failure = result.getLeft().toNullable();
    expect((failure! as SavePhotoRecognitionFailed).failure, networkFailure);
  });

  test('entry-creation failure -> entryCreation(failure)', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => recognitionRepository.recognize(imagePath)).thenAnswer(
      (_) async => const Right(OcrResult(text: 'recognized text', confidence: 'high')),
    );
    const entryFailure = ValidationFailure(message: 'bad request', requestId: 'r3');
    when(() => createEntryUseCase('recognized text', EntrySource.photo))
        .thenAnswer((_) async => const Left(entryFailure));

    final result = await useCase(imagePath);

    final failure = result.getLeft().toNullable();
    expect(failure, isA<SavePhotoEntryCreationFailed>());
    expect((failure! as SavePhotoEntryCreationFailed).failure, entryFailure);
  });

  test('happy path with confidence: low still proceeds to Right(entry) with source: photo', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => recognitionRepository.recognize(imagePath)).thenAnswer(
      (_) async => const Right(OcrResult(text: 'recognized text', confidence: 'low')),
    );
    final entry = _buildEntry();
    when(() => createEntryUseCase('recognized text', EntrySource.photo))
        .thenAnswer((_) async => Right(entry));

    final result = await useCase(imagePath);

    expect(result, Right<SavePhotoFailure, Entry>(entry));
  });
}
