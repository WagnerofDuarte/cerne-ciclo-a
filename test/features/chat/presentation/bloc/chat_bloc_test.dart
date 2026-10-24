import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_status.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/entities/insight_trigger.dart';
import 'package:cerne/features/chat/domain/entities/proactive_insight.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockChatRepository extends Mock implements ChatRepository {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

class MockCreateEntryUseCase extends Mock implements CreateEntryUseCase {}

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

Entry _buildEntry({String id = 'entry-1'}) => Entry(
  id: id,
  content: 'hi',
  source: EntrySource.chat,
  chatMessageId: 'm1',
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
  late MockChatRepository chatRepository;
  late MockConnectivityChecker connectivityChecker;
  late MockCreateEntryUseCase createEntryUseCase;
  late StreamController<bool> connectivityController;
  late StreamController<Either<Failure, ChatStreamEvent>> fifthTurnControllerRef;
  late Completer<Either<Failure, String>> inFlightCompleterRef;

  setUpAll(() {
    registerFallbackValue(EntrySource.chat);
    registerFallbackValue(InsightTriggerType.messageCount);
  });

  setUp(() {
    chatRepository = MockChatRepository();
    connectivityChecker = MockConnectivityChecker();
    createEntryUseCase = MockCreateEntryUseCase();
    connectivityController = StreamController<bool>.broadcast();
    when(() => connectivityChecker.onConnectivityChanged)
        .thenAnswer((_) => connectivityController.stream);
    when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
    when(() => chatRepository.setLastActiveSessionId(any())).thenAnswer((_) async {});
    when(() => chatRepository.savedEntryIdFor(any())).thenReturn(null);
    when(
      () => chatRepository.recordMessageSaved(
        chatMessageId: any(named: 'chatMessageId'),
        entryId: any(named: 'entryId'),
      ),
    ).thenAnswer((_) async {});
    // Default: no card, no indicator (FR-006) — individual tests override
    // this when they need success/offline/auth-expired behavior.
    when(
      () => chatRepository.createInsight(
        sessionId: any(named: 'sessionId'),
        triggerType: any(named: 'triggerType'),
        triggerKey: any(named: 'triggerKey'),
      ),
    ).thenAnswer(
      (_) async =>
          const Left(AiGenerationTimeoutFailure(message: 'timeout', requestId: '')),
    );
  });

  tearDown(() => connectivityController.close());

  ChatBloc buildBloc({Duration? insightInactivityTimeout}) => ChatBloc(
    chatRepository: chatRepository,
    connectivityChecker: connectivityChecker,
    createEntryUseCase: createEntryUseCase,
    insightInactivityTimeout: insightInactivityTimeout ?? const Duration(minutes: 2),
  );

  // A turn that completes immediately with no tokens — sufficient for every
  // insight-mechanism scenario below, which only cares about
  // awaitingResponse flipping back to false, never about message content.
  void stubImmediateTurn() {
    when(
      () => chatRepository.sendMessage(
        sessionId: any(named: 'sessionId'),
        content: any(named: 'content'),
      ),
    ).thenAnswer(
      (_) => Stream.fromIterable([const Right(StreamDone(assistantMessageId: 'ignored'))]),
    );
  }

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
        isA<ChatReady>() // the lazily-created session id is written back
            .having((s) => s.sessionId, 'sessionId', 's1'),
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

  group('_seedBookmarks (via ChatStarted/_loadSession)', () {
    blocTest<ChatBloc, ChatState>(
      '#1 a mix of messages, one saved user message, seeds bookmarks to '
      'exactly {that id: saved} — other messages report idle',
      setUp: () {
        when(() => chatRepository.lastActiveSessionId).thenAnswer((_) async => 's1');
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => Right([
            _buildMessage(id: 'm1', role: ChatRole.assistant),
            _buildMessage(id: 'm2', role: ChatRole.user),
            _buildMessage(id: 'm3', role: ChatRole.user),
          ]),
        );
        when(() => chatRepository.savedEntryIdFor('m2')).thenReturn('entry-1');
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStarted()),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.bookmarks, 'bookmarks', {'m2': BookmarkStatus.saved})
            .having((s) => s.bookmarkStatusFor('m1'), 'm1 status', BookmarkStatus.idle)
            .having((s) => s.bookmarkStatusFor('m3'), 'm3 status', BookmarkStatus.idle),
      ],
    );
  });

  group('BookmarkTapped', () {
    blocTest<ChatBloc, ChatState>(
      '#2 idle user message: saving -> saved, createEntryUseCase called once '
      'with chatMessageId/occurredAt, recordMessageSaved called once',
      setUp: () {
        final entry = _buildEntry();
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer((_) async => Right(entry));
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user, content: 'hi')],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const BookmarkTapped('m1')),
      expect: () => [
        isA<ChatReady>().having(
          (s) => s.bookmarkStatusFor('m1'),
          'status after tap',
          BookmarkStatus.saving,
        ),
        isA<ChatReady>().having(
          (s) => s.bookmarkStatusFor('m1'),
          'status after success',
          BookmarkStatus.saved,
        ),
      ],
      verify: (_) {
        verify(
          () => createEntryUseCase(
            'hi',
            EntrySource.chat,
            chatMessageId: 'm1',
            occurredAt: DateTime(2026, 1, 1),
          ),
        ).called(1);
        verify(
          () => chatRepository.recordMessageSaved(chatMessageId: 'm1', entryId: 'entry-1'),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#3 NetworkOfflineFailure -> saving -> error; recordMessageSaved never '
      'called',
      setUp: () {
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer(
          (_) async =>
              const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
        );
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const BookmarkTapped('m1')),
      expect: () => [
        isA<ChatReady>().having(
          (s) => s.bookmarkStatusFor('m1'),
          'saving',
          BookmarkStatus.saving,
        ),
        isA<ChatReady>().having((s) => s.bookmarkStatusFor('m1'), 'error', BookmarkStatus.error),
      ],
      verify: (_) {
        verifyNever(
          () => chatRepository.recordMessageSaved(
            chatMessageId: any(named: 'chatMessageId'),
            entryId: any(named: 'entryId'),
          ),
        );
      },
    );

    test(
      '#4 AuthExpiredFailure -> error; reauthRequired emits exactly one event',
      () async {
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer(
          (_) async =>
              const Left(AuthExpiredFailure(message: 'expired', requestId: '')),
        );
        final bloc = buildBloc();
        var reauthCount = 0;
        final subscription = bloc.reauthRequired.listen((_) => reauthCount++);
        bloc.emit(
          ChatReady(
            sessionId: 's1',
            messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
            isOffline: false,
            awaitingResponse: false,
          ),
        );

        bloc.add(const BookmarkTapped('m1'));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(reauthCount, 1);
        expect((bloc.state as ChatReady).bookmarkStatusFor('m1'), BookmarkStatus.error);
        await subscription.cancel();
        await bloc.close();
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#5 two dispatches back-to-back before the first resolves -> '
      'createEntryUseCase called exactly once',
      setUp: () {
        final completer = Completer<Either<Failure, Entry>>();
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer((_) => completer.future);
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) {
        bloc.add(const BookmarkTapped('m1'));
        bloc.add(const BookmarkTapped('m1'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verify(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#6 already-saved bookmark -> no-op, createEntryUseCase never called',
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
        bookmarks: const {'m1': BookmarkStatus.saved},
      ),
      act: (bloc) => bloc.add(const BookmarkTapped('m1')),
      expect: () => <ChatState>[],
      verify: (_) {
        verifyNever(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        );
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#7 tapping an optimistic (local-...) user message -> no-op, '
      'createEntryUseCase never called (research.md R6)',
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [
          ChatMessage(
            id: 'local-1',
            sessionId: 's1',
            role: ChatRole.user,
            content: 'oi',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const BookmarkTapped('local-1')),
      expect: () => <ChatState>[],
      verify: (_) {
        verifyNever(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        );
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#8 tapping an assistant message id (defensive, UI never dispatches '
      'this) -> no-op',
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'a1', role: ChatRole.assistant)],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const BookmarkTapped('a1')),
      expect: () => <ChatState>[],
      verify: (_) {
        verifyNever(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        );
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#9 a save in flight, superseded by ConversationSelected before it '
      "resolves -> the new session's own ChatReady is unaffected; "
      'recordMessageSaved is still called once',
      setUp: () {
        final entry = _buildEntry();
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 20), () => Right(entry)),
        );
        when(() => chatRepository.listMessages('other-session')).thenAnswer(
          (_) async => Right([_buildMessage(id: 'm2', sessionId: 'other-session')]),
        );
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const BookmarkTapped('m1'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ConversationSelected('other-session'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<ChatReady>());
        expect((state as ChatReady).sessionId, 'other-session');
        expect(state.messages.map((m) => m.id), ['m2']);
        verify(
          () => chatRepository.recordMessageSaved(chatMessageId: 'm1', entryId: 'entry-1'),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#10 a full round trip, immediately followed by re-selecting the same '
      'session (navigate-away-and-back) -> the reloaded bookmarks reflect '
      "recordMessageSaved's persisted write",
      setUp: () {
        final entry = _buildEntry();
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer((_) async => Right(entry));
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => Right([_buildMessage(id: 'm1', role: ChatRole.user)]),
        );
      },
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const BookmarkTapped('m1'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        when(() => chatRepository.savedEntryIdFor('m1')).thenReturn('entry-1');
        bloc.add(const ConversationSelected('s1'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<ChatReady>());
        expect((state as ChatReady).bookmarkStatusFor('m1'), BookmarkStatus.saved);
      },
    );
  });

  group('BookmarkTapped never affects the rest of the screen (FR-006)', () {
    blocTest<ChatBloc, ChatState>(
      '#11 a bookmark save in flight never touches awaitingResponse/messages '
      '— a concurrent MessageSubmitted proceeds exactly as it would with no '
      'bookmark activity at all',
      setUp: () {
        final completer = Completer<Either<Failure, Entry>>();
        when(
          () => createEntryUseCase(
            any(),
            any(),
            chatMessageId: any(named: 'chatMessageId'),
            occurredAt: any(named: 'occurredAt'),
          ),
        ).thenAnswer((_) => completer.future);
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
      seed: () => ChatReady(
        sessionId: null,
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const BookmarkTapped('m1'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const MessageSubmitted('olá'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<ChatReady>());
        expect((state as ChatReady).awaitingResponse, isTrue);
        expect(state.messages, hasLength(3));
        expect(state.bookmarkStatusFor('m1'), BookmarkStatus.saving);
      },
    );
  });

  group('Insight mechanism — US1 message-count trigger', () {
    blocTest<ChatBloc, ChatState>(
      '#1 5 messages each resolving normally -> createInsight called exactly '
      'once with triggerType: messageCount, triggerKey: "message_count:5", '
      'only after the 5th turn completes; emitted state carries insight != null',
      setUp: () {
        stubImmediateTurn();
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => const Right('texto gerado'));
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      verify: (bloc) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:5',
          ),
        ).called(1);
        expect((bloc.state as ChatReady).insight, isNotNull);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#2 continuing from #1: dismiss then send 5 more -> a 2nd call with '
      'triggerKey: "message_count:10"',
      setUp: () {
        stubImmediateTurn();
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => const Right('texto gerado'));
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        bloc.add(const InsightDismissed());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('n$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:5',
          ),
        ).called(1);
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:10',
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#3 a message-count crossing landing on a message whose turn is still '
      'streaming defers the call until the turn resolves',
      setUp: () {
        var callIndex = 0;
        final fifthTurnController =
            StreamController<Either<Failure, ChatStreamEvent>>();
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer((_) {
          callIndex++;
          if (callIndex == 5) return fifthTurnController.stream;
          return Stream.fromIterable([
            const Right(StreamDone(assistantMessageId: 'ignored')),
          ]);
        });
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => const Right('texto gerado'));
        fifthTurnControllerRef = fifthTurnController;
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 4; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        bloc.add(const MessageSubmitted('m4')); // the 5th message — crosses to 5
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // Turn still streaming — the call must not have fired yet.
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        );
        fifthTurnControllerRef.add(const Right(StreamDone(assistantMessageId: 'ignored')));
        await fifthTurnControllerRef.close();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:5',
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#16 sending 4 messages, letting the 5th fail outright and retrying '
      'it, does not double-count the retry — the crossing still fires '
      'exactly once, at the correct message',
      setUp: () {
        var callIndex = 0;
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer((_) {
          callIndex++;
          if (callIndex == 5) {
            // Reconciles ids first (so the retry below takes the normal
            // `retryMessage` path, not the lazy-session-creation path a
            // still-optimistic user message would trigger) before failing.
            return Stream.fromIterable([
              const Right(MessageCreated(userMessageId: 'u5', assistantMessageId: 'a5')),
              const Left(NetworkOfflineFailure(message: 'offline', requestId: '')),
            ]);
          }
          return Stream.fromIterable([
            const Right(StreamDone(assistantMessageId: 'ignored')),
          ]);
        });
        when(
          () => chatRepository.retryMessage(
            sessionId: any(named: 'sessionId'),
            userMessageId: any(named: 'userMessageId'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            const Right(StreamDone(assistantMessageId: 'ignored')),
          ]),
        );
        // The failed 5th turn has empty content, so `_reconcileSilentFailure`
        // re-fetches — irrelevant to this test, just needs a valid response.
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => const Right([]),
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
        for (var i = 0; i < 4; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        bloc.add(const MessageSubmitted('m4')); // 5th -> count=5, this turn fails
        await Future<void>.delayed(const Duration(milliseconds: 5));

        final failedState = bloc.state as ChatReady;
        final failedIndex = failedState.messages.indexWhere(
          (m) => m.status == ChatMessageStatus.failed,
        );
        final userMessageId = failedState.messages[failedIndex - 1].id;
        bloc.add(MessageRetryRequested(userMessageId));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        // 4 more messages: if the retry had double-counted, this would
        // already reach the 10th-message crossing.
        for (var i = 0; i < 4; i++) {
          bloc.add(MessageSubmitted('n$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:5',
          ),
        ).called(1);
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:10',
          ),
        );

        bloc.add(const MessageSubmitted('n4')); // the true 10th message
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:10',
          ),
        ).called(1);
      },
    );
  });

  group('Insight mechanism — US2 inactivity trigger', () {
    blocTest<ChatBloc, ChatState>(
      '#4 the inactivity timer fires once with triggerType: inactivity after '
      'the configured timeout',
      setUp: () {
        // A successful resolution renders a card, which suspends the
        // mechanism — the only way to assert "exactly one call" without
        // racing against this test's own re-arm-on-failure behavior
        // (verified separately by #10/#11).
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => const Right('texto gerado'));
      },
      build: () => buildBloc(insightInactivityTimeout: const Duration(milliseconds: 10)),
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) => bloc.add(const ChatForegroundChanged(true)),
      wait: const Duration(milliseconds: 40),
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.inactivity,
            triggerKey: any(named: 'triggerKey'),
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#5 sending a message before the timeout elapses means the original '
      'timer never fires; a new one starts from the send instant',
      setUp: stubImmediateTurn,
      build: () => buildBloc(insightInactivityTimeout: const Duration(milliseconds: 40)),
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const ChatForegroundChanged(true)); // arms the first timer at t=0
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const MessageSubmitted('oi')); // resets to a fresh 40ms from t=20
        await Future<void>.delayed(const Duration(milliseconds: 25));
        // t=45 total: the original timer (due at t=40) would have fired by
        // now if it hadn't been reset; the reset one is due at t=60.
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.inactivity,
            triggerKey: any(named: 'triggerKey'),
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#6 ChatForegroundChanged(false) before the timeout elapses means the '
      'timer never fires while backgrounded',
      build: () => buildBloc(insightInactivityTimeout: const Duration(milliseconds: 20)),
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const ChatForegroundChanged(true));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ChatForegroundChanged(false));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      },
      verify: (_) {
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        );
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#7 ChatForegroundChanged(false) after 90% of the configured duration, '
      'then ChatForegroundChanged(true), starts a brand-new full-length '
      'timer — it does not fire after only the remaining 10%',
      build: () => buildBloc(insightInactivityTimeout: const Duration(milliseconds: 100)),
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(const ChatForegroundChanged(true)); // arm at t=0 (due t=100)
        await Future<void>.delayed(const Duration(milliseconds: 90));
        bloc.add(const ChatForegroundChanged(false)); // pause at t=90
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ChatForegroundChanged(true)); // resume at t=95 (new timer due t=195)
        await Future<void>.delayed(const Duration(milliseconds: 20)); // t=115 — only 20ms since resume
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100)); // past t=195
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.inactivity,
            triggerKey: any(named: 'triggerKey'),
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#15 on a fresh "Novo Chat" (sessionId == null), the timer firing '
      'never calls createInsight and stays disarmed until the first message '
      'is sent',
      setUp: stubImmediateTurn,
      build: () => buildBloc(insightInactivityTimeout: const Duration(milliseconds: 10)),
      seed: () => const ChatReady(
        sessionId: null,
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        bloc.add(InsightInactivityTimerFired(DateTime(2026, 1, 1)));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
      verify: (_) {
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        );
      },
    );
  });

  group('Insight mechanism — US3 failure/offline invisibility', () {
    blocTest<ChatBloc, ChatState>(
      '#8 a trigger that resolves to a visible card suspends the mechanism '
      '— no further createInsight call fires even after another 5 messages '
      'or another timeout, until InsightDismissed',
      setUp: () {
        stubImmediateTurn();
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => const Right('texto gerado'));
      },
      build: () => buildBloc(insightInactivityTimeout: const Duration(milliseconds: 10)),
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('n$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        bloc.add(InsightInactivityTimerFired(DateTime(2026, 1, 1)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#9 a second, independently-satisfied trigger condition while a '
      'createInsight call is still pending produces no 2nd call',
      setUp: () {
        stubImmediateTurn();
        final completer = Completer<Either<Failure, String>>();
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) => completer.future);
        inFlightCompleterRef = completer;
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        // The first attempt is now in flight (completer unresolved).
        bloc.add(InsightInactivityTimerFired(DateTime(2026, 1, 1)));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlightCompleterRef.complete(const Right('texto gerado'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
      verify: (_) {
        verify(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#10 createInsight resolving Left(AiGenerationTimeoutFailure) leaves '
      'insight at/returning to null, and the next crossing fires normally '
      'afterward',
      setUp: () {
        stubImmediateTurn();
        var callIndex = 0;
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async {
          callIndex++;
          return callIndex == 1
              ? const Left(AiGenerationTimeoutFailure(message: 'x', requestId: ''))
              : const Right('texto gerado');
        });
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect((bloc.state as ChatReady).insight, isNull);
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('n$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      verify: (bloc) {
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:5',
          ),
        ).called(1);
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:10',
          ),
        ).called(1);
        expect((bloc.state as ChatReady).insight, isNotNull);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#11 ConnectivityChecker.hasConnection() returning false when a '
      'trigger fires means createInsight is never called; the occurrence '
      'resolves exactly like a failure',
      setUp: () {
        stubImmediateTurn();
        var callCount = 0;
        when(() => connectivityChecker.hasConnection()).thenAnswer((_) async {
          callCount++;
          // The first 5 calls are _onMessageSubmitted's own FR-012 pre-check
          // (true, so the messages send); the 6th is the insight attempt's
          // own pre-check (false).
          return callCount <= 5;
        });
      },
      build: buildBloc,
      seed: () => const ChatReady(
        sessionId: 's1',
        messages: [],
        isOffline: false,
        awaitingResponse: false,
      ),
      act: (bloc) async {
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      verify: (bloc) {
        verifyNever(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        );
        expect((bloc.state as ChatReady).insight, isNull);
      },
    );

    blocTest<ChatBloc, ChatState>(
      '#13 a trigger firing (attempt in flight) on session A followed by '
      'ConversationSelected(B) before it resolves means the stale call\'s '
      'eventual resolution causes no state mutation; session B\'s own '
      'counters start at 0',
      setUp: () {
        stubImmediateTurn();
        final completer = Completer<Either<Failure, String>>();
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) => completer.future);
        inFlightCompleterRef = completer;
        when(() => chatRepository.listMessages('session-b')).thenAnswer(
          (_) async => const Right([]),
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
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        bloc.add(const ConversationSelected('session-b'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlightCompleterRef.complete(const Right('texto gerado'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
      verify: (bloc) {
        final state = bloc.state as ChatReady;
        expect(state.sessionId, 'session-b');
        expect(state.insight, isNull);
      },
    );

    test(
      '#14 createInsight resolving Left(AuthExpiredFailure) emits '
      'reauthRequired but insight stays null',
      () async {
        final chatRepository = MockChatRepository();
        final connectivityChecker = MockConnectivityChecker();
        final createEntryUseCase = MockCreateEntryUseCase();
        final connectivityController = StreamController<bool>.broadcast();
        when(() => connectivityChecker.onConnectivityChanged)
            .thenAnswer((_) => connectivityController.stream);
        when(() => connectivityChecker.hasConnection()).thenAnswer((_) async => true);
        when(() => chatRepository.setLastActiveSessionId(any())).thenAnswer((_) async {});
        when(
          () => chatRepository.sendMessage(
            sessionId: any(named: 'sessionId'),
            content: any(named: 'content'),
          ),
        ).thenAnswer(
          (_) => Stream.fromIterable([const Right(StreamDone(assistantMessageId: 'ignored'))]),
        );
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer(
          (_) async =>
              const Left(AuthExpiredFailure(message: 'expired', requestId: '')),
        );

        final bloc = ChatBloc(
          chatRepository: chatRepository,
          connectivityChecker: connectivityChecker,
          createEntryUseCase: createEntryUseCase,
        );
        var reauthCount = 0;
        final subscription = bloc.reauthRequired.listen((_) => reauthCount++);
        bloc.emit(
          const ChatReady(
            sessionId: 's1',
            messages: [],
            isOffline: false,
            awaitingResponse: false,
          ),
        );

        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(reauthCount, 1);
        expect((bloc.state as ChatReady).insight, isNull);
        await subscription.cancel();
        await bloc.close();
        await connectivityController.close();
      },
    );
  });

  group('Insight mechanism — US4 dismiss isolation', () {
    blocTest<ChatBloc, ChatState>(
      '#12 with a card visible and other messages present, InsightDismissed '
      'emits a state with insight: null and an otherwise byte-identical '
      'messages/sessionId/isOffline/awaitingResponse/bookmarks',
      build: buildBloc,
      seed: () => ChatReady(
        sessionId: 's1',
        messages: [_buildMessage(id: 'm1', role: ChatRole.user)],
        isOffline: false,
        awaitingResponse: false,
        bookmarks: const {'m1': BookmarkStatus.saved},
        insight: const ProactiveInsight(content: 'texto gerado', anchorIndex: 1),
      ),
      act: (bloc) => bloc.add(const InsightDismissed()),
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.insight, 'insight', isNull)
            .having((s) => s.messages.map((m) => m.id), 'messages', ['m1'])
            .having((s) => s.sessionId, 'sessionId', 's1')
            .having((s) => s.isOffline, 'isOffline', false)
            .having((s) => s.awaitingResponse, 'awaitingResponse', false)
            .having((s) => s.bookmarks, 'bookmarks', {'m1': BookmarkStatus.saved}),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      '#39 a dismissed/still-visible card never reappears after '
      'ConversationSelected re-emits ChatReady, and the message-count '
      'counter has restarted at zero',
      setUp: () {
        stubImmediateTurn();
        when(
          () => chatRepository.createInsight(
            sessionId: any(named: 'sessionId'),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => const Right('texto gerado'));
        when(() => chatRepository.listMessages('s1')).thenAnswer(
          (_) async => const Right([]),
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
        for (var i = 0; i < 5; i++) {
          bloc.add(MessageSubmitted('m$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect((bloc.state as ChatReady).insight, isNotNull);

        bloc.add(const ConversationSelected('s1'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect((bloc.state as ChatReady).insight, isNull);

        for (var i = 0; i < 4; i++) {
          bloc.add(MessageSubmitted('n$i'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      verify: (bloc) {
        expect((bloc.state as ChatReady).insight, isNull);
        verify(
          () => chatRepository.createInsight(
            sessionId: 's1',
            triggerType: InsightTriggerType.messageCount,
            triggerKey: 'message_count:5',
          ),
        ).called(1);
      },
    );
  });
}
