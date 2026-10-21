import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_sessions_page.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_state.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockChatRepository extends Mock implements ChatRepository {}

ChatSession _buildSession({required String id}) => ChatSession(
  id: id,
  title: 'title-$id',
  personaSnapshot: ChatPersona.analitico,
  userMessageCount: 1,
  lastUserMessageAt: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  late MockChatRepository chatRepository;

  setUp(() {
    chatRepository = MockChatRepository();
  });

  ChatSessionsBloc buildBloc() => ChatSessionsBloc(chatRepository: chatRepository);

  group('SessionsStarted', () {
    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#1 a successful first page -> ChatSessionsLoaded with the backend\'s own nextCursor',
      setUp: () {
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async => Right(ChatSessionsPage(sessions: [_buildSession(id: 's1')], nextCursor: 'c2')),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SessionsStarted()),
      expect: () => [
        const ChatSessionsLoading(),
        isA<ChatSessionsLoaded>()
            .having((s) => s.sessions.map((e) => e.id), 'session ids', ['s1'])
            .having((s) => s.nextCursor, 'nextCursor', 'c2'),
      ],
    );

    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#2 fails outright, nothing cached -> ChatSessionsLoadFailure',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer((_) async => const Left(failure));
        when(() => chatRepository.cachedSessions).thenReturn(const []);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SessionsStarted()),
      expect: () => [
        const ChatSessionsLoading(),
        isA<ChatSessionsLoadFailure>(),
      ],
    );

    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#3 fails, but cachedSessions is non-empty -> ChatSessionsLoaded(sessions: cached)',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
        final cached = [_buildSession(id: 'cached-1')];
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer((_) async => const Left(failure));
        when(() => chatRepository.cachedSessions).thenReturn(cached);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SessionsStarted()),
      expect: () => [
        const ChatSessionsLoading(),
        isA<ChatSessionsLoaded>()
            .having((s) => s.sessions.map((e) => e.id), 'session ids', ['cached-1'])
            .having((s) => s.nextCursor, 'nextCursor', isNull),
      ],
    );
  });

  group('SessionsRefreshRequested', () {
    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#4 fired while already ChatSessionsLoaded, refresh fails -> existing '
      'sessions list is not regressed to ChatSessionsLoading/ChatSessionsLoadFailure '
      '(the repository\'s own cache, populated by the earlier successful fetch '
      'that produced the seeded state, still has something to fall back to)',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer((_) async => const Left(failure));
        when(() => chatRepository.cachedSessions).thenReturn([_buildSession(id: 's1')]);
      },
      build: buildBloc,
      seed: () => ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1')],
        nextCursor: null,
        isLoadingMore: false,
      ),
      act: (bloc) => bloc.add(const SessionsRefreshRequested()),
      // No new state is even emitted: the post-failure fallback resolves to
      // the exact same ChatSessionsLoaded already showing (Equatable
      // equality), which is itself the strongest proof of "never regresses".
      expect: () => <ChatSessionsState>[],
      verify: (bloc) {
        expect(bloc.state, isA<ChatSessionsLoaded>());
        expect((bloc.state as ChatSessionsLoaded).sessions.map((e) => e.id), ['s1']);
      },
    );
  });

  group('SessionsNextPageRequested', () {
    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#5 when hasReachedEnd is already true -> no repository call',
      build: buildBloc,
      seed: () => ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1')],
        nextCursor: null,
        isLoadingMore: false,
      ),
      act: (bloc) => bloc.add(const SessionsNextPageRequested()),
      expect: () => <ChatSessionsState>[],
      verify: (_) {
        verifyNever(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        );
      },
    );

    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#6 succeeds -> sessions grows by exactly the new page\'s items, no '
      'duplicates, nextCursor updated',
      setUp: () {
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async => Right(ChatSessionsPage(sessions: [_buildSession(id: 's2')], nextCursor: null)),
        );
      },
      build: buildBloc,
      seed: () => ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1')],
        nextCursor: 'c2',
        isLoadingMore: false,
      ),
      act: (bloc) => bloc.add(const SessionsNextPageRequested()),
      expect: () => [
        isA<ChatSessionsLoaded>().having((s) => s.isLoadingMore, 'isLoadingMore', true),
        isA<ChatSessionsLoaded>()
            .having((s) => s.sessions.map((e) => e.id), 'session ids', ['s1', 's2'])
            .having((s) => s.nextCursor, 'nextCursor', isNull)
            .having((s) => s.isLoadingMore, 'isLoadingMore', false),
      ],
    );

    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#7 an AuthExpiredFailure leaves sessions/nextCursor unchanged, '
      'pageLoadFailure stays null, isLoadingMore resets to false, and '
      'reauthRequired fires exactly once',
      setUp: () {
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
      },
      build: buildBloc,
      seed: () => ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1')],
        nextCursor: 'c2',
        isLoadingMore: false,
      ),
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const SessionsNextPageRequested());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      expect: () => [
        isA<ChatSessionsLoaded>().having((s) => s.isLoadingMore, 'isLoadingMore', true),
        isA<ChatSessionsLoaded>()
            .having((s) => s.sessions.map((e) => e.id), 'session ids', ['s1'])
            .having((s) => s.nextCursor, 'nextCursor', 'c2')
            .having((s) => s.isLoadingMore, 'isLoadingMore', false)
            .having((s) => s.pageLoadFailure, 'pageLoadFailure', isNull),
      ],
    );

    blocTest<ChatSessionsBloc, ChatSessionsState>(
      '#8 two fired back-to-back before the first resolves -> the second is '
      'a no-op while isLoadingMore is already true',
      setUp: () {
        when(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Right(ChatSessionsPage(sessions: [_buildSession(id: 's2')], nextCursor: null));
        });
      },
      build: buildBloc,
      seed: () => ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1')],
        nextCursor: 'c2',
        isLoadingMore: false,
      ),
      act: (bloc) {
        bloc.add(const SessionsNextPageRequested());
        bloc.add(const SessionsNextPageRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => chatRepository.listSessions(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
        ).called(1);
      },
    );
  });
}
