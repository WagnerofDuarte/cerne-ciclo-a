import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/network/sse_frame.dart';
import 'package:cerne/features/chat/data/chat_remote_data_source.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/entities/insight_trigger.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late ChatRemoteDataSource dataSource;

  final validSessionData = {
    'id': 'session-1',
    'title': 'Como lidar com ansiedade',
    'personaSnapshot': 'analitico',
    'userMessageCount': 1,
    'lastUserMessageAt': '2026-01-01T00:00:00.000Z',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
  };

  setUpAll(() {
    registerFallbackValue(AuthMode.userSession);
  });

  setUp(() {
    apiClient = MockApiClient();
    dataSource = ChatRemoteDataSource(apiClient);
  });

  group('createSession', () {
    void stubCall(Either<Failure, Map<String, dynamic>> result) {
      when(
        () => apiClient.call(
          'chat-sessions-create',
          method: any(named: 'method'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('calls chat-sessions-create with {"title": ...} verbatim', () async {
      stubCall(Right(validSessionData));

      await dataSource.createSession(
        title: 'Como lidar com ansiedade antes de apresentações',
      );

      verify(
        () => apiClient.call(
          'chat-sessions-create',
          method: 'POST',
          body: {'title': 'Como lidar com ansiedade antes de apresentações'},
        ),
      ).called(1);
    });

    test('parses a valid success body into ChatSession', () async {
      stubCall(Right(validSessionData));

      final result = await dataSource.createSession(title: 'x');

      expect(result.isRight(), isTrue);
      final session = result.toNullable()!;
      expect(session.id, 'session-1');
      expect(session.personaSnapshot, ChatPersona.analitico);
      expect(session.userMessageCount, 1);
    });
  });

  group('sendMessage', () {
    void stubSseStream(Stream<Either<Failure, SseFrame>> stream) {
      when(
        () => apiClient.sseStream(
          'chat-messages-send',
          method: any(named: 'method'),
          pathSegments: any(named: 'pathSegments'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => stream);
    }

    test('calls chat-messages-send via sseStream with pathSegments/body', () async {
      stubSseStream(const Stream.empty());

      await dataSource.sendMessage(sessionId: 's1', content: 'hello').toList();

      verify(
        () => apiClient.sseStream(
          'chat-messages-send',
          method: 'POST',
          pathSegments: ['s1'],
          body: {'content': 'hello'},
        ),
      ).called(1);
    });

    test('message_created frame maps to MessageCreated', () async {
      stubSseStream(
        Stream.value(
          const Right(
            SseFrame(
              event: 'message_created',
              data: '{"userMessageId":"u1","assistantMessageId":"a1"}',
            ),
          ),
        ),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, [
        const Right<Failure, ChatStreamEvent>(
          MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1'),
        ),
      ]);
    });

    test('context frame is filtered out (never emitted)', () async {
      stubSseStream(
        Stream.value(const Right(SseFrame(event: 'context', data: '{}'))),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, isEmpty);
    });

    test('token frame maps to TokenReceived(delta) — wire field is "text"', () async {
      stubSseStream(
        Stream.value(const Right(SseFrame(event: 'token', data: '{"text":"ol"}'))),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, [const Right<Failure, ChatStreamEvent>(TokenReceived('ol'))]);
    });

    test('done frame maps to StreamDone — wire shape has no content/createdAt', () async {
      stubSseStream(
        Stream.value(
          const Right(
            SseFrame(
              event: 'done',
              data: '{"assistantMessageId":"a1","finishReason":"end_turn"}',
            ),
          ),
        ),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, [
        const Right<Failure, ChatStreamEvent>(StreamDone(assistantMessageId: 'a1')),
      ]);
    });

    test('error frame maps to Left(ErrorMapper.fromResponse(...))', () async {
      stubSseStream(
        Stream.value(
          const Right(
            SseFrame(
              event: 'error',
              data: '{"code":"AI_GENERATION_TIMEOUT","message":"timed out","retryable":true,"requestId":"r1"}',
            ),
          ),
        ),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, hasLength(1));
      expect(results.single.isLeft(), isTrue);
      expect(results.single.getLeft().toNullable(), isA<AiGenerationTimeoutFailure>());
    });

    test('an unrecognized event name is filtered out, never thrown', () async {
      stubSseStream(
        Stream.value(const Right(SseFrame(event: 'future_event', data: '{}'))),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, isEmpty);
    });

    test('a transport-level Left(Failure) passes through as-is', () async {
      const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
      stubSseStream(Stream.value(const Left(failure)));

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, [const Left<Failure, ChatStreamEvent>(failure)]);
    });

    test('a done frame with malformed JSON yields Left(malformed), never throws', () async {
      stubSseStream(
        Stream.value(const Right(SseFrame(event: 'done', data: 'not json'))),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, hasLength(1));
      expect(results.single.isLeft(), isTrue);
      expect(results.single.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a done frame missing a required field yields Left(malformed), never throws', () async {
      stubSseStream(
        Stream.value(
          const Right(SseFrame(event: 'done', data: '{"finishReason":"end_turn"}')),
        ),
      );

      final results = await dataSource.sendMessage(sessionId: 's1', content: 'hi').toList();

      expect(results, hasLength(1));
      expect(results.single.isLeft(), isTrue);
      expect(results.single.getLeft().toNullable(), isA<ValidationFailure>());
    });
  });

  group('retryMessage', () {
    test('calls chat-messages-retry via sseStream with [sessionId, userMessageId] and empty body', () async {
      when(
        () => apiClient.sseStream(
          'chat-messages-retry',
          method: any(named: 'method'),
          pathSegments: any(named: 'pathSegments'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => const Stream.empty());

      await dataSource.retryMessage(sessionId: 's1', userMessageId: 'u1').toList();

      verify(
        () => apiClient.sseStream(
          'chat-messages-retry',
          method: 'POST',
          pathSegments: ['s1', 'u1'],
          body: const {},
        ),
      ).called(1);
    });
  });

  group('createInsight', () {
    void stubCall(Either<Failure, Map<String, dynamic>> result) {
      when(
        () => apiClient.call(
          'chat-insight-create',
          method: any(named: 'method'),
          pathSegments: any(named: 'pathSegments'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('#1 calls chat-insight-create with [sessionId] and the wire body', () async {
      stubCall(Right({'status': 'ready', 'content': 'Some insight text'}));

      await dataSource.createInsight(
        sessionId: 's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );

      verify(
        () => apiClient.call(
          'chat-insight-create',
          method: 'POST',
          pathSegments: ['s1'],
          body: {'triggerType': 'message_count', 'triggerKey': 'message_count:5'},
        ),
      ).called(1);
    });

    test('inactivity triggerType maps to "inactivity" on the wire', () async {
      stubCall(Right({'status': 'ready', 'content': 'x'}));

      await dataSource.createInsight(
        sessionId: 's1',
        triggerType: InsightTriggerType.inactivity,
        triggerKey: 'inactivity:2026-01-01T00:00:00.000Z',
      );

      verify(
        () => apiClient.call(
          'chat-insight-create',
          method: 'POST',
          pathSegments: ['s1'],
          body: {
            'triggerType': 'inactivity',
            'triggerKey': 'inactivity:2026-01-01T00:00:00.000Z',
          },
        ),
      ).called(1);
    });

    test('#1 status: ready -> Right(content)', () async {
      stubCall(Right({'status': 'ready', 'content': 'Some insight text'}));

      final result = await dataSource.createInsight(
        sessionId: 's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );

      expect(result, const Right<Failure, String>('Some insight text'));
    });

    test(
      '#2 status: failed with errorCode AI_GENERATION_TIMEOUT -> '
      'Left(AiGenerationTimeoutFailure)',
      () async {
        stubCall(
          Right({'status': 'failed', 'errorCode': 'AI_GENERATION_TIMEOUT', 'id': 'ins_1'}),
        );

        final result = await dataSource.createInsight(
          sessionId: 's1',
          triggerType: InsightTriggerType.messageCount,
          triggerKey: 'message_count:5',
        );

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<AiGenerationTimeoutFailure>());
      },
    );

    test(
      '#3 status: failed with null errorCode -> Left(ValidationFailure) '
      "(ErrorMapper's own unrecognized-code default)",
      () async {
        stubCall(Right({'status': 'failed', 'errorCode': null, 'id': 'ins_1'}));

        final result = await dataSource.createInsight(
          sessionId: 's1',
          triggerType: InsightTriggerType.messageCount,
          triggerKey: 'message_count:5',
        );

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      },
    );

    test('#4 missing status -> Left(_malformedChatFailure), never throws', () async {
      stubCall(Right({'content': 'x'}));

      final result = await dataSource.createInsight(
        sessionId: 's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('#5 a transport timeout passes through unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timeout', requestId: '');
      stubCall(const Left(failure));

      final result = await dataSource.createInsight(
        sessionId: 's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );

      expect(result, const Left<Failure, String>(failure));
    });

    test('#6 a no-connection failure passes through unchanged', () async {
      const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
      stubCall(const Left(failure));

      final result = await dataSource.createInsight(
        sessionId: 's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );

      expect(result, const Left<Failure, String>(failure));
    });
  });
}
