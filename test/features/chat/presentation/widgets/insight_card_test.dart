import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/presentation/widgets/insight_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpCard(
  WidgetTester tester, {
  String content = 'Você tem falado bastante sobre prazos no trabalho.',
  required VoidCallback onDismiss,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InsightCard(content: content, onDismiss: onDismiss),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the "INSIGHT" label and the given content', (tester) async {
    await pumpCard(tester, content: 'meu texto gerado', onDismiss: () {});

    expect(find.text('INSIGHT'), findsOneWidget);
    expect(find.text('meu texto gerado'), findsOneWidget);
  });

  testWidgets('the "INSIGHT" label uses textMonoCaption with colorAccent', (tester) async {
    await pumpCard(tester, onDismiss: () {});

    final label = tester.widget<Text>(find.text('INSIGHT'));
    expect(label.style?.color, DesignTokens.colorAccent);
    expect(label.style?.fontFamily, DesignTokens.textMonoCaption.fontFamily);
  });

  testWidgets('the body text uses textBodyMd unmodified', (tester) async {
    const content = 'meu texto gerado';
    await pumpCard(tester, content: content, onDismiss: () {});

    final body = tester.widget<Text>(find.text(content));
    expect(body.style, DesignTokens.textBodyMd);
  });

  testWidgets('renders an Icons.close dismiss glyph in colorTextSecondary', (tester) async {
    await pumpCard(tester, onDismiss: () {});

    final icon = tester.widget<Icon>(find.byIcon(Icons.close));
    expect(icon.color, DesignTokens.colorTextSecondary);
    expect(icon.size, DesignTokens.sizeInsightDismissIcon);
  });

  testWidgets('tapping the dismiss glyph invokes onDismiss exactly once', (tester) async {
    var dismissCount = 0;
    await pumpCard(tester, onDismiss: () => dismissCount++);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissCount, 1);
  });
}
