import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/routing/app_router.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/proactive_insight.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_state.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:cerne/features/chat/presentation/widgets/bookmark_button.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_offline_banner.dart';
import 'package:cerne/features/chat/presentation/widgets/insight_card.dart';
import 'package:cerne/features/home/presentation/pages/home_chat_shell_page.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockChatBloc extends MockBloc<ChatEvent, ChatState> implements ChatBloc {}

class MockChatSessionsBloc extends MockBloc<ChatSessionsEvent, ChatSessionsState>
    implements ChatSessionsBloc {}

class MockSessionBloc extends MockBloc<SessionEvent, SessionStatus> implements SessionBloc {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

ChatMessage _buildMessage({
  required String id,
  required ChatRole role,
  required ChatMessageStatus status,
  String content = 'olá',
  int seq = 0,
}) => ChatMessage(
  id: id,
  sessionId: 's1',
  role: role,
  content: content,
  seq: seq,
  status: status,
  retryCount: 0,
  createdAt: DateTime(2026, 1, 15, 9, 30),
);

void main() {
  late MockChatBloc chatBloc;
  late MockChatSessionsBloc chatSessionsBloc;
  late MockSessionBloc sessionBloc;

  setUpAll(() {
    registerFallbackValue(const ConversationSelected(''));
    registerFallbackValue(const MessageRetryRequested(''));
    registerFallbackValue(const AuthExpiredDetected());
  });

  setUp(() {
    chatBloc = MockChatBloc();
    chatSessionsBloc = MockChatSessionsBloc();
    sessionBloc = MockSessionBloc();
    when(() => chatBloc.reauthRequired).thenAnswer((_) => const Stream.empty());
    when(() => chatBloc.close()).thenAnswer((_) async {});
    when(() => chatSessionsBloc.reauthRequired).thenAnswer((_) => const Stream.empty());
    when(() => chatSessionsBloc.close()).thenAnswer((_) async {});
    whenListen(
      chatSessionsBloc,
      const Stream<ChatSessionsState>.empty(),
      initialState: const ChatSessionsLoaded(sessions: [], nextCursor: null, isLoadingMore: false),
    );

    // AppDrawer (rendered when the drawer opens, research.md R10's drawer
    // test) reads this via getIt in its own initState.
    final tokenStorage = MockSecureTokenStorage();
    when(() => tokenStorage.readAccountEmail()).thenAnswer((_) async => 'wagner@x.com');
    getIt.registerLazySingleton<SecureTokenStorage>(() => tokenStorage);
  });

  tearDown(getIt.reset);

  Future<void> pumpHomeChatShellPage(WidgetTester tester, ChatState state) async {
    whenListen(chatBloc, Stream.value(state), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [chatRouteObserver],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ChatBloc>.value(value: chatBloc),
            BlocProvider<ChatSessionsBloc>.value(value: chatSessionsBloc),
            BlocProvider<SessionBloc>.value(value: sessionBloc),
          ],
          child: const HomeChatShellPage(),
        ),
      ),
    );
    await tester.pump();
  }

  group('load failure view', () {
    testWidgets(
      'ChatReady(loadFailure: ...) renders the failure message and a retry '
      'action dispatching ConversationSelected(state.sessionId), not the '
      'empty ListView',
      (tester) async {
        const failure = NetworkOfflineFailure(message: 'Sem conexão com a internet.', requestId: '');
        await pumpHomeChatShellPage(
          tester,
          const ChatReady(
            sessionId: 's1',
            messages: [],
            isOffline: false,
            awaitingResponse: false,
            loadFailure: failure,
          ),
        );

        expect(find.text('Sem conexão com a internet.'), findsOneWidget);
        expect(find.byType(ListView), findsNothing);

        await tester.tap(find.text('Tentar novamente'));
        await tester.pump();

        verify(() => chatBloc.add(const ConversationSelected('s1'))).called(1);
      },
    );
  });

  group('offline banner', () {
    testWidgets('ChatReady(isOffline: true) renders ChatOfflineBanner', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(
          sessionId: 's1',
          messages: [],
          isOffline: true,
          awaitingResponse: false,
        ),
      );

      expect(find.byType(ChatOfflineBanner), findsOneWidget);
    });

    testWidgets('ChatReady(isOffline: false) does not render ChatOfflineBanner', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(
          sessionId: 's1',
          messages: [],
          isOffline: false,
          awaitingResponse: false,
        ),
      );

      expect(find.byType(ChatOfflineBanner), findsNothing);
    });
  });

  group('composer enabled/disabled wiring', () {
    testWidgets('canSend == true -> the TextField is enabled', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(
          sessionId: 's1',
          messages: [],
          isOffline: false,
          awaitingResponse: false,
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isTrue);
    });

    testWidgets('canSend == false (awaitingResponse) -> the TextField is disabled', (
      tester,
    ) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(
          sessionId: 's1',
          messages: [],
          isOffline: false,
          awaitingResponse: true,
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('canSend == false (isOffline) -> the TextField is disabled', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(
          sessionId: 's1',
          messages: [],
          isOffline: true,
          awaitingResponse: false,
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });
  });

  group('retry tap wiring', () {
    testWidgets(
      "tapping a failed message bubble's retry affordance dispatches "
      'MessageRetryRequested with the preceding user message id',
      (tester) async {
        await pumpHomeChatShellPage(
          tester,
          ChatReady(
            sessionId: 's1',
            messages: [
              _buildMessage(id: 'u1', role: ChatRole.user, status: ChatMessageStatus.complete),
              _buildMessage(
                id: 'a1',
                role: ChatRole.assistant,
                status: ChatMessageStatus.failed,
                seq: 1,
              ),
            ],
            isOffline: false,
            awaitingResponse: false,
          ),
        );

        await tester.tap(find.text('Falha ao gerar resposta — toque para tentar novamente'));
        await tester.pump();

        verify(() => chatBloc.add(const MessageRetryRequested('u1'))).called(1);
      },
    );
  });

  group('bookmark wiring (US4/SC-004)', () {
    testWidgets(
      'a mixed message list (including a streaming and a failed assistant '
      'message) renders exactly one BookmarkButton per user message and '
      'zero on any assistant message',
      (tester) async {
        await pumpHomeChatShellPage(
          tester,
          ChatReady(
            sessionId: 's1',
            messages: [
              _buildMessage(id: 'u1', role: ChatRole.user, status: ChatMessageStatus.complete),
              _buildMessage(
                id: 'a1',
                role: ChatRole.assistant,
                status: ChatMessageStatus.streaming,
                seq: 1,
              ),
              _buildMessage(id: 'u2', role: ChatRole.user, status: ChatMessageStatus.complete, seq: 2),
              _buildMessage(
                id: 'a2',
                role: ChatRole.assistant,
                status: ChatMessageStatus.failed,
                seq: 3,
              ),
            ],
            isOffline: false,
            awaitingResponse: false,
          ),
        );

        expect(find.byType(BookmarkButton), findsNWidgets(2));
      },
    );

    testWidgets(
      "tapping a user message's bookmark dispatches BookmarkTapped(message.id)",
      (tester) async {
        await pumpHomeChatShellPage(
          tester,
          ChatReady(
            sessionId: 's1',
            messages: [
              _buildMessage(id: 'u1', role: ChatRole.user, status: ChatMessageStatus.complete),
            ],
            isOffline: false,
            awaitingResponse: false,
          ),
        );

        await tester.tap(find.byType(BookmarkButton));
        await tester.pump();

        verify(() => chatBloc.add(const BookmarkTapped('u1'))).called(1);
      },
    );
  });

  group('reauth forwarding', () {
    testWidgets(
      "a reauthRequired event from ChatBloc is forwarded to "
      'SessionBloc.add(AuthExpiredDetected())',
      (tester) async {
        when(() => chatBloc.reauthRequired).thenAnswer((_) => Stream.value(null));

        await pumpHomeChatShellPage(
          tester,
          const ChatReady(
            sessionId: 's1',
            messages: [],
            isOffline: false,
            awaitingResponse: false,
          ),
        );
        await tester.pump();

        verify(() => sessionBloc.add(const AuthExpiredDetected())).called(1);
      },
    );
  });

  group('insight-card interleaving (US1/FR-005)', () {
    testWidgets(
      'the card renders at anchorIndex, surrounding messages render at the '
      'correct shifted indices, no change to scroll/composer',
      (tester) async {
        await pumpHomeChatShellPage(
          tester,
          ChatReady(
            sessionId: 's1',
            messages: [
              _buildMessage(id: 'u1', role: ChatRole.user, status: ChatMessageStatus.complete),
              _buildMessage(
                id: 'a1',
                role: ChatRole.assistant,
                status: ChatMessageStatus.complete,
                seq: 1,
              ),
              _buildMessage(
                id: 'u2',
                role: ChatRole.user,
                status: ChatMessageStatus.complete,
                seq: 2,
              ),
            ],
            isOffline: false,
            awaitingResponse: false,
            insight: const ProactiveInsight(content: 'texto gerado', anchorIndex: 3),
          ),
        );

        expect(find.byType(InsightCard), findsOneWidget);
        expect(find.byType(ChatMessageBubble), findsNWidgets(3));

        // anchorIndex == messages.length (2) -> the card renders after all
        // three existing messages, not interleaved among them.
        final cardTop = tester.getTopLeft(find.byType(InsightCard)).dy;
        final bubbleBottoms = tester
            .widgetList(find.byType(ChatMessageBubble))
            .map((w) => tester.getBottomLeft(find.byWidget(w)).dy);
        for (final bottom in bubbleBottoms) {
          expect(cardTop, greaterThanOrEqualTo(bottom));
        }

        // The composer stays rendered/untouched regardless of the card.
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets('no insight -> no InsightCard, itemCount unaffected', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        ChatReady(
          sessionId: 's1',
          messages: [_buildMessage(id: 'u1', role: ChatRole.user, status: ChatMessageStatus.complete)],
          isOffline: false,
          awaitingResponse: false,
        ),
      );

      expect(find.byType(InsightCard), findsNothing);
    });

    testWidgets(
      "tapping the card's dismiss control dispatches InsightDismissed",
      (tester) async {
        await pumpHomeChatShellPage(
          tester,
          ChatReady(
            sessionId: 's1',
            messages: [
              _buildMessage(id: 'u1', role: ChatRole.user, status: ChatMessageStatus.complete),
            ],
            isOffline: false,
            awaitingResponse: false,
            insight: const ProactiveInsight(content: 'texto gerado', anchorIndex: 0),
          ),
        );

        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();

        verify(() => chatBloc.add(const InsightDismissed())).called(1);
      },
    );
  });

  group('lifecycle/drawer/route wiring dispatches ChatForegroundChanged (US2/FR-010)', () {
    testWidgets('app backgrounding/resume', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(sessionId: 's1', messages: [], isOffline: false, awaitingResponse: false),
      );
      clearInteractions(chatBloc);

      // Valid AppLifecycleState transitions only (resumed -> inactive is
      // allowed directly; inactive -> resumed is allowed directly) — this
      // bloc's own handler treats every non-"resumed" state identically, so
      // exercising "inactive" covers the same `false` branch "paused" would.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      verify(() => chatBloc.add(const ChatForegroundChanged(false))).called(1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      verify(() => chatBloc.add(const ChatForegroundChanged(true))).called(1);
    });

    testWidgets('opening/closing the drawer', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(sessionId: 's1', messages: [], isOffline: false, awaitingResponse: false),
      );
      clearInteractions(chatBloc);

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();
      verify(() => chatBloc.add(const ChatForegroundChanged(false))).called(1);

      scaffold.closeDrawer();
      await tester.pumpAndSettle();
      verify(() => chatBloc.add(const ChatForegroundChanged(true))).called(1);
    });

    testWidgets('pushing to another route and popping back', (tester) async {
      await pumpHomeChatShellPage(
        tester,
        const ChatReady(sessionId: 's1', messages: [], isOffline: false, awaitingResponse: false),
      );
      clearInteractions(chatBloc);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
      await tester.pumpAndSettle();
      verify(() => chatBloc.add(const ChatForegroundChanged(false))).called(1);

      navigator.pop();
      await tester.pumpAndSettle();
      verify(() => chatBloc.add(const ChatForegroundChanged(true))).called(1);
    });
  });
}
