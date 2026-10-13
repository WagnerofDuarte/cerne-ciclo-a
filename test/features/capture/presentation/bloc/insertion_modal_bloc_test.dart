import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:cerne/features/capture/domain/usecases/save_audio_entry_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/save_photo_entry_usecase.dart';
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

class MockSaveAudioEntryUseCase extends Mock implements SaveAudioEntryUseCase {}

class MockPhotoCaptureRepository extends Mock
    implements PhotoCaptureRepository {}

class MockSavePhotoEntryUseCase extends Mock implements SavePhotoEntryUseCase {}

Entry _buildEntry(EntrySource source) => Entry(
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
  late MockSaveTextEntryUseCase saveTextEntryUseCase;
  late MockAudioCaptureRepository audioCaptureRepository;
  late MockSaveAudioEntryUseCase saveAudioEntryUseCase;
  late MockPhotoCaptureRepository photoCaptureRepository;
  late MockSavePhotoEntryUseCase savePhotoEntryUseCase;

  const audioPath = '/tmp/audio.wav';
  const imagePath = '/tmp/photo.jpg';
  var closeSignalFired = false;

  setUp(() {
    closeSignalFired = false;
    saveTextEntryUseCase = MockSaveTextEntryUseCase();
    audioCaptureRepository = MockAudioCaptureRepository();
    saveAudioEntryUseCase = MockSaveAudioEntryUseCase();
    photoCaptureRepository = MockPhotoCaptureRepository();
    savePhotoEntryUseCase = MockSavePhotoEntryUseCase();

    when(() => audioCaptureRepository.discard()).thenReturn(null);
  });

  InsertionModalBloc buildBloc() => InsertionModalBloc(
    saveTextEntryUseCase: saveTextEntryUseCase,
    audioCaptureRepository: audioCaptureRepository,
    saveAudioEntryUseCase: saveAudioEntryUseCase,
    photoCaptureRepository: photoCaptureRepository,
    savePhotoEntryUseCase: savePhotoEntryUseCase,
  );

  test('initial state is InsertionModalTexto with an empty draft', () {
    expect(buildBloc().state, const InsertionModalTexto());
  });

  group('Texto flow (US1)', () {
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
      'partially typed text + ModalClosed creates no entry, draft discarded (US4)',
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

  group('Áudio flow (US2)', () {
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
      'AudioStopRequested success triggers the close side-effect',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => saveAudioEntryUseCase(audioPath))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.audio)));
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const AudioStopRequested());
      },
      expect: () => [const InsertionModalAudioSaving()],
      verify: (_) {
        verify(() => saveAudioEntryUseCase(audioPath)).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'recognition failure maps to InsertionModalAudioFailure',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => saveAudioEntryUseCase(audioPath)).thenAnswer(
          (_) async =>
              const Left(SaveAudioRecognitionFailed(EmptyRecognitionResult())),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const AudioStopRequested()),
      expect: () => [
        const InsertionModalAudioSaving(),
        isA<InsertionModalAudioFailure>(),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'entry-creation failure maps to InsertionModalAudioFailure with the backend message',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => saveAudioEntryUseCase(audioPath)).thenAnswer(
          (_) async => const Left(
            SaveAudioEntryCreationFailed(
              NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const AudioStopRequested()),
      expect: () => [
        const InsertionModalAudioSaving(),
        const InsertionModalAudioFailure('timed out'),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'RetryRequested re-uses the held audio path without calling stop() again',
      setUp: () {
        when(() => audioCaptureRepository.stop())
            .thenAnswer((_) async => audioPath);
        when(() => saveAudioEntryUseCase(audioPath)).thenAnswer(
          (_) async => const Left(
            SaveAudioEntryCreationFailed(
              NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) async {
        bloc.add(const AudioStopRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        when(() => saveAudioEntryUseCase(audioPath))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.audio)));
        bloc.add(const RetryRequested());
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const InsertionModalAudioSaving(),
        const InsertionModalAudioFailure('timed out'),
        const InsertionModalAudioSaving(),
      ],
      verify: (_) {
        verify(() => audioCaptureRepository.stop()).called(1);
        verify(() => saveAudioEntryUseCase(audioPath)).called(2);
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
      'ModalClosed mid-recording discards it, creates no entry (US4)',
      build: buildBloc,
      seed: () => const InsertionModalAudioRecording(elapsed: Duration.zero),
      act: (bloc) => bloc.add(const ModalClosed()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verify(() => audioCaptureRepository.discard()).called(1);
        verifyNever(() => saveAudioEntryUseCase(any()));
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
        verifyNever(() => saveAudioEntryUseCase(any()));
      },
    );
  });

  group('Foto flow (US3)', () {
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
        verifyNever(() => savePhotoEntryUseCase(any()));
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
        verifyNever(() => savePhotoEntryUseCase(any()));
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'PhotoSourceSelected success triggers the close side-effect',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.camera))
            .thenAnswer((_) async => imagePath);
        when(() => savePhotoEntryUseCase(imagePath))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.photo)));
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) {
        bloc.closeRequests.listen((_) => closeSignalFired = true);
        bloc.add(const PhotoSourceSelected(PhotoSource.camera));
      },
      expect: () => [const InsertionModalFotoSaving()],
      verify: (_) {
        verify(() => savePhotoEntryUseCase(imagePath)).called(1);
        expect(closeSignalFired, isTrue);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'OCR_NO_TEXT recognition failure maps to InsertionModalFotoFailure',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => savePhotoEntryUseCase(imagePath)).thenAnswer(
          (_) async => const Left(
            SavePhotoRecognitionFailed(
              OcrNoTextFailure(message: 'no text', requestId: 'r1'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.gallery)),
      expect: () => [
        const InsertionModalFotoSaving(),
        isA<InsertionModalFotoFailure>(),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'entry-creation failure maps to InsertionModalFotoFailure with the backend message',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => savePhotoEntryUseCase(imagePath)).thenAnswer(
          (_) async => const Left(
            SavePhotoEntryCreationFailed(
              ValidationFailure(message: 'bad request', requestId: 'r2'),
            ),
          ),
        );
      },
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const PhotoSourceSelected(PhotoSource.gallery)),
      expect: () => [
        const InsertionModalFotoSaving(),
        const InsertionModalFotoFailure('bad request'),
      ],
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'RetryRequested re-uses the held image path without calling pickImage() again',
      setUp: () {
        when(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .thenAnswer((_) async => imagePath);
        when(() => savePhotoEntryUseCase(imagePath)).thenAnswer(
          (_) async => const Left(
            SavePhotoEntryCreationFailed(
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
        when(() => savePhotoEntryUseCase(imagePath))
            .thenAnswer((_) async => Right(_buildEntry(EntrySource.photo)));
        bloc.add(const RetryRequested());
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const InsertionModalFotoSaving(),
        const InsertionModalFotoFailure('bad request'),
        const InsertionModalFotoSaving(),
      ],
      verify: (_) {
        verify(() => photoCaptureRepository.pickImage(PhotoSource.gallery))
            .called(1);
        verify(() => savePhotoEntryUseCase(imagePath)).called(2);
      },
    );

    blocTest<InsertionModalBloc, InsertionModalState>(
      'ModalClosed while on Captura creates no entry (US4)',
      build: buildBloc,
      seed: () => const InsertionModalFotoCaptura(),
      act: (bloc) => bloc.add(const ModalClosed()),
      expect: () => <InsertionModalState>[],
      verify: (_) {
        verifyNever(() => savePhotoEntryUseCase(any()));
      },
    );
  });
}
