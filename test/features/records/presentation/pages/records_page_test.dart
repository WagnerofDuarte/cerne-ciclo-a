import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:cerne/features/records/presentation/pages/records_page.dart';
import 'package:cerne/features/records/presentation/widgets/active_filter_chips_row.dart';
import 'package:cerne/features/records/presentation/widgets/no_results_for_criteria_view.dart';
import 'package:cerne/features/records/presentation/widgets/records_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRecordsBloc extends MockBloc<RecordsEvent, RecordsState> implements RecordsBloc {}

Entry _buildEntry({required String id}) => Entry(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: DateTime(2026, 1, 1),
  tags: const [],
  piiStatus: PiiStatus.pending,
  piiSpans: const [],
  embeddingStatus: EmbeddingStatus.pending,
  mediaDurationSeconds: null,
  serverRevision: 1,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  late MockRecordsBloc bloc;

  setUpAll(() {
    registerFallbackValue(const SearchTextChanged(''));
    registerFallbackValue(const FiltersAndSearchCleared());
  });

  setUp(() {
    bloc = MockRecordsBloc();
    when(() => bloc.reauthRequired).thenAnswer((_) => const Stream.empty());
    when(() => bloc.close()).thenAnswer((_) async {});
  });

  Future<void> pumpRecordsPage(WidgetTester tester, RecordsState state) async {
    whenListen(bloc, Stream.value(state), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RecordsBloc>.value(value: bloc, child: const RecordsPage()),
      ),
    );
    await tester.pump();
  }

  group('search bar', () {
    testWidgets('typing dispatches SearchTextChanged once per keystroke', (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
      );

      await tester.enterText(find.byType(TextField), 'ansiedade');

      verify(() => bloc.add(const SearchTextChanged('ansiedade'))).called(1);
    });
  });

  group('funnel button filled state', () {
    testWidgets('hasActiveFilters == true -> funnel renders filled (colorAccent background)', (
      tester,
    ) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(
          entries: [_buildEntry(id: 'e1')],
          nextCursor: null,
          isLoadingMore: false,
          dateRange: DateRangeOption.thisWeek,
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.filter_alt));
      expect(icon.color, DesignTokens.colorOnAccent);

      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.filter_alt), matching: find.byType(IconButton)),
      );
      expect(iconButton.style?.backgroundColor?.resolve({}), DesignTokens.colorAccent);
    });

    testWidgets('hasActiveFilters == false -> funnel renders neutral', (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.filter_alt));
      expect(icon.color, DesignTokens.colorTextPrimary);
    });
  });

  group('active filter chips row', () {
    testWidgets('activeChips has 2 entries -> ActiveFilterChipsRow renders with both chips', (
      tester,
    ) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(
          entries: [_buildEntry(id: 'e1')],
          nextCursor: null,
          isLoadingMore: false,
          dateRange: DateRangeOption.thisWeek,
          entryTypes: const {EntrySource.audio},
        ),
      );

      expect(find.byType(ActiveFilterChipsRow), findsOneWidget);
      final row = tester.widget<ActiveFilterChipsRow>(find.byType(ActiveFilterChipsRow));
      expect(row.chips, hasLength(2));
    });

    testWidgets('no active criteria -> ActiveFilterChipsRow is absent', (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
      );

      expect(find.byType(ActiveFilterChipsRow), findsNothing);
    });
  });

  group('FR-009 — no-results-for-criteria view', () {
    testWidgets('isEmptyForCriteria == true -> NoResultsForCriteriaView renders, not '
        'RecordsEmptyState', (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(
          entries: const [],
          nextCursor: null,
          isLoadingMore: false,
          searchQuery: 'ansiedade',
        ),
      );

      expect(find.byType(NoResultsForCriteriaView), findsOneWidget);
      expect(find.byType(RecordsEmptyState), findsNothing);
    });

    testWidgets('a true zero-entries account with no active criteria renders '
        'RecordsEmptyState', (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: const [], nextCursor: null, isLoadingMore: false),
      );

      expect(find.byType(RecordsEmptyState), findsOneWidget);
      expect(find.byType(NoResultsForCriteriaView), findsNothing);
    });
  });

  group('offline note (prototype "Tela 4" offline note)', () {
    const offlineNote = 'Busca limitada ao que está salvo no aparelho.';

    testWidgets(
      'a pageLoadFailure that is NetworkOfflineFailure shows the note under '
      'the search bar',
      (tester) async {
        await pumpRecordsPage(
          tester,
          RecordsLoaded(
            entries: [_buildEntry(id: 'e1')],
            nextCursor: null,
            isLoadingMore: false,
            pageLoadFailure: const NetworkOfflineFailure(
              message: 'Sem conexão com a internet.',
              requestId: '',
            ),
          ),
        );

        expect(find.text(offlineNote), findsOneWidget);
      },
    );

    testWidgets(
      'the offline note is left-aligned under the search bar, not centered',
      (tester) async {
        await pumpRecordsPage(
          tester,
          RecordsLoaded(
            entries: [_buildEntry(id: 'e1')],
            nextCursor: null,
            isLoadingMore: false,
            pageLoadFailure: const NetworkOfflineFailure(
              message: 'Sem conexão com a internet.',
              requestId: '',
            ),
          ),
        );

        final noteLeft = tester.getTopLeft(find.text(offlineNote)).dx;
        final searchFieldLeft = tester.getTopLeft(find.byType(TextField)).dx;
        expect(noteLeft, searchFieldLeft);
      },
    );

    testWidgets(
      'a pageLoadFailure that is NOT NetworkOfflineFailure does not show the '
      'offline note, and never shows the raw failure message in its place',
      (tester) async {
        await pumpRecordsPage(
          tester,
          RecordsLoaded(
            entries: [_buildEntry(id: 'e1')],
            nextCursor: null,
            isLoadingMore: false,
            pageLoadFailure: const NetworkTimeoutFailure(
              message: 'A conexão demorou demais. Tente novamente.',
              requestId: '',
            ),
          ),
        );

        expect(find.text(offlineNote), findsNothing);
      },
    );

    testWidgets('no active failure -> the offline note is absent', (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
      );

      expect(find.text(offlineNote), findsNothing);
    });
  });
}
