import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_status.dart';
import 'package:cerne/features/chat/presentation/widgets/bookmark_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpButton(
  WidgetTester tester,
  BookmarkStatus status, {
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: BookmarkButton(status: status, onTap: onTap)),
    ),
  );
}

void main() {
  testWidgets('idle renders Icons.bookmark_border in colorTextSecondary, '
      'tappable', (tester) async {
    var tapped = false;
    await pumpButton(tester, BookmarkStatus.idle, onTap: () => tapped = true);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.bookmark_border);
    expect(icon.color, DesignTokens.colorTextSecondary);
    expect(icon.size, DesignTokens.sizeBookmarkIcon);
    expect(find.byType(GestureDetector), findsOneWidget);

    await tester.tap(find.byType(GestureDetector));
    expect(tapped, isTrue);
  });

  testWidgets('saving renders a spinner in colorTextSecondary, no '
      'GestureDetector at all', (tester) async {
    await pumpButton(tester, BookmarkStatus.saving);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('saved renders Icons.check in colorAccent, no GestureDetector '
      'at all', (tester) async {
    await pumpButton(tester, BookmarkStatus.saved);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.check);
    expect(icon.color, DesignTokens.colorAccent);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('error renders Icons.error_outline in colorError, tappable', (
    tester,
  ) async {
    var tapped = false;
    await pumpButton(tester, BookmarkStatus.error, onTap: () => tapped = true);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.error_outline);
    expect(icon.color, DesignTokens.colorError);
    expect(find.byType(GestureDetector), findsOneWidget);

    await tester.tap(find.byType(GestureDetector));
    expect(tapped, isTrue);
  });
}
