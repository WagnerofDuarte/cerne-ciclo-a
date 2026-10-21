import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _buildMessage({
  required ChatMessageStatus status,
  ChatRole role = ChatRole.assistant,
  String content = 'hello',
  DateTime? createdAt,
}) => ChatMessage(
  id: 'm1',
  sessionId: 's1',
  role: role,
  content: content,
  seq: 0,
  status: status,
  retryCount: 0,
  createdAt: createdAt ?? DateTime(2026, 1, 1, 10, 30),
);

Future<void> pumpBubble(
  WidgetTester tester,
  ChatMessage message, {
  VoidCallback? onRetryTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageBubble(message: message, onRetryTap: onRetryTap),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'a streaming message renders an inline blinking cursor at the end of '
    'its text, no spinner below the bubble, and is not tappable',
    (tester) async {
      var tapped = false;
      await pumpBubble(
        tester,
        _buildMessage(status: ChatMessageStatus.streaming),
        onRetryTap: () => tapped = true,
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final richText = tester.widget<Text>(find.byType(Text));
      final span = richText.textSpan! as TextSpan;
      expect(span.text, 'hello');
      expect(span.children, hasLength(1));
      expect(span.children!.single, isA<WidgetSpan>());

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(tapped, isFalse);
    },
  );

  testWidgets('an empty streaming message still renders only the blinking cursor', (
    tester,
  ) async {
    await pumpBubble(tester, _buildMessage(status: ChatMessageStatus.streaming, content: ''));

    final richText = tester.widget<Text>(find.byType(Text));
    final span = richText.textSpan! as TextSpan;
    expect(span.text, '');
    expect(span.children, hasLength(1));
    expect(span.children!.single, isA<WidgetSpan>());
  });

  testWidgets('a complete message renders its final text + timestamp with no indicator', (
    tester,
  ) async {
    await pumpBubble(tester, _buildMessage(status: ChatMessageStatus.complete, content: 'oi!'));

    expect(find.text('oi!'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Falha'), findsNothing);
  });

  testWidgets(
    'a failed message renders "Falha ao gerar resposta" in colorError, '
    'regular (not monospaced) font, with the timestamp still below it '
    '(prototype: the note sits above the time, not in its place)',
    (tester) async {
      await pumpBubble(tester, _buildMessage(status: ChatMessageStatus.failed));

      final finder = find.textContaining('Falha ao gerar resposta');
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      expect(text.style?.color, DesignTokens.colorError);
      expect(text.style?.fontFamily, DesignTokens.textBodyMd.fontFamily);
      expect(text.style?.fontSize, 12);

      final context = tester.element(find.byType(Scaffold));
      final expectedLabel = TimeOfDay.fromDateTime(
        _buildMessage(status: ChatMessageStatus.failed).createdAt.toLocal(),
      ).format(context);
      expect(find.text(expectedLabel), findsOneWidget);
    },
  );

  testWidgets('tapping a failed bubble invokes onRetryTap exactly once', (tester) async {
    var tapCount = 0;
    await pumpBubble(
      tester,
      _buildMessage(status: ChatMessageStatus.failed),
      onRetryTap: () => tapCount++,
    );

    await tester.tap(find.text('hello'));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets(
    'a UTC createdAt (as returned by the backend for a history-loaded '
    'message) renders the local wall-clock time, same as the current '
    "device's own local DateTime would — not the raw UTC hour",
    (tester) async {
      final utcCreatedAt = DateTime.utc(2026, 1, 1, 23, 20);
      await pumpBubble(
        tester,
        _buildMessage(status: ChatMessageStatus.complete, createdAt: utcCreatedAt),
      );

      final context = tester.element(find.byType(Scaffold));
      final expectedLabel = TimeOfDay.fromDateTime(utcCreatedAt.toLocal()).format(context);

      expect(find.text(expectedLabel), findsOneWidget);
    },
  );

  testWidgets('tapping a streaming/complete bubble invokes nothing', (tester) async {
    var tapCount = 0;
    await pumpBubble(
      tester,
      _buildMessage(status: ChatMessageStatus.complete),
      onRetryTap: () => tapCount++,
    );

    await tester.tap(find.text('hello'));
    await tester.pump();

    expect(tapCount, 0);
  });
}
