import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockChatBloc extends MockBloc<ChatEvent, ChatState> implements ChatBloc {}

void main() {
  late MockChatBloc bloc;

  setUpAll(() {
    registerFallbackValue(const MessageSubmitted(''));
  });

  setUp(() {
    bloc = MockChatBloc();
    when(() => bloc.reauthRequired).thenAnswer((_) => const Stream.empty());
    when(() => bloc.close()).thenAnswer((_) async {});
    const initial = ChatReady(
      sessionId: 's1',
      messages: [],
      isOffline: false,
      awaitingResponse: false,
    );
    whenListen(bloc, const Stream<ChatState>.empty(), initialState: initial);
  });

  Future<void> pumpComposer(WidgetTester tester, {required bool canSend}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<ChatBloc>.value(
          value: bloc,
          child: Scaffold(body: ChatComposer(canSend: canSend)),
        ),
      ),
    );
  }

  testWidgets(
    'typing non-empty text and tapping send dispatches MessageSubmitted(text) '
    'and clears the controller afterward',
    (tester) async {
      await pumpComposer(tester, canSend: true);

      await tester.enterText(find.byType(TextField), 'olá');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();

      verify(() => bloc.add(const MessageSubmitted('olá'))).called(1);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    },
  );

  testWidgets(
    'typing only whitespace keeps the send control inactive and dispatches nothing',
    (tester) async {
      await pumpComposer(tester, canSend: true);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      final sendButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send_outlined),
      );
      expect(sendButton.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();
      verifyNever(() => bloc.add(any()));
    },
  );

  testWidgets('canSend: false disables the text field and the send control', (tester) async {
    await pumpComposer(tester, canSend: false);
    await tester.enterText(find.byType(TextField), 'olá');
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send_outlined),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('re-enables automatically once canSend flips back to true', (tester) async {
    await pumpComposer(tester, canSend: false);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await pumpComposer(tester, canSend: true);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets(
    'the field is a fully rounded pill filled with colorSurfaceBg, a darker '
    'beige than the bar it sits on (prototype: #F2EFE7 on a #FBF9F4 bar)',
    (tester) async {
      await pumpComposer(tester, canSend: true);

      final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, DesignTokens.colorSurfaceBg);
      final border = decoration.border as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(DesignTokens.radiusFull));
    },
  );
}
