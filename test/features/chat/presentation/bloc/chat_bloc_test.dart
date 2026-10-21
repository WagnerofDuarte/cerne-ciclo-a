import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockChatRepository extends Mock implements ChatRepository {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

ChatMessage _buildMessage({
  required String id,
  ChatRole role = ChatRole.assistant,
  ChatMessageStatus status = ChatMessageStatus.complete,
  int seq = 0,
  String content = 'hi',
  String sessionId = 's1',
}) => ChatMessage(
  id: id,
  sessionId: sessionId,
  role: role,
  content: content,
  seq: seq,
  status: status,
  retryCount: 0,
  createdAt: DateTime(2026, 1, 1),
);

ChatSession _buildSession({String id = 's1'}) => ChatSession(
  id: id,
  title: 'title',
  personaSnapshot: ChatPersona.analitico,
  userMessageCount: 1,
  lastUserMessageAt: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  late MockChatRepository chatRepository;
  late MockConnectivityChecker connectivityChecker;
  late StreamController<bool> connectivityController;

  setUp(() {
    chatRepository = MockChatRepository();
    connectivityChecker = MockConnectivityChecker();
    connectivityController = StreamController<bool>.broadcast();
    when(() => connectivityChecker.onConnectivityChanged)
        .thenAnswer((_) => connectivityController.stream);
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => chatRepository.setLastActiveSessionId(any())).thenAnswer((_) async {});
  });

  tearDown(() => connectivityController.close());

  ChatBloc buildBloc() => ChatBloc(
    chatRepository: chatRepository,
    connectivityChecker: connectivityChecker,
  );

  group('ChatStarted', () {
    blocTest<ChatBloc, ChatState>(
      '#1 no lastActiveSessionId -> ChatReady(sessionId: null, messages: []), '
      'no repository call beyond that one read',
      setUp: () {
        when(() => chatRepository.lastActiveSessionId).thenAnswer((_) async => null);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStarted()),
      expect: () => [
        const ChatReady(
          sessionId: null,
          messages: [],
          isOffline: false,
          awaitingResponse: false,
        ),
      ],
      verify: (_) {
        verifyNever(() => chatRepository.listMessages(any()));
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#2 a stored id whose listMessages succeeds -> ChatReady(sessionId, messages)',
      setUp: () {
        when(() => chatRepository.lastActiveSessionId).thenAnswer((_) async => 's1');
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => Right([_buildMessage(id: 'm1')]),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStarted()),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.sessionId, 'sessionId', 's1')
            .having((s) => s.messages.map((m) => m.id), 'message ids', ['m1'])
            .having((s) => s.loadFailure, 'loadFailure', isNull),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#3 a stored id whose listMessages fails and nothing is cached -> '
      'ChatReady(loadFailure: failure)',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
        when(() => chatRepository.lastActiveSessionId).thenAnswer((_) async => 's1');
        when(() => chatRepository.listMessages('s1')).thenAnswer((_) async => const Left(failure));
        when(() => chatRepository.cachedMessages('s1')).thenReturn(null);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStarted()),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.sessionId, 'sessionId', 's1')
            .having((s) => s.messages, 'messages', isEmpty)
            .having((s) => s.loadFailure, 'loadFailure', isNotNull),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#4 a stored id whose listMessages fails but a cache exists -> '
      'ChatReady(messages: cached), no loadFailure',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
        final cached = [_buildMessage(id: 'm1')];
        when(() => chatRepository.lastActiveSessionId).thenAnswer((_) async => 's1');
        when(() => chatRepository.listMessages('s1')).thenAnswer((_) async => const Left(failure));
        when(() => chatRepository.cachedMessages('s1')).thenReturn(cached);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStarted()),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.sessionId, 'sessionId', 's1')
            .having((s) => s.messages.map((m) => m.id), 'message ids', ['m1'])
            .having((s) => s.loadFailure, 'loadFailure', isNull),
      ],
    );
  });

  group('MessageSubmitted', () {
    blocTest<ChatBloc, ChatState>(
      '#5 on an empty conversation: optimistic pair appended within the same '
      'synchronous emit, then createSession, then sendMessage',
      setUp: () {
        when(() => chatRepository.createSession(title: any(named: 'title')))
            .thenAnswer((_) async => Right(_buildSession()));
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer((_) => const Stream.empty());
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: null,
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageSubmitted('olá')),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.messages, 'messages', hasLength(2))
            .having((s) => s.messages[0].role, 'first role', ChatRole.user)
            .having((s) => s.messages[0].content, 'first content', 'olá')
            .having((s) => s.messages[1].role, 'second role', ChatRole.assistant)
            .having((s) => s.messages[1].status, 'second status', ChatMessageStatus.streaming)
            .having((s) => s.awaitingResponse, 'awaitingResponse', true),
      ],
      verify: (_) {
        verify(() => chatRepository.createSession(title: 'olá')).called(1);
        verify(
          () => chatRepository.sendMessage(sessionId: 's1', content: 'olá'),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#6 while offline: composer already disabled (canSend == false) -> '
      'handler is a no-op, no repository call',
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: true,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageSubmitted('olá')),
      expect: () => <ChatState>[],
      verify: (_) {
        verifyNever(() => chatRepository.sendMessage(
              sessionId: any(named: 'sessionId'),
              content: any(named: 'content'),
            ));
        verifyNever(() => chatRepository.createSession(title: any(named: 'title')));
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#7 a full successful turn: content grows per token, StreamDone (no '
      'content of its own, per the backend wire contract) just flips status '
      'to complete, awaitingResponse false',
      setUp: () {
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            const Right(MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1')),
            const Right(ContextReceived()),
            const Right(TokenReceived('Ol')),
            const Right(TokenReceived('á!')),
            const Right(StreamDone(assistantMessageId: 'a1')),
          ]),
        );
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageSubmitted('oi')),
      expect: () => [
        isA<ChatReady>() // optimistic append
            .having((s) => s.messages[1].status, 'optimistic status', ChatMessageStatus.streaming)
            .having((s) => s.messages[1].content, 'optimistic content', ''),
        isA<ChatReady>() // MessageCreated reconciles ids
            .having((s) => s.messages[1].id, 'reconciled id', 'a1')
            .having((s) => s.messages[1].content, 'content still empty', ''),
        isA<ChatReady>().having((s) => s.messages[1].content, 'content after 1st token', 'Ol'),
        isA<ChatReady>().having((s) => s.messages[1].content, 'content after 2nd token', 'Olá!'),
        isA<ChatReady>()
            .having((s) => s.messages[1].content, 'final content (locally accumulated)', 'Olá!')
            .having((s) => s.messages[1].status, 'final status', ChatMessageStatus.complete)
            .having((s) => s.messages[1].id, 'final id', 'a1')
            .having((s) => s.awaitingResponse, 'awaitingResponse', false),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#8 a turn interrupted mid-stream by Left(failure) after 2 tokens '
      'keeps the accumulated content, status becomes failed, '
      'awaitingResponse becomes false',
      setUp: () {
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            const Right(MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1')),
            const Right(TokenReceived('Ol')),
            const Right(TokenReceived('á!')),
            const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
          ]),
        );
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageSubmitted('oi')),
      expect: () => [
        isA<ChatReady>() // optimistic append
            .having((s) => s.messages[1].status, 'optimistic status', ChatMessageStatus.streaming)
            .having((s) => s.messages[1].content, 'optimistic content', ''),
        isA<ChatReady>() // MessageCreated reconciles ids
            .having((s) => s.messages[1].id, 'reconciled id', 'a1'),
        isA<ChatReady>().having((s) => s.messages[1].content, 'content after 1st token', 'Ol'),
        isA<ChatReady>().having((s) => s.messages[1].content, 'content after 2nd token', 'Olá!'),
        isA<ChatReady>()
            .having((s) => s.messages[1].content, 'content preserved on failure', 'Olá!')
            .having((s) => s.messages[1].status, 'status', ChatMessageStatus.failed)
            .having((s) => s.awaitingResponse, 'awaitingResponse', false),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#8b a turn that fails before any token (e.g. a brand-new question '
      'whose backend generation errors out mid-retrieval) is reconciled '
      "against listMessages — if the backend had already persisted the "
      'full answer, it replaces the failed bubble instead of leaving it '
      'empty',
      setUp: () {
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
          ]),
        );
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => Right([
            _buildMessage(id: 'u1', role: ChatRole.user, seq: 0, content: 'oi'),
            _buildMessage(
              id: 'a1',
              role: ChatRole.assistant,
              seq: 1,
              content: 'resposta completa',
            ),
          ]),
        );
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageSubmitted('oi')),
      expect: () => [
        isA<ChatReady>() // optimistic append
            .having((s) => s.messages[1].status, 'optimistic status', ChatMessageStatus.streaming)
            .having((s) => s.messages[1].content, 'optimistic content', ''),
        isA<ChatReady>() // immediate failure, no tokens ever arrived
            .having((s) => s.messages[1].status, 'failed status', ChatMessageStatus.failed)
            .having((s) => s.messages[1].content, 'failed content', '')
            .having((s) => s.awaitingResponse, 'awaitingResponse', false),
        isA<ChatReady>() // reconciled from listMessages
            .having((s) => s.messages[1].id, 'reconciled id', 'a1')
            .having((s) => s.messages[1].content, 'reconciled content', 'resposta completa')
            .having((s) => s.messages[1].status, 'reconciled status', ChatMessageStatus.complete),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#8c the same empty-content failure, but listMessages has no matching '
      'completed answer yet (backend genuinely still failed) — stays failed, '
      'no phantom recovery',
      setUp: () {
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
          ]),
        );
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => Right([
            _buildMessage(id: 'u1', role: ChatRole.user, seq: 0, content: 'oi'),
          ]),
        );
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageSubmitted('oi')),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.messages[1].status, 'optimistic status', ChatMessageStatus.streaming),
        isA<ChatReady>()
            .having((s) => s.messages[1].status, 'stays failed', ChatMessageStatus.failed)
            .having((s) => s.messages[1].content, 'stays empty', ''),
      ],
      verify: (_) {
        verify(() => chatRepository.listMessages('s1')).called(1);
      },
    );
  });

  group('MessageRetryRequested', () {
    blocTest<ChatBloc, ChatState>(
      '#9 on a failed message not the most recent -> only that index is '
      'replaced, every later message untouched',
      setUp: () {
        when(
          () => chatRepository.retryMessage(
            sessionId: any(named: 'sessionId'),
            userMessageId: any(named: 'userMessageId'),
          ),
        ).thenAnswer((_) => const Stream.empty());
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [
          _buildMessage(id: 'u1', role: ChatRole.user, seq: 0),
          _buildMessage(id: 'a1', role: ChatRole.assistant, status: ChatMessageStatus.failed, seq: 1),
          _buildMessage(id: 'u2', role: ChatRole.user, seq: 2),
          _buildMessage(id: 'a2', role: ChatRole.assistant, seq: 3),
        ],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageRetryRequested('u1')),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.messages[0].id, 'message 0 unchanged', 'u1')
            .having((s) => s.messages[1].status, 'message 1 now streaming', ChatMessageStatus.streaming)
            .having((s) => s.messages[2].id, 'message 2 unchanged', 'u2')
            .having((s) => s.messages[3].id, 'message 3 unchanged', 'a2'),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#10 two dispatches back-to-back for the same message -> the second is '
      'a no-op (awaitingResponse already true)',
      setUp: () {
        when(
          () => chatRepository.retryMessage(
            sessionId: any(named: 'sessionId'),
            userMessageId: any(named: 'userMessageId'),
          ),
        ).thenAnswer((_) => const Stream.empty());
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [
          _buildMessage(id: 'u1', role: ChatRole.user, seq: 0),
          _buildMessage(id: 'a1', role: ChatRole.assistant, status: ChatMessageStatus.failed, seq: 1),
        ],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) {
        bloc.add(const MessageRetryRequested('u1'));
        bloc.add(const MessageRetryRequested('u1'));
      },
      verify: (_) {
        verify(
          () => chatRepository.retryMessage(
            sessionId: any(named: 'sessionId'),
            userMessageId: any(named: 'userMessageId'),
          ),
        ).called(1);
      },
    );
  });

  group('MessageRetryRequested on a failed lazy session creation', () {
    blocTest<ChatBloc, ChatState>(
      '#14 retrying a turn whose createSession itself failed (sessionId '
      'still null, preceding user message still optimistic) re-runs '
      'createSession then sendMessage instead of retryMessage',
      setUp: () {
        when(() => chatRepository.createSession(title: any(named: 'title')))
            .thenAnswer((_) async => Right(_buildSession()));
        when(() => chatRepository.setLastActiveSessionId(any())).thenAnswer((_) async {});
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            const Right(MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1')),
            const Right(TokenReceived('resposta')),
            const Right(StreamDone(assistantMessageId: 'a1')),
          ]),
        );
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: null,
        messages: [
          ChatMessage(
            id: 'local-1',
            sessionId: '',
            role: ChatRole.user,
            content: 'oi',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
          ChatMessage(
            id: 'local-1-response',
            sessionId: '',
            role: ChatRole.assistant,
            content: '',
            seq: 1,
            status: ChatMessageStatus.failed,
            retryCount: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageRetryRequested('local-1')),
      expect: () => [
        isA<ChatReady>() // streaming placeholder replaces the failed message
            .having((s) => s.messages[1].status, 'placeholder status', ChatMessageStatus.streaming)
            .having((s) => s.awaitingResponse, 'awaitingResponse', true),
        isA<ChatReady>() // sessionId now set, placeholder still id-unreconciled
            .having((s) => s.sessionId, 'sessionId', 's1'),
        isA<ChatReady>() // MessageCreated reconciles both ids
            .having((s) => s.messages[0].id, 'user id reconciled', 'u1')
            .having((s) => s.messages[1].id, 'assistant id reconciled', 'a1'),
        isA<ChatReady>() // token appended
            .having((s) => s.messages[1].content, 'content after token', 'resposta'),
        isA<ChatReady>()
            .having((s) => s.messages[1].content, 'final content (locally accumulated)', 'resposta')
            .having((s) => s.messages[1].status, 'final status', ChatMessageStatus.complete)
            .having((s) => s.awaitingResponse, 'awaitingResponse', false),
      ],
      verify: (_) {
        verify(() => chatRepository.createSession(title: 'oi')).called(1);
        verify(() => chatRepository.sendMessage(sessionId: 's1', content: 'oi')).called(1);
        verifyNever(
          () => chatRepository.retryMessage(
            sessionId: any(named: 'sessionId'),
            userMessageId: any(named: 'userMessageId'),
          ),
        );
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#15 when the retried createSession call fails again, the message '
      'returns to failed with no sendMessage attempted',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
        when(() => chatRepository.createSession(title: any(named: 'title')))
            .thenAnswer((_) async => const Left(failure));
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: null,
        messages: [
          ChatMessage(
            id: 'local-1',
            sessionId: '',
            role: ChatRole.user,
            content: 'oi',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
          ChatMessage(
            id: 'local-1-response',
            sessionId: '',
            role: ChatRole.assistant,
            content: '',
            seq: 1,
            status: ChatMessageStatus.failed,
            retryCount: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const MessageRetryRequested('local-1')),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.messages[1].status, 'placeholder status', ChatMessageStatus.streaming),
        isA<ChatReady>()
            .having((s) => s.messages[1].status, 'final status', ChatMessageStatus.failed)
            .having((s) => s.sessionId, 'sessionId stays null', isNull)
            .having((s) => s.awaitingResponse, 'awaitingResponse', false),
      ],
      verify: (_) {
        verifyNever(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        );
      },
    );
  });

  group('NewConversationRequested', () {
    blocTest<ChatBloc, ChatState>(
      '#11 while a previous conversation has in-memory messages -> only '
      'lastActiveSessionId changes, no cache-clearing repository call',
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1')],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const NewConversationRequested()),
      expect: () => [
        const ChatReady(
          sessionId: null,
          messages: [],
          isOffline: false,
          awaitingResponse: false,
        ),
      ],
      verify: (_) {
        verify(() => chatRepository.setLastActiveSessionId(null)).called(1);
      },
    );
  });

  group('ChatConnectivityChanged', () {
    blocTest<ChatBloc, ChatState>(
      '#12 isOffline flips immediately on a connectivity change event',
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const ChatConnectivityChanged(false)),
      expect: () => [
        isA<ChatReady>().having((s) => s.isOffline, 'isOffline', true),
      ],
    );
  });

  group('ConversationSelected mid-stream abandonment', () {
    late StreamController<Either<Failure, ChatStreamEvent>> turnController;

    blocTest<ChatBloc, ChatState>(
      '#13 switching conversations mid-stream ignores the abandoned turn\'s '
      'later stream items',
      setUp: () {
        turnController = StreamController<Either<Failure, ChatStreamEvent>>();
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer((_) => turnController.stream);
        when(() => chatRepository.listMessages('s2')).thenAnswer(
          (_) async => Right([_buildMessage(id: 'm2', sessionId: 's2')]),
        );
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const MessageSubmitted('oi'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const ConversationSelected('s2'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // The abandoned turn's stream is still open — a late item arriving
        // now must be ignored (generation mismatch), never mutating the
        // newly-loaded conversation's state.
        turnController.add(const Right(TokenReceived('late')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await turnController.close();
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<ChatReady>());
        expect((state as ChatReady).sessionId, 's2');
        expect(state.messages.map((m) => m.id), ['m2']);
      },
    );
  });
}
