import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_transcription_repository.dart';
import 'package:cerne/features/capture/domain/usecases/save_audio_entry_usecase.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAudioTranscriptionRepository extends Mock
    implements AudioTranscriptionRepository {}

class MockCreateEntryUseCase extends Mock implements CreateEntryUseCase {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

Entry _buildEntry() => Entry(
  id: 'entry-1',
  content: 'hello world',
  source: EntrySource.audio,
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
  late MockAudioTranscriptionRepository transcriptionRepository;
  late MockCreateEntryUseCase createEntryUseCase;
  late MockConnectivityChecker connectivityChecker;
  late SaveAudioEntryUseCase useCase;

  const audioPath = '/tmp/audio.wav';

  setUpAll(() {
    registerFallbackValue(EntrySource.audio);
  });

  setUp(() {
    transcriptionRepository = MockAudioTranscriptionRepository();
    createEntryUseCase = MockCreateEntryUseCase();
    connectivityChecker = MockConnectivityChecker();
    useCase = SaveAudioEntryUseCase(
      transcriptionRepository: transcriptionRepository,
      createEntryUseCase: createEntryUseCase,
      connectivityChecker: connectivityChecker,
    );
  });

  test('offline short-circuit before transcribe() is ever called', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => false);

    final result = await useCase(audioPath);

    expect(result, const Left<SaveAudioFailure, Entry>(SaveAudioOffline()));
    verifyNever(() => transcriptionRepository.transcribe(any()));
  });

  test('transcription failure -> recognition', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => transcriptionRepository.transcribe(audioPath))
        .thenAnswer((_) async => const Left(TranscriptionError()));

    final result = await useCase(audioPath);

    expect(result.isLeft(), isTrue);
    final failure = result.getLeft().toNullable();
    expect(failure, isA<SaveAudioRecognitionFailed>());
    expect(
      (failure! as SaveAudioRecognitionFailed).recognitionFailure,
      isA<TranscriptionError>(),
    );
    verifyNever(() => createEntryUseCase(any(), any()));
  });

  test('empty-result transcription -> recognition', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => transcriptionRepository.transcribe(audioPath))
        .thenAnswer((_) async => const Left(EmptyRecognitionResult()));

    final result = await useCase(audioPath);

    final failure = result.getLeft().toNullable();
    expect(
      (failure! as SaveAudioRecognitionFailed).recognitionFailure,
      isA<EmptyRecognitionResult>(),
    );
    verifyNever(() => createEntryUseCase(any(), any()));
  });

  test('entry-creation failure -> entryCreation(failure)', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => transcriptionRepository.transcribe(audioPath))
        .thenAnswer((_) async => const Right('hello world'));
    const entryFailure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    when(() => createEntryUseCase('hello world', EntrySource.audio))
        .thenAnswer((_) async => const Left(entryFailure));

    final result = await useCase(audioPath);

    final failure = result.getLeft().toNullable();
    expect(failure, isA<SaveAudioEntryCreationFailed>());
    expect((failure! as SaveAudioEntryCreationFailed).failure, entryFailure);
  });

  test('happy path -> Right(entry) with source: audio', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => transcriptionRepository.transcribe(audioPath))
        .thenAnswer((_) async => const Right('hello world'));
    final entry = _buildEntry();
    when(() => createEntryUseCase('hello world', EntrySource.audio))
        .thenAnswer((_) async => Right(entry));

    final result = await useCase(audioPath);

    expect(result, Right<SaveAudioFailure, Entry>(entry));
  });
}
