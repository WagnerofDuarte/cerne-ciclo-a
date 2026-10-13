import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/data/media_ocr_remote_data_source.dart';
import 'package:cerne/features/capture/data/photo_recognition_repository_impl.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockMediaOcrRemoteDataSource extends Mock implements MediaOcrRemoteDataSource {}

void main() {
  late MockMediaOcrRemoteDataSource remote;
  late PhotoRecognitionRepositoryImpl repository;

  const imagePath = '/tmp/photo.jpg';

  setUp(() {
    remote = MockMediaOcrRemoteDataSource();
    repository = PhotoRecognitionRepositoryImpl(remote);
  });

  void stubRecognize(Either<Failure, Map<String, dynamic>> result) {
    when(() => remote.recognize(imagePath)).thenAnswer((_) async => result);
  }

  test('NetworkTimeoutFailure passes through unchanged', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    stubRecognize(const Left(failure));

    final result = await repository.recognize(imagePath);

    expect(result, const Left<Failure, OcrResult>(failure));
  });

  test('NetworkOfflineFailure passes through unchanged', () async {
    const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
    stubRecognize(const Left(failure));

    final result = await repository.recognize(imagePath);

    expect(result, const Left<Failure, OcrResult>(failure));
  });

  test('malformed response failure passes through unchanged', () async {
    const failure = ValidationFailure(message: 'malformed', requestId: 'r3');
    stubRecognize(const Left(failure));

    final result = await repository.recognize(imagePath);

    expect(result, const Left<Failure, OcrResult>(failure));
  });

  test('OCR_NO_TEXT failure passes through unchanged', () async {
    const failure = OcrNoTextFailure(message: 'no text', requestId: 'r4');
    stubRecognize(const Left(failure));

    final result = await repository.recognize(imagePath);

    expect(result, const Left<Failure, OcrResult>(failure));
  });

  test('a 200 response with blank text is normalized to OcrNoTextFailure', () async {
    stubRecognize(const Right({'text': '   ', 'confidence': 'high'}));

    final result = await repository.recognize(imagePath);

    expect(result.getLeft().toNullable(), isA<OcrNoTextFailure>());
  });

  test('a valid success body parses into OcrResult', () async {
    stubRecognize(const Right({'text': 'hello', 'confidence': 'low'}));

    final result = await repository.recognize(imagePath);

    expect(result, const Right<Failure, OcrResult>(OcrResult(text: 'hello', confidence: 'low')));
  });
}
