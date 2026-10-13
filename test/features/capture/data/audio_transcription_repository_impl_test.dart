import 'package:cerne/features/capture/data/audio_transcription_repository_impl.dart';
import 'package:cerne/features/capture/data/whisper_transcription_data_source.dart';
import 'package:cerne/features/capture/domain/entities/recognition_failure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockWhisperTranscriptionDataSource extends Mock
    implements WhisperTranscriptionDataSource {}

void main() {
  late MockWhisperTranscriptionDataSource dataSource;
  late AudioTranscriptionRepositoryImpl repository;

  const audioPath = '/tmp/audio.wav';

  setUp(() {
    dataSource = MockWhisperTranscriptionDataSource();
    repository = AudioTranscriptionRepositoryImpl(dataSource);
  });

  test('empty transcript -> EmptyRecognitionResult', () async {
    when(() => dataSource.transcribe(audioPath)).thenAnswer((_) async => '   ');

    final result = await repository.transcribe(audioPath);

    expect(result.getLeft().toNullable(), isA<EmptyRecognitionResult>());
  });

  test('whitespace-only transcript -> EmptyRecognitionResult', () async {
    when(() => dataSource.transcribe(audioPath)).thenAnswer((_) async => '\n\t ');

    final result = await repository.transcribe(audioPath);

    expect(result.getLeft().toNullable(), isA<EmptyRecognitionResult>());
  });

  test('thrown exception -> TranscriptionError', () async {
    when(() => dataSource.transcribe(audioPath))
        .thenThrow(const WhisperTranscriptionFailedException());

    final result = await repository.transcribe(audioPath);

    expect(result.getLeft().toNullable(), isA<TranscriptionError>());
  });

  test('happy path -> Right(text), trimmed', () async {
    when(() => dataSource.transcribe(audioPath)).thenAnswer((_) async => '  hello world  ');

    final result = await repository.transcribe(audioPath);

    expect(result.getRight().toNullable(), 'hello world');
  });
}
