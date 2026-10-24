import 'package:cerne/features/export/presentation/widgets/export_failed_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy is textually distinct from the narrative-failed view\'s, '
      'no download button renders, only "Fechar" is present', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ExportFailedView(onClosePressed: () {}))),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('Não foi possível gerar a exportação'), findsOneWidget);
    expect(find.textContaining('resumo com IA'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.widgetWithText(TextButton, 'Fechar'), findsOneWidget);
  });

  testWidgets('tapping "Fechar" invokes onClosePressed', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ExportFailedView(onClosePressed: () => closed = true))),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Fechar'));

    expect(closed, isTrue);
  });
}
