import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/presentation/widgets/filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({DateRangeOption dateRange, Set<EntrySource> entryTypes})? result;

  Future<void> pumpAndOpenSheet(
    WidgetTester tester, {
    DateRangeOption initialDateRange = DateRangeOption.allTime,
    Set<EntrySource> initialEntryTypes = const {},
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<
                    ({DateRangeOption dateRange, Set<EntrySource> entryTypes})>(
                  context: context,
                  builder: (_) => FilterSheet(
                    initialDateRange: initialDateRange,
                    initialEntryTypes: initialEntryTypes,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'select "Esta semana" + "áudio", tap "Aplicar" -> pops with '
    'dateRange: thisWeek, entryTypes: {audio}',
    (tester) async {
      await pumpAndOpenSheet(tester);
      await tester.tap(find.text('Esta semana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áudio'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(result?.dateRange, DateRangeOption.thisWeek);
      expect(result?.entryTypes, {EntrySource.audio});
    },
  );

  testWidgets('opened with {audio, photo} already applied -> both chips render pre-selected', (
    tester,
  ) async {
    await pumpAndOpenSheet(
      tester,
      initialEntryTypes: const {EntrySource.audio, EntrySource.photo},
    );

    final audioChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Áudio'), matching: find.byType(ChoiceChip)),
    );
    final photoChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Foto'), matching: find.byType(ChoiceChip)),
    );
    expect(audioChip.selected, isTrue);
    expect(photoChip.selected, isTrue);
  });

  testWidgets('does not render a CATEGORIA group, matching the prototype', (tester) async {
    await pumpAndOpenSheet(tester);

    expect(find.text('CATEGORIA'), findsNothing);
    expect(find.text('trabalho'), findsNothing);
  });

  testWidgets('does not render a "Limpar" button, matching the prototype', (tester) async {
    await pumpAndOpenSheet(tester);

    expect(find.text('Limpar'), findsNothing);
  });

  testWidgets('groups render in prototype order: TIPO DE ENTRADA before PERÍODO', (
    tester,
  ) async {
    await pumpAndOpenSheet(tester);

    final entryTypeY = tester.getTopLeft(find.text('TIPO DE ENTRADA')).dy;
    final periodY = tester.getTopLeft(find.text('PERÍODO')).dy;
    expect(entryTypeY, lessThan(periodY));
  });

  testWidgets('a selected chip renders without a checkmark', (tester) async {
    await pumpAndOpenSheet(tester, initialEntryTypes: const {EntrySource.audio});

    final audioChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Áudio'), matching: find.byType(ChoiceChip)),
    );
    expect(audioChip.showCheckmark, isFalse);
  });

  testWidgets('"Aplicar" spans the full width of the sheet', (tester) async {
    await pumpAndOpenSheet(tester);

    final buttonWidth = tester.getSize(find.widgetWithText(ElevatedButton, 'Aplicar')).width;
    final sheetWidth = tester.getSize(find.byType(FilterSheet)).width;
    // Button fills the sheet's content width (sheet width minus the sheet's
    // own horizontal padding on both sides).
    expect(buttonWidth, greaterThan(sheetWidth * 0.8));
  });
}
