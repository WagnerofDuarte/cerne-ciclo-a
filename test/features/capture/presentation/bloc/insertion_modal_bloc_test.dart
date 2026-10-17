import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/audio_transcription_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:cerne/features/capture/domain/usecases/confirm_entry_save_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/recognize_photo_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/save_text_entry_usecase.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockSaveTextEntryUseCase extends Mock implements SaveTextEntryUseCase {}

class MockAudioCaptureRepository extends Mock
    implements AudioCaptureRepository {}

class MockAudioTranscriptionRepository extends Mock
    implements AudioTranscriptionRepository {}

class MockConfirmEntrySaveUseCase extends Mock
    implements ConfirmEntrySaveUseCase {}

class MockPhotoCaptureRepository extends Mock
    implements PhotoCaptureRepository {}

class MockRecognizePhotoUseCase extends Mock implements RecognizePhotoUseCase {}

Entry _buildEntry(EntrySource source, {String content = 'hello'}) => Entry(
  id: 'entry-1',
  content: content,
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
  late MockSaveTextEntryUseCase saveTextEntryUseCase;
  late MockAudioCaptureRepository audioCaptureRepository;
  late MockAudioTranscriptionRepository audioTranscriptionRepository;
  late MockConfirmEntrySaveUseCase confirmEntrySaveUseCase;
  late MockPhotoCaptureRepository photoCaptureRepository;
  late MockRecognizePhotoUseCase recognizePhotoUseCase;

  const audioPath = '/tmp/audio.wav';
  const imagePath = '/tmp/photo.jpg';
  var closeSignalFired = false;

  setUpAll(() {
    registerFallbackValue(EntrySource.audio);
  });

  setUp(() {
    closeSignalFired = false;
    saveTextEntryUseCase = MockSaveTextEntryUseCase();
    audioCaptureRepository = MockAudioCaptureRepository();
    audioTranscriptionRepository = MockAudioTranscriptionRepository();
    confirmEntrySaveUseCase = MockConfirmEntrySaveUseCase();
    photoCaptureRepository = MockPhotoCaptureRepository();
    recognizePhotoUseCase = MockRecognizePhotoUseCase();

    when(() => audioCaptureRepository.discard()).thenReturn(null);
  });

  InsertionModalBloc buildBloc() => InsertionModalBloc(
    saveTextEntryUseCase: saveTextEntryUseCase,
    audioCaptureRepository: audioCaptureRepository,
    audioTranscriptionRepository: audioTranscriptionRepository,
    confirmEntrySaveUseCase: confirmEntrySaveUseCase,
    photoCaptureRepository: photoCaptureRepository,
    recognizePhotoUseCase: recognizePhotoUseCase,
  );

  test('initial state is InsertionModalTexto with an empty draft', () {
    expect(buildBloc().state, const InsertionModalTexto());
  });

  group('Texto flow', () {
    blocTest<InsertionModalBloc, InsertionModalState>(
      'TextDraftChanged round-trips the draft',
      build: buildBloc,
      act: (bloc) => bloc.add(const TextDraftChanged('hello')),
      expect: () => [const InsertionModalTexto(text: 'hello')],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'SaveTextSubmitted with empty text is a no-op',
      build: buildBloc,
      act: (bloc) => bloc.add(const SaveTextSubmitted()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verifyNever(() => saveTextEntryUseCase(any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'SaveTextSubmitted success triggers the close side-effect',
      setUp: () {
        when(() => saveTextEntryUseCase('hello'))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.manual)));
      },
      build: buildBloc,
      seed: () => const InsertionModalTexto(text: 'hello'),
      act: (bloc) {
        closeSignalFired = false;
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const SaveTextSubmitted());
      },
      expect: () => [const InsertionModalTextoSaving('hello')],
      verify: (_) {
        verify(() => saveTextEntryUseCase('hello')).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'offline blocks before any network call (SaveTextEntryUseCase itself enforces this)',
      setUp: () {
        when(() => saveTextEntryUseCase('hello')).thenAnswer(
          (_) async => const Left(
            NetworkOfflineFailure(message: 'offline', requestId: ''),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalTexto(text: 'hello'),
      act: (bloc) => bloc.add(const SaveTextSubmitted()),
      expect: () => [
        const InsertionModalTextoSaving('hello'),
        const InsertionModalTextoFailure(text: 'hello', message: 'offline'),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a second SaveTextSubmitted while already saving is ignored (no duplicate entry)',
      setUp: () {
        when(() => saveTextEntryUseCase('hello')).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return Right(_buildEntry(EntrySource.manual));
        });
      },
      build: buildBloc,
      seed: () => const InsertionModalTexto(text: 'hello'),
      act: (bloc) {
        bloc.add(const SaveTextSubmitted());
        bloc.add(const SaveTextSubmitted());
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [const InsertionModalTextoSaving('hello')],
      verify: (_) {
        verify(() => saveTextEntryUseCase('hello')).called(1);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'resubmitting from a failure state (tapping Salvar again) works without a dedicated retry event',
      setUp: () {
        when(() => saveTextEntryUseCase('hello'))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.manual)));
      },
      build: buildBloc,
      seed: () =>
          const InsertionModalTextoFailure(text: 'hello', message: 'oops'),
      act: (bloc) => bloc.add(const SaveTextSubmitted()),
      expect: () => [const InsertionModalTextoSaving('hello')],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'partially typed text + ModalClosed creates no entry, draft discarded (US5)',
      build: buildBloc,
      act: (bloc) {
        bloc.add(const TextDraftChanged('partial'));
        bloc.add(const ModalClosed());
      },
      expect: () => [const InsertionModalTexto(text: 'partial')],
      verify: (_) {
        verifyNever(() => saveTextEntryUseCase(any()));
      },
    );
  });

  group('Áudio flow (US1/US2)', () {
    blocTest<InsertionModalBloc, InsertionModalState>(
      'TabSelected(audio) opens on the idle state, without checking '
      'permission or starting recording',
      build: buildBloc,
      act: (bloc) => bloc.add(const TabSelected(CaptureTab.audio)),
      expect: () => [const InsertionModalAudioIdle()],
      verify: (_) {
        verifyNever(() => audioCaptureRepository.hasPermission());
        verifyNever(() => audioCaptureRepository.start());
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioStartRequested with permission denied',
      setUp: () {
        when(() => audioCaptureRepository.hasPermission())
            .thenAnswer((_) async => false);
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioIdle(),
      act: (bloc) => bloc.add(const AudioStartRequested()),
      expect: () => [const InsertionModalAudioPermissionDenied()],
      verify: (_) {
        verifyNever(() => audioCaptureRepository.start());
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioStartRequested with permission granted starts recording',
      setUp: () {
        when(() => audioCaptureRepository.hasPermission())
            .thenAnswer((_) async => true);
        when(() => audioCaptureRepository.start()).thenAnswer((_) async {});
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioIdle(),
      act: (bloc) => bloc.add(const AudioStartRequested()),
      expect: () => [
        const InsertionModalAudioRecording(elapsed: Duration.zero),
      ],
      verify: (_) {
        verify(() => audioCaptureRepository.start()).called(1);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioStartRequested is ignored unless currently idle',
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const AudioStartRequested()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verifyNever(() => audioCaptureRepository.hasPermission());
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioTimerTicked advances elapsed by one second while recording',
      build: buildBloc,
      seed: () =>
          const InsertionModalAudioRecording(elapsed: Duration(seconds: 3)),
      act: (bloc) => bloc.add(const AudioTimerTicked()),
      expect: () => [
        const InsertionModalAudioRecording(elapsed: Duration(seconds: 4)),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioStopRequested is ignored unless currently recording',
      build: buildBloc,
      act: (bloc) => bloc.add(const AudioStopRequested()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verifyNever(() => audioCaptureRepository.stop());
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioStopRequested reaches Processing then Transcribed on success, '
      'with no entries-create call made in between (SC-001)',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async => const Right('hello world'));
      },
      build: buildBloc,
      seed: () =>
          const InsertionModalAudioRecording(elapsed: Duration(seconds: 5)),
      act: (bloc) => bloc.add(const AudioStopRequested()),
      expect: () => [
        const InsertionModalAudioProcessing(duration: Duration(seconds: 5)),
        const InsertionModalAudioTranscribed(
          text: 'hello world',
          duration: Duration(seconds: 5),
        ),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'empty-result transcription maps to InsertionModalAudioFailure, no entry created',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async => const Left(EmptyRecognitionResult()));
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const AudioStopRequested()),
      expect: () => [
        const InsertionModalAudioProcessing(duration: Duration.zero),
        isA<InsertionModalAudioFailure>(),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'generic transcription error maps to InsertionModalAudioFailure',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async => const Left(TranscriptionError()));
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const AudioStopRequested()),
      expect: () => [
        const InsertionModalAudioProcessing(duration: Duration.zero),
        isA<InsertionModalAudioFailure>(),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioReviewTextChanged updates the held draft and re-emits the same state subtype',
      build: buildBloc,
      seed: () => const InsertionModalAudioTranscribed(
        text: 'hello world',
        duration: Duration(seconds: 5),
      ),
      act: (bloc) => bloc.add(const AudioReviewTextChanged('edited text')),
      expect: () => [
        const InsertionModalAudioTranscribed(
          text: 'edited text',
          duration: Duration(seconds: 5),
        ),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioSaveConfirmed with edited text creates the entry with that edited '
      'text and source: audio, then triggers the close side-effect',
      setUp: () {
        when(() => confirmEntrySaveUseCase('edited text', EntrySource.audio))
            .thenAnswer(
              (_) async => Right(
                _buildEntry(EntrySource.audio, content: 'edited text'),
              ),
            );
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioTranscribed(
        text: 'hello world',
        duration: Duration(seconds: 5),
      ),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const AudioReviewTextChanged('edited text'));
        bloc.add(const AudioSaveConfirmed());
      },
      expect: () => [
        const InsertionModalAudioTranscribed(
          text: 'edited text',
          duration: Duration(seconds: 5),
        ),
        const InsertionModalAudioSaving(
          text: 'edited text',
          duration: Duration(seconds: 5),
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase('edited text', EntrySource.audio),
        ).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a repeat AudioSaveConfirmed while already Saving is ignored (no duplicate entry)',
      setUp: () {
        when(() => confirmEntrySaveUseCase('hello world', EntrySource.audio))
            .thenAnswer((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return Right(_buildEntry(EntrySource.audio));
            });
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioTranscribed(
        text: 'hello world',
        duration: Duration(seconds: 5),
      ),
      act: (bloc) {
        bloc.add(const AudioSaveConfirmed());
        bloc.add(const AudioSaveConfirmed());
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [
        const InsertionModalAudioSaving(
          text: 'hello world',
          duration: Duration(seconds: 5),
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase('hello world', EntrySource.audio),
        ).called(1);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'AudioSaveConfirmed while the reviewed text is whitespace-only is ignored '
      '(bypassing the UI\'s disabled Salvar) — no entry created, no state change',
      build: buildBloc,
      seed: () => const InsertionModalAudioTranscribed(
        text: 'hello world',
        duration: Duration(seconds: 5),
      ),
      act: (bloc) {
        bloc.add(const AudioReviewTextChanged('   '));
        bloc.add(const AudioSaveConfirmed());
      },
      expect: () => [
        const InsertionModalAudioTranscribed(
          text: '   ',
          duration: Duration(seconds: 5),
        ),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'ConfirmEntrySaveUseCase offline/creation failure from Transcrito maps '
      'to InsertionModalAudioSaveFailure, preserving the held text/duration',
      setUp: () {
        when(() => confirmEntrySaveUseCase('hello world', EntrySource.audio))
            .thenAnswer((_) async => const Left(ConfirmEntrySaveOffline()));
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioTranscribed(
        text: 'hello world',
        duration: Duration(seconds: 5),
      ),
      act: (bloc) => bloc.add(const AudioSaveConfirmed()),
      expect: () => [
        const InsertionModalAudioSaving(
          text: 'hello world',
          duration: Duration(seconds: 5),
        ),
        isA<InsertionModalAudioSaveFailure>()
            .having((s) => s.text, 'text', 'hello world')
            .having((s) => s.duration, 'duration', const Duration(seconds: 5)),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a subsequent AudioSaveConfirmed from AudioSaveFailure retries and '
      'creates exactly one entry on success',
      setUp: () {
        when(() => confirmEntrySaveUseCase('hello world', EntrySource.audio))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.audio)));
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioSaveFailure(
        text: 'hello world',
        duration: Duration(seconds: 5),
        message: 'offline',
      ),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const AudioSaveConfirmed());
      },
      expect: () => [
        const InsertionModalAudioSaving(
          text: 'hello world',
          duration: Duration(seconds: 5),
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase('hello world', EntrySource.audio),
        ).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a transcribe() result that resolves after the bloc has moved away '
      'from the matching AudioProcessing state is discarded (research.md R6)',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return const Right('late result');
            });
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) async {
        bloc.add(const AudioStopRequested());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const TabSelected(CaptureTab.texto));
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const InsertionModalAudioProcessing(duration: Duration.zero),
        const InsertionModalTexto(),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'RetryRequested re-transcribes the same held path without a new stop() call',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async => const Left(TranscriptionError()));
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) async {
        bloc.add(const AudioStopRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async => const Right('hello world'));
        bloc.add(const RetryRequested());
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const InsertionModalAudioProcessing(duration: Duration.zero),
        isA<InsertionModalAudioFailure>(),
        const InsertionModalAudioProcessing(duration: Duration.zero),
        const InsertionModalAudioTranscribed(
          text: 'hello world',
          duration: Duration.zero,
        ),
      ],
      verify: (_) {
        verify(() => audioCaptureRepository.stop()).called(1);
        verify(() => audioTranscriptionRepository.transcribe(audioPath))
            .called(2);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'TabSelected(<other>) mid-recording discards it',
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const TabSelected(CaptureTab.texto)),
      expect: () => [const InsertionModalTexto()],
      verify: (_) {
        verify(() => audioCaptureRepository.discard()).called(1);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'closing the modal from AudioTranscribed with unsaved edits discards '
      'both the edits and the capture — no entry created (US5 Scenario 2)',
      build: buildBloc,
      seed: () => const InsertionModalAudioTranscribed(
        text: 'hello world',
        duration: Duration(seconds: 5),
      ),
      act: (bloc) {
        bloc.add(const AudioReviewTextChanged('unsaved edit'));
        bloc.add(const ModalClosed());
        bloc.add(const TabSelected(CaptureTab.audio));
      },
      expect: () => [
        const InsertionModalAudioTranscribed(
          text: 'unsaved edit',
          duration: Duration(seconds: 5),
        ),
        const InsertionModalAudioIdle(),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'switching tabs from AudioSaveFailure discards the held audio — no '
      'entry created (US5 Scenario 3)',
      build: buildBloc,
      seed: () => const InsertionModalAudioSaveFailure(
        text: 'hello world',
        duration: Duration(seconds: 5),
        message: 'offline',
      ),
      act: (bloc) {
        bloc.add(const TabSelected(CaptureTab.audio));
      },
      expect: () => [const InsertionModalAudioIdle()],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'ModalClosed mid-recording discards it, creates no entry',
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const ModalClosed()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verify(() => audioCaptureRepository.discard()).called(1);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'bloc disposal mid-recording (swipe-down/tap-outside dismissal, '
      'bypassing ModalClosed) still discards the recording',
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) async {},
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verify(() => audioCaptureRepository.discard()).called(1);
      },
    );
  });

  group('Foto flow (US3/US4)', () {
    blocTest<InsertionModalBloc, InsertionModalState>(
      'TabSelected(foto) goes straight to the two-button Captura state',
      build: buildBloc,
      act: (bloc) => bloc.add(const TabSelected(CaptureTab.foto)),
      expect: () => [const InsertionModalFotoCaptura()],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSourceSelected cancelled (null) stays on Captura, creates no entry',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => null);
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.gallery)),
      verify: (_) {
        verifyNever(() => recognizePhotoUseCase(any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSourceSelected when the OS picker throws (permission revoked) shows the permission-denied message',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.camera))
            .thenThrow(Exception('camera access denied'));
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.camera)),
      expect: () => [const InsertionModalFotoPermissionDenied()],
      verify: (_) {
        verifyNever(() => recognizePhotoUseCase(any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSourceSelected reaches Processing then Reconhecido on success, '
      'with no entries-create call made in between (SC-002)',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.camera))
            .thenAnswer((_) async => imagePath);
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer(
          (_) async =>
              const Right(OcrResult(text: 'hello world', confidence: 'high')),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.camera)),
      expect: () => [
        const InsertionModalFotoProcessing(imagePath: imagePath),
        const InsertionModalFotoReconhecido(
          imagePath: imagePath,
          text: 'hello world',
        ),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'offline before OCR maps to InsertionModalFotoFailure with the offline message',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer(
          (_) async => const Left(PhotoRecognitionOffline()),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.gallery)),
      expect: () => [
        const InsertionModalFotoProcessing(imagePath: imagePath),
        isA<InsertionModalFotoFailure>(),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'OCR_NO_TEXT recognition failure maps to InsertionModalFotoFailure',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer(
          (_) async => const Left(
            PhotoRecognitionCallFailed(
              OcrNoTextFailure(message: 'no text', requestId: 'r1'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.gallery)),
      expect: () => [
        const InsertionModalFotoProcessing(imagePath: imagePath),
        isA<InsertionModalFotoFailure>(),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'another recognition failure maps to InsertionModalFotoFailure with '
      "the same 'no text recognized' copy as OCR_NO_TEXT, not the raw "
      'backend message (FR-007)',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer(
          (_) async => const Left(
            PhotoRecognitionCallFailed(
              ValidationFailure(message: 'bad request', requestId: 'r2'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.gallery)),
      expect: () => [
        const InsertionModalFotoProcessing(imagePath: imagePath),
        const InsertionModalFotoFailure(
          imagePath: imagePath,
          message: 'Não foi possível reconhecer o texto — tente outra foto.',
        ),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoReviewTextChanged updates the held draft',
      build: buildBloc,
      seed: () => const InsertionModalFotoReconhecido(
        imagePath: imagePath,
        text: 'hello world',
      ),
      act: (bloc) => bloc.add(const PhotoReviewTextChanged('edited text')),
      expect: () => [
        const InsertionModalFotoReconhecido(
          imagePath: imagePath,
          text: 'edited text',
        ),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSaveConfirmed with the current (possibly edited) text creates '
      'the entry with source: photo, then triggers the close side-effect',
      setUp: () {
        when(() => confirmEntrySaveUseCase('edited text', EntrySource.photo))
            .thenAnswer(
              (_) async => Right(
                _buildEntry(EntrySource.photo, content: 'edited text'),
              ),
            );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoReconhecido(
        imagePath: imagePath,
        text: 'hello world',
      ),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const PhotoReviewTextChanged('edited text'));
        bloc.add(const PhotoSaveConfirmed());
      },
      expect: () => [
        const InsertionModalFotoReconhecido(
          imagePath: imagePath,
          text: 'edited text',
        ),
        const InsertionModalFotoSaving(
          imagePath: imagePath,
          text: 'edited text',
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase('edited text', EntrySource.photo),
        ).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a repeat PhotoSaveConfirmed while already Saving is ignored',
      setUp: () {
        when(() => confirmEntrySaveUseCase('hello world', EntrySource.photo))
            .thenAnswer((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return Right(_buildEntry(EntrySource.photo));
            });
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoReconhecido(
        imagePath: imagePath,
        text: 'hello world',
      ),
      act: (bloc) {
        bloc.add(const PhotoSaveConfirmed());
        bloc.add(const PhotoSaveConfirmed());
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [
        const InsertionModalFotoSaving(
          imagePath: imagePath,
          text: 'hello world',
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase('hello world', EntrySource.photo),
        ).called(1);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSaveConfirmed while the reviewed text is whitespace-only is ignored',
      build: buildBloc,
      seed: () => const InsertionModalFotoReconhecido(
        imagePath: imagePath,
        text: 'hello world',
      ),
      act: (bloc) {
        bloc.add(const PhotoReviewTextChanged('   '));
        bloc.add(const PhotoSaveConfirmed());
      },
      expect: () => [
        const InsertionModalFotoReconhecido(imagePath: imagePath, text: '   '),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'ConfirmEntrySaveUseCase failure from Reconhecido maps to '
      'InsertionModalFotoSaveFailure, preserving the held path/text',
      setUp: () {
        when(() => confirmEntrySaveUseCase('hello world', EntrySource.photo))
            .thenAnswer(
              (_) async => const Left(
                ConfirmEntrySaveCreationFailed(
                  NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'),
                ),
              ),
            );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoReconhecido(
        imagePath: imagePath,
        text: 'hello world',
      ),
      act: (bloc) => bloc.add(const PhotoSaveConfirmed()),
      expect: () => [
        const InsertionModalFotoSaving(
          imagePath: imagePath,
          text: 'hello world',
        ),
        const InsertionModalFotoSaveFailure(
          imagePath: imagePath,
          text: 'hello world',
          message: 'timed out',
        ),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a subsequent PhotoSaveConfirmed from FotoSaveFailure retries and '
      'creates exactly one entry on success',
      setUp: () {
        when(() => confirmEntrySaveUseCase('hello world', EntrySource.photo))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.photo)));
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoSaveFailure(
        imagePath: imagePath,
        text: 'hello world',
        message: 'timed out',
      ),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const PhotoSaveConfirmed());
      },
      expect: () => [
        const InsertionModalFotoSaving(
          imagePath: imagePath,
          text: 'hello world',
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase('hello world', EntrySource.photo),
        ).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'a recognize() result that resolves after the bloc has moved away from '
      'the matching FotoProcessing state is discarded (research.md R6)',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return const Right(OcrResult(text: 'late result', confidence: 'high'));
        });
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) async {
        bloc.add(const PhotoSourceSelected(PhotoSource.gallery));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const TabSelected(CaptureTab.texto));
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const InsertionModalFotoProcessing(imagePath: imagePath),
        const InsertionModalTexto(),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'RetryRequested re-runs OCR on the same held image without a new pickImage() call',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer(
          (_) async => const Left(
            PhotoRecognitionCallFailed(
              ValidationFailure(message: 'bad request', requestId: 'r2'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) async {
        bloc.add(const PhotoSourceSelected(PhotoSource.gallery));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        when(() => recognizePhotoUseCase(imagePath)).thenAnswer(
          (_) async =>
              const Right(OcrResult(text: 'hello world', confidence: 'high')),
        );
        bloc.add(const RetryRequested());
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const InsertionModalFotoProcessing(imagePath: imagePath),
        const InsertionModalFotoFailure(
          imagePath: imagePath,
          message: 'Não foi possível reconhecer o texto — tente outra foto.',
        ),
        const InsertionModalFotoProcessing(imagePath: imagePath),
        const InsertionModalFotoReconhecido(
          imagePath: imagePath,
          text: 'hello world',
        ),
      ],
      verify: (_) {
        verify(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .called(1);
        verify(() => recognizePhotoUseCase(imagePath)).called(2);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSaveWithoutTextRequested creates exactly one entry with the '
      'fixed placeholder content and no further recognize() call (SC-004)',
      setUp: () {
        when(
          () => confirmEntrySaveUseCase(
            'Foto registrada sem texto reconhecido.',
            EntrySource.photo,
          ),
        ).thenAnswer((_) async => Right(_buildEntry(EntrySource.photo)));
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoFailure(
        imagePath: imagePath,
        message: 'Não foi possível reconhecer o texto',
      ),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const PhotoSaveWithoutTextRequested());
      },
      expect: () => [
        const InsertionModalFotoSaving(
          imagePath: imagePath,
          text: 'Foto registrada sem texto reconhecido.',
        ),
      ],
      verify: (_) {
        verify(
          () => confirmEntrySaveUseCase(
            'Foto registrada sem texto reconhecido.',
            EntrySource.photo,
          ),
        ).called(1);
        verifyNever(() => recognizePhotoUseCase(any()));
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'closing the modal from FotoReconhecido with unsaved edits discards both '
      'the edits and the picked image — no entry created (US5 Scenario 2)',
      build: buildBloc,
      seed: () => const InsertionModalFotoReconhecido(
        imagePath: imagePath,
        text: 'hello world',
      ),
      act: (bloc) {
        bloc.add(const PhotoReviewTextChanged('unsaved edit'));
        bloc.add(const ModalClosed());
        bloc.add(const TabSelected(CaptureTab.foto));
      },
      expect: () => [
        const InsertionModalFotoReconhecido(
          imagePath: imagePath,
          text: 'unsaved edit',
        ),
        const InsertionModalFotoCaptura(),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'switching tabs from FotoFailure discards the held image — no entry '
      'created, closing instead of choosing either action (US5 Scenario 3)',
      build: buildBloc,
      seed: () => const InsertionModalFotoFailure(
        imagePath: imagePath,
        message: 'Não foi possível reconhecer o texto',
      ),
      act: (bloc) {
        bloc.add(const TabSelected(CaptureTab.foto));
      },
      expect: () => [const InsertionModalFotoCaptura()],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
        verifyNever(() => recognizePhotoUseCase(any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'ModalClosed while on Captura creates no entry',
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const ModalClosed()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );
  });

  group('Cross-modality abandonment (US5)', () {
    blocTest<InsertionModalBloc, InsertionModalState>(
      'switching from Áudio to Foto mid-recognition, then back to Áudio, '
      'shows a fresh idle state (no stale Transcrito/Erro resumed)',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => audioTranscriptionRepository.transcribe(audioPath))
            .thenAnswer((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return const Right('late result');
            });
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) async {
        bloc.add(const AudioStopRequested());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const TabSelected(CaptureTab.foto));
        bloc.add(const TabSelected(CaptureTab.audio));
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const InsertionModalAudioProcessing(duration: Duration.zero),
        const InsertionModalFotoCaptura(),
        const InsertionModalAudioIdle(),
      ],
      verify: (_) {
        verifyNever(() => confirmEntrySaveUseCase(any(), any()));
      },
    );
  });
}
