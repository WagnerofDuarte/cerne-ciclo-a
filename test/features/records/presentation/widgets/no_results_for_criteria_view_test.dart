import 'package:cerne/features/records/presentation/widgets/no_results_for_criteria_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders distinct copy and invokes onAdjustPressed when tapped', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoResultsForCriteriaView(onAdjustPressed: () => pressed = true),
        ),
      ),
    );

    expect(find.text('Nenhum resultado para esta busca/filtro'), findsOneWidget);
    expect(find.text('Nenhum registro ainda'), findsNothing);

    await tester.tap(find.text('Limpar filtros'));
    await tester.pump();

    expect(pressed, isTrue);
  });
}
