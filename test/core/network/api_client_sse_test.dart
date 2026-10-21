import 'dart:async';
import 'dart:typed_data';

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/network/sse_frame.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockDio extends Mock implements Dio {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

void main() {
  late MockDio dio;
  late MockSecureTokenStorage tokenStorage;
  late ApiClient client;

  const anonKey = 'anon-key';
  const baseUrl = 'https://example.supabase.co/functions/v1';

  setUpAll(() {
    dotenv.loadFromString(envString: 'FUNCTIONS_BASE_URL=$baseUrl');
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = MockDio();
    tokenStorage = MockSecureTokenStorage();
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => 'default-token');
    client = ApiClient(dio: dio, tokenStorage: tokenStorage, anonKey: anonKey);
  });

  void stubStreamResponse(Stream<Uint8List> byteStream) {
    when(
      () => dio.request<ResponseBody>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<ResponseBody>(
        requestOptions: RequestOptions(path: ''),
        statusCode: 200,
        data: ResponseBody(byteStream, 200),
      ),
    );
  }

  void stubStreamThrows(DioException exception) {
    when(
      () => dio.request<ResponseBody>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(exception);
  }

  test('a stream with 3 frames split across 2 raw byte chunks mid-frame parses all 3 correctly', () async {
    const full =
        'event: message_created\ndata: {"a":1}\n\n'
        'event: token\ndata: {"b":2}\n\n'
        'event: done\ndata: {"c":3}\n\n';
    final bytes = Uint8List.fromList(full.codeUnits);
    final splitIndex = bytes.length ~/ 2 + 3; // mid-frame, not on a boundary
    stubStreamResponse(
      Stream.fromIterable([bytes.sublist(0, splitIndex), bytes.sublist(splitIndex)]),
    );

    final frames = await client
        .sseStream('chat-messages-send', method: 'POST')
        .toList();

    expect(frames, hasLength(3));
    expect(frames[0], Right<Failure, SseFrame>(const SseFrame(event: 'message_created', data: '{"a":1}')));
    expect(frames[1], Right<Failure, SseFrame>(const SseFrame(event: 'token', data: '{"b":2}')));
    expect(frames[2], Right<Failure, SseFrame>(const SseFrame(event: 'done', data: '{"c":3}')));
  });

  test('a DioException thrown mid-stream after 1 frame yields that frame then exactly one Left(NetworkTimeoutFailure)', () async {
    const frame = 'event: token\ndata: {"delta":"hi"}\n\n';
    final controller = StreamController<Uint8List>();
    stubStreamResponse(controller.stream);

    final results = <Either<Failure, SseFrame>>[];
    final subscription = client.sseStream('chat-messages-send', method: 'POST').listen(results.add);

    controller.add(Uint8List.fromList(frame.codeUnits));
    await Future<void>.delayed(Duration.zero);
    controller.addError(
      DioException(requestOptions: RequestOptions(path: ''), type: DioExceptionType.connectionTimeout),
    );
    await controller.close();
    await subscription.asFuture<void>();
    await subscription.cancel();

    expect(results, hasLength(2));
    expect(results[0].isRight(), isTrue);
    expect(results[1].isLeft(), isTrue);
    expect(results[1].getLeft().toNullable(), isA<NetworkTimeoutFailure>());
  });

  test('a DioException with no response at all yields Left(NetworkOfflineFailure) as the final item', () async {
    stubStreamThrows(DioException(requestOptions: RequestOptions(path: ''), type: DioExceptionType.connectionError));

    final results = await client.sseStream('chat-messages-send', method: 'POST').toList();

    expect(results, hasLength(1));
    expect(results.single.isLeft(), isTrue);
    expect(results.single.getLeft().toNullable(), isA<NetworkOfflineFailure>());
  });

  test('a frame containing only event: context / data: {} is yielded as an ordinary SseFrame', () async {
    stubStreamResponse(Stream.fromIterable([
      Uint8List.fromList('event: context\ndata: {}\n\n'.codeUnits),
    ]));

    final results = await client.sseStream('chat-messages-send', method: 'POST').toList();

    expect(results, hasLength(1));
    expect(results.single, Right<Failure, SseFrame>(const SseFrame(event: 'context', data: '{}')));
  });

  test('a multi-line data: field is joined with \\n into one SseFrame.data string', () async {
    stubStreamResponse(Stream.fromIterable([
      Uint8List.fromList('event: done\ndata: {"a":1,\ndata: "b":2}\n\n'.codeUnits),
    ]));

    final results = await client.sseStream('chat-messages-send', method: 'POST').toList();

    expect(results, hasLength(1));
    expect(
      results.single,
      Right<Failure, SseFrame>(const SseFrame(event: 'done', data: '{"a":1,\n"b":2}')),
    );
  });
}
