import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_state.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_offline_banner.dart';
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
  });

  Future<void> pumpHomeChatShellPage(WidgetTester tester, ChatState state) async {
    whenListen(chatBloc, Stream.value(state), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
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
}
