import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:cerne/features/capture/domain/usecases/recognize_photo_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockPhotoRecognitionRepository extends Mock
    implements PhotoRecognitionRepository {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

void main() {
  late MockPhotoRecognitionRepository recognitionRepository;
  late MockConnectivityChecker connectivityChecker;
  late RecognizePhotoUseCase useCase;

  const imagePath = '/tmp/photo.jpg';

  setUp(() {
    recognitionRepository = MockPhotoRecognitionRepository();
    connectivityChecker = MockConnectivityChecker();
    useCase = RecognizePhotoUseCase(
      recognitionRepository: recognitionRepository,
      connectivityChecker: connectivityChecker,
    );
  });

  test('offline short-circuit before recognize() is ever called', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => false);

    final result = await useCase(imagePath);

    expect(
      result,
      const Left<PhotoRecognitionAttemptFailure, OcrResult>(
        PhotoRecognitionOffline(),
      ),
    );
    verifyNever(() => recognitionRepository.recognize(any()));
  });

  test('repository Right(ocrResult) passes through unchanged', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const ocrResult = OcrResult(text: 'hello world', confidence: 'high');
    when(() => recognitionRepository.recognize(imagePath))
        .thenAnswer((_) async => const Right(ocrResult));

    final result = await useCase(imagePath);

    expect(result, const Right<PhotoRecognitionAttemptFailure, OcrResult>(ocrResult));
  });

  test('repository Left(OcrNoTextFailure) wraps into PhotoRecognitionCallFailed', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const failure = OcrNoTextFailure(message: 'no text', requestId: 'r1');
    when(() => recognitionRepository.recognize(imagePath))
        .thenAnswer((_) async => const Left(failure));

    final result = await useCase(imagePath);

    final left = result.getLeft().toNullable();
    expect(left, isA<PhotoRecognitionCallFailed>());
    expect((left! as PhotoRecognitionCallFailed).failure, failure);
  });

  test('repository Left(<other Failure>) wraps into PhotoRecognitionCallFailed', () async {
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r2');
    when(() => recognitionRepository.recognize(imagePath))
        .thenAnswer((_) async => const Left(failure));

    final result = await useCase(imagePath);

    final left = result.getLeft().toNullable();
    expect(left, isA<PhotoRecognitionCallFailed>());
    expect((left! as PhotoRecognitionCallFailed).failure, failure);
  });
}
