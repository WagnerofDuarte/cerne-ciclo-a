import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/chat/data/chat_local_cache.dart';
import 'package:cerne/features/chat/data/chat_remote_data_source.dart';
import 'package:cerne/features/chat/data/chat_repository_impl.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_sessions_page.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockChatRemoteDataSource extends Mock implements ChatRemoteDataSource {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockChatLocalCache extends Mock implements ChatLocalCache {}

ChatSession _buildSession({String id = 's1'}) => ChatSession(
  id: id,
  title: 'title',
  personaSnapshot: ChatPersona.analitico,
  userMessageCount: 1,
  lastUserMessageAt: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

ChatMessage _buildMessage({String id = 'm1'}) => ChatMessage(
  id: id,
  sessionId: 's1',
  role: ChatRole.user,
  content: 'hi',
  seq: 0,
  status: ChatMessageStatus.complete,
  retryCount: 0,
  createdAt: DateTime(2026, 1, 1),
);

Session _buildAuthSession() => const Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresAt: 0,
  tokenType: 'bearer',
  account: Account(id: 'acc-1', email: 'test@example.com'),
);

const _authExpired = AuthExpiredFailure(message: 'expired', requestId: '');

void main() {
  late MockChatRemoteDataSource remoteDataSource;
  late MockSessionRepository sessionRepository;
  late MockChatLocalCache localCache;
  late ChatRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(<ChatSession>[]);
  });

  setUp(() {
    remoteDataSource = MockChatRemoteDataSource();
    sessionRepository = MockSessionRepository();
    localCache = MockChatLocalCache();
    when(() => localCache.readSessions()).thenAnswer((_) async => const []);
    when(() => localCache.readAllMessages()).thenAnswer((_) async => const {});
    when(() => localCache.readSavedMessageEntryIds()).thenAnswer((_) async => const {});
    when(() => localCache.writeSessions(any())).thenAnswer((_) async {});
    when(
      () => localCache.writeMessagesForSession(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => localCache.writeSavedMessageEntryIds(any()),
    ).thenAnswer((_) async {});
    repository = ChatRepositoryImpl(
      remoteDataSource,
      sessionRepository: sessionRepository,
      localCache: localCache,
    );
  });

  test(
    '#1 createSession upserts the parsed session into cachedSessions',
    () async {
      final session = _buildSession();
      when(
        () => remoteDataSource.createSession(title: any(named: 'title')),
      ).thenAnswer((_) async => Right(session));

      final result = await repository.createSession(title: 'Ansiedade');

      expect(result, Right<Failure, ChatSession>(session));
      expect(repository.cachedSessions, [session]);
    },
  );

  test(
    '#1b cachedSessions stays ordered by lastUserMessageAt descending after a '
    'newer session is created (FR-008) — not merely appended to the end',
    () async {
      final older = ChatSession(
        id: 's-old',
        title: 'older',
        personaSnapshot: ChatPersona.analitico,
        userMessageCount: 1,
        lastUserMessageAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final newer = ChatSession(
        id: 's-new',
        title: 'newer',
        personaSnapshot: ChatPersona.analitico,
        userMessageCount: 1,
        lastUserMessageAt: DateTime(2026, 1, 2),
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      );
      when(() => localCache.readSessions()).thenAnswer((_) async => [older]);
      when(
        () => remoteDataSource.createSession(title: any(named: 'title')),
      ).thenAnswer((_) async => Right(newer));

      // `createSession` lazily loads `older` from the local cache first (as
      // a real app restart would), then upserts `newer` — the most recently
      // active session must sort to the front even though it was upserted
      // last.
      await repository.createSession(title: 'Nova conversa');

      expect(repository.cachedSessions.map((s) => s.id), ['s-new', 's-old']);
    },
  );

  test(
    '#2 listSessions: AuthExpiredFailure on first call, success on retry -> '
    'exactly one refresh, one more listSessions call, final Right',
    () async {
      final page = ChatSessionsPage(sessions: [_buildSession()], nextCursor: null);
      var callCount = 0;
      when(
        () => remoteDataSource.listSessions(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? const Left(_authExpired) : Right(page);
      });
      when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildAuthSession()));

      final result = await repository.listSessions();

      expect(result, Right<Failure, ChatSessionsPage>(page));
      verify(() => sessionRepository.refresh()).called(1);
      verify(
        () => remoteDataSource.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
      ).called(2);
    },
  );

  test(
    '#3 listMessages succeeds -> cachedMessages returns that exact list, '
    'writeMessagesForSession called once',
    () async {
      final messages = [_buildMessage()];
      when(() => remoteDataSource.listMessages('s1')).thenAnswer((_) async => Right(messages));

      final result = await repository.listMessages('s1');

      expect(result, Right<Failure, List<ChatMessage>>(messages));
      expect(repository.cachedMessages('s1'), messages);
      verify(() => localCache.writeMessagesForSession('s1', messages)).called(1);
    },
  );

  test('#4 cachedMessages("never-opened") returns null', () {
    expect(repository.cachedMessages('never-opened'), isNull);
  });

  test(
    '#5 sendMessage stream: first item Left(AuthExpiredFailure), refresh '
    'succeeds, re-called stream succeeds -> exactly one refresh call, caller '
    'sees only the retry\'s items',
    () async {
      var callCount = 0;
      when(
        () => remoteDataSource.sendMessage(
          sessionId: any(named: 'sessionId'),
          content: any(named: 'content'),
        ),
      ).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.value(const Left(_authExpired));
        }
        return Stream.value(
          const Right(MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1')),
        );
      });
      when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildAuthSession()));

      final results = await repository
          .sendMessage(sessionId: 's1', content: 'hi')
          .toList();

      expect(results, [
        const Right<Failure, ChatStreamEvent>(
          MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1'),
        ),
      ]);
      verify(() => sessionRepository.refresh()).called(1);
    },
  );

  test(
    '#6 sendMessage stream: Right(MessageCreated) already emitted, then '
    'Left(AuthExpiredFailure) -> yielded as-is, no retry attempted',
    () async {
      when(
        () => remoteDataSource.sendMessage(
          sessionId: any(named: 'sessionId'),
          content: any(named: 'content'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          const Right(MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1')),
          const Left(_authExpired),
        ]),
      );

      final results = await repository
          .sendMessage(sessionId: 's1', content: 'hi')
          .toList();

      expect(results, [
        const Right<Failure, ChatStreamEvent>(
          MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1'),
        ),
        const Left<Failure, ChatStreamEvent>(_authExpired),
      ]);
      verifyNever(() => sessionRepository.refresh());
    },
  );

  test(
    '#7 sendMessage stream: first item Left(AuthExpiredFailure), refresh '
    'itself also fails -> original failure yielded once, stream closes',
    () async {
      when(
        () => remoteDataSource.sendMessage(
          sessionId: any(named: 'sessionId'),
          content: any(named: 'content'),
        ),
      ).thenAnswer((_) => Stream.value(const Left(_authExpired)));
      when(
        () => sessionRepository.refresh(),
      ).thenAnswer((_) async => const Left(_authExpired));

      final results = await repository
          .sendMessage(sessionId: 's1', content: 'hi')
          .toList();

      expect(results, [const Left<Failure, ChatStreamEvent>(_authExpired)]);
      verify(() => sessionRepository.refresh()).called(1);
    },
  );

  test(
    '#8 a message_created frame followed by a connection-drop reaches the '
    'caller, in order',
    () async {
      const offline = NetworkOfflineFailure(message: 'offline', requestId: '');
      when(
        () => remoteDataSource.sendMessage(
          sessionId: any(named: 'sessionId'),
          content: any(named: 'content'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          const Right(MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1')),
          const Left(offline),
        ]),
      );

      final results = await repository
          .sendMessage(sessionId: 's1', content: 'hi')
          .toList();

      expect(results, [
        const Right<Failure, ChatStreamEvent>(
          MessageCreated(userMessageId: 'u1', assistantMessageId: 'a1'),
        ),
        const Left<Failure, ChatStreamEvent>(offline),
      ]);
    },
  );

  group('savedEntryIdFor()/recordMessageSaved()', () {
    test(
      "#9 savedEntryIdFor('m1') before any local-cache-loading call has run "
      '-> null',
      () {
        expect(repository.savedEntryIdFor('m1'), isNull);
      },
    );

    test(
      "#10 after listMessages(sessionId) resolves, savedEntryIdFor for a "
      'previously-recorded id returns that entryId',
      () async {
        when(
          () => localCache.readSavedMessageEntryIds(),
        ).thenAnswer((_) async => {'m1': 'e1'});
        when(() => remoteDataSource.listMessages('s1')).thenAnswer(
          (_) async => Right([_buildMessage()]),
        );

        await repository.listMessages('s1');

        expect(repository.savedEntryIdFor('m1'), 'e1');
      },
    );

    test(
      '#11 recordMessageSaved calls writeSavedMessageEntryIds with the '
      'merged map, and a subsequent savedEntryIdFor returns it without a '
      'new storage read',
      () async {
        await repository.recordMessageSaved(chatMessageId: 'm1', entryId: 'e1');

        verify(() => localCache.writeSavedMessageEntryIds({'m1': 'e1'})).called(1);
        expect(repository.savedEntryIdFor('m1'), 'e1');
      },
    );

    test(
      '#12 recordMessageSaved called twice for the same pair is a harmless '
      'overwrite — no error, exactly one entry in the map for that id',
      () async {
        await repository.recordMessageSaved(chatMessageId: 'm1', entryId: 'e1');
        await repository.recordMessageSaved(chatMessageId: 'm1', entryId: 'e1');

        expect(repository.savedEntryIdFor('m1'), 'e1');
        verify(() => localCache.writeSavedMessageEntryIds(any())).called(2);
      },
    );

    test(
      '#13 FR-004/US2: with no local record of a prior success (as if the '
      'device cache were cleared/reinstalled), savedEntryIdFor returns null; '
      'after an idempotent-retry save completes, it self-heals to the '
      'returned entryId regardless of what it previously held',
      () async {
        expect(repository.savedEntryIdFor('m1'), isNull);

        await repository.recordMessageSaved(chatMessageId: 'm1', entryId: 'e1');

        expect(repository.savedEntryIdFor('m1'), 'e1');
      },
    );
  });
}
