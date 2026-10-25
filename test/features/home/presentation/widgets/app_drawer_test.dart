import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_state.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:cerne/features/home/presentation/widgets/app_drawer.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:cerne/features/settings/domain/repositories/account_profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockChatBloc extends MockBloc<ChatEvent, ChatState> implements ChatBloc {}

class MockChatSessionsBloc extends MockBloc<ChatSessionsEvent, ChatSessionsState>
    implements ChatSessionsBloc {}

class MockSessionBloc extends MockBloc<SessionEvent, SessionStatus> implements SessionBloc {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

class MockAccountProfileRepository extends Mock implements AccountProfileRepository {}

ChatSession _buildSession({required String id, required String title}) => ChatSession(
  id: id,
  title: title,
  personaSnapshot: ChatPersona.analitico,
  userMessageCount: 1,
  lastUserMessageAt: DateTime(2026, 1, 15, 9, 30),
  createdAt: DateTime(2026, 1, 15),
  updatedAt: DateTime(2026, 1, 15),
);

void main() {
  late MockChatBloc chatBloc;
  late MockChatSessionsBloc chatSessionsBloc;
  late MockSessionBloc sessionBloc;

  setUpAll(() {
    registerFallbackValue(const NewConversationRequested());
    registerFallbackValue(const ConversationSelected(''));
    registerFallbackValue(const SessionsNextPageRequested());
    registerFallbackValue(const AuthExpiredDetected());
  });

  setUp(() {
    chatBloc = MockChatBloc();
    chatSessionsBloc = MockChatSessionsBloc();
    sessionBloc = MockSessionBloc();
    when(() => chatSessionsBloc.reauthRequired).thenAnswer((_) => const Stream.empty());
    when(() => chatSessionsBloc.close()).thenAnswer((_) async {});

    final tokenStorage = MockSecureTokenStorage();
    when(() => tokenStorage.readAccountEmail()).thenAnswer((_) async => 'wagner.duarte@x.com');
    getIt.registerLazySingleton<SecureTokenStorage>(() => tokenStorage);

    final accountProfileRepository = MockAccountProfileRepository();
    when(() => accountProfileRepository.readCachedDisplayName())
        .thenAnswer((_) async => null);
    getIt.registerLazySingleton<AccountProfileRepository>(() => accountProfileRepository);
  });

  tearDown(getIt.reset);

  Future<GlobalKey<ScaffoldState>> pumpDrawer(
    WidgetTester tester,
    ChatSessionsState sessionsState, {
    bool settle = true,
  }) async {
    whenListen(
      chatSessionsBloc,
      const Stream<ChatSessionsState>.empty(),
      initialState: sessionsState,
    );
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ChatBloc>.value(value: chatBloc),
            BlocProvider<ChatSessionsBloc>.value(value: chatSessionsBloc),
            BlocProvider<SessionBloc>.value(value: sessionBloc),
          ],
          child: Scaffold(
            key: scaffoldKey,
            drawer: const AppDrawer(),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    // `isLoadingMore`'s CircularProgressIndicator animates indefinitely, so
    // these two tests settle with a bounded pump instead of pumpAndSettle.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    return scaffoldKey;
  }

  testWidgets('shows an initials avatar + display name derived from the account email', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      const ChatSessionsLoaded(sessions: [], nextCursor: null, isLoadingMore: false),
    );

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('WD'), findsOneWidget);
    expect(find.text('Wagner Duarte'), findsOneWidget);
  });

  testWidgets('the CONVERSAS section lists each loaded session with its title + timestamp', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1', title: 'Ansiedade antes de apresentações')],
        nextCursor: null,
        isLoadingMore: false,
      ),
    );

    expect(find.text('Ansiedade antes de apresentações'), findsOneWidget);
    // Fixed past date -> always "older than this week" by the time this
    // test runs, so the relative formatter always renders "day + month".
    expect(find.textContaining('15 jan'), findsOneWidget);
  });

  testWidgets('tapping a session row dispatches ConversationSelected(session.id) and closes the drawer', (
    tester,
  ) async {
    final scaffoldKey = await pumpDrawer(
      tester,
      ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1', title: 'Ansiedade')],
        nextCursor: null,
        isLoadingMore: false,
      ),
    );

    await tester.tap(find.text('Ansiedade'));
    await tester.pumpAndSettle();

    verify(() => chatBloc.add(const ConversationSelected('s1'))).called(1);
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
  });

  testWidgets('tapping "Novo Chat" dispatches NewConversationRequested', (tester) async {
    await pumpDrawer(
      tester,
      const ChatSessionsLoaded(sessions: [], nextCursor: null, isLoadingMore: false),
    );

    await tester.tap(find.text('Novo Chat'));
    await tester.pumpAndSettle();

    verify(() => chatBloc.add(const NewConversationRequested())).called(1);
  });

  testWidgets('scrolling to the bottom of the section dispatches SessionsNextPageRequested', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      ChatSessionsLoaded(
        sessions: List.generate(30, (i) => _buildSession(id: 's$i', title: 'Session $i')),
        nextCursor: 'c2',
        isLoadingMore: false,
      ),
    );

    await tester.drag(find.text('Session 0'), const Offset(0, -4000));
    await tester.pumpAndSettle();

    verify(() => chatSessionsBloc.add(const SessionsNextPageRequested())).called(greaterThanOrEqualTo(1));
  });

  testWidgets('renders a loading indicator below the list while isLoadingMore is true', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      ChatSessionsLoaded(
        sessions: [_buildSession(id: 's1', title: 'Ansiedade')],
        nextCursor: 'c2',
        isLoadingMore: true,
      ),
      settle: false,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'renders a retry affordance dispatching SessionsPageLoadRetried when pageLoadFailure is set',
    (tester) async {
      const failure = NetworkOfflineFailure(message: 'Sem conexão', requestId: '');
      await pumpDrawer(
        tester,
        ChatSessionsLoaded(
          sessions: [_buildSession(id: 's1', title: 'Ansiedade')],
          nextCursor: 'c2',
          isLoadingMore: false,
          pageLoadFailure: failure,
        ),
      );

      expect(find.text('Sem conexão'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      verify(() => chatSessionsBloc.add(const SessionsPageLoadRetried())).called(1);
    },
  );
}
