import 'package:cerne/features/export/presentation/widgets/export_empty_period_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('"Nenhum registro nesse período." copy, the filter-adjustment '
      'suggestion, and no download button renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ExportEmptyPeriodView(onClosePressed: () {}))),
    );

    expect(find.text('Nenhum registro nesse período.'), findsOneWidget);
    expect(find.textContaining('Ajuste o filtro'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.widgetWithText(TextButton, 'Fechar'), findsOneWidget);
  });
}
