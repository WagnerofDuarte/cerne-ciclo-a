import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:cerne/features/records/presentation/widgets/active_filter_chips_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRecordsBloc extends MockBloc<RecordsEvent, RecordsState> implements RecordsBloc {}

void main() {
  late MockRecordsBloc bloc;

  setUpAll(() {
    registerFallbackValue(const DateRangeChip(DateRangeOption.thisWeek));
  });

  setUp(() {
    bloc = MockRecordsBloc();
  });

  Future<void> pumpRow(WidgetTester tester, List<ActiveFilterChip> chips) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RecordsBloc>.value(
          value: bloc,
          child: Scaffold(body: ActiveFilterChipsRow(chips: chips)),
        ),
      ),
    );
  }

  testWidgets('renders one chip per entry plus "Limpar filtros"', (tester) async {
    await pumpRow(tester, const [
      DateRangeChip(DateRangeOption.thisWeek),
      EntryTypeChip(EntrySource.audio),
    ]);

    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('Áudio'), findsOneWidget);
    expect(find.text('Limpar filtros'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(2));
  });

  testWidgets('tapping a chip\'s remove control dispatches FilterChipRemoved '
      'with that exact chip value', (tester) async {
    const chip = EntryTypeChip(EntrySource.audio);
    await pumpRow(tester, const [chip]);

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();

    verify(() => bloc.add(const FilterChipRemoved(chip))).called(1);
  });

  testWidgets('tapping "Limpar filtros" dispatches FiltersAndSearchCleared', (tester) async {
    await pumpRow(tester, const [DateRangeChip(DateRangeOption.thisWeek)]);

    await tester.tap(find.text('Limpar filtros'));
    await tester.pump();

    verify(() => bloc.add(const FiltersAndSearchCleared())).called(1);
  });
}
