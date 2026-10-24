import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/export/domain/repositories/export_file_repository.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/presentation/bloc/export_bloc.dart';
import 'package:cerne/features/export/presentation/widgets/export_sheet.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:cerne/features/records/presentation/pages/records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockRecordsBloc extends MockBloc<RecordsEvent, RecordsState> implements RecordsBloc {}

class MockExportRepository extends Mock implements ExportRepository {}

class MockExportFileRepository extends Mock implements ExportFileRepository {}

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
  late MockRecordsBloc recordsBloc;
  late MockExportRepository exportRepository;
  late MockExportFileRepository exportFileRepository;

  setUpAll(() {
    registerFallbackValue(const SearchTextChanged(''));
  });

  setUp(() {
    recordsBloc = MockRecordsBloc();
    when(() => recordsBloc.reauthRequired).thenAnswer((_) => const Stream.empty());
    when(() => recordsBloc.close()).thenAnswer((_) async {});

    exportRepository = MockExportRepository();
    exportFileRepository = MockExportFileRepository();
    // create() never resolves — this test only needs ExportSheet to
    // construct and mount successfully with the right constructor args; it
    // never needs the export flow to actually complete.
    when(
      () => exportRepository.create(
        periodStart: any(named: 'periodStart'),
        periodEnd: any(named: 'periodEnd'),
      ),
    ).thenAnswer((_) => Completer<Either<Failure, String>>().future);

    if (getIt.isRegistered<ExportBloc>()) getIt.unregister<ExportBloc>();
    getIt.registerFactory<ExportBloc>(
      () => ExportBloc(exportRepository: exportRepository, exportFileRepository: exportFileRepository),
    );
  });

  tearDown(() {
    if (getIt.isRegistered<ExportBloc>()) getIt.unregister<ExportBloc>();
  });

  Future<void> pumpRecordsPage(WidgetTester tester, RecordsState state) async {
    whenListen(recordsBloc, Stream.value(state), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RecordsBloc>.value(value: recordsBloc, child: const RecordsPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    '1: thisWeek -> ExportSheet constructed with periodEnd: null and '
    'periodStart equal to this week\'s most-recent-Monday boundary',
    (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(
          entries: [_buildEntry(id: 'e1')],
          nextCursor: null,
          isLoadingMore: false,
          dateRange: DateRangeOption.thisWeek,
        ),
      );

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();

      final expectedBounds = DateRangeOption.thisWeek.boundsAt(DateTime.now());
      final sheet = tester.widget<ExportSheet>(find.byType(ExportSheet));
      expect(sheet.periodStart, expectedBounds.from);
      expect(sheet.periodEnd, isNull);
    },
  );

  testWidgets(
    '2: allTime -> ExportSheet constructed with periodStart: null, periodEnd: null',
    (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
      );

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();

      final sheet = tester.widget<ExportSheet>(find.byType(ExportSheet));
      expect(sheet.periodStart, isNull);
      expect(sheet.periodEnd, isNull);
    },
  );

  testWidgets(
    '3: a rapid double-tap on the download icon calls showModalBottomSheet exactly once',
    (tester) async {
      await pumpRecordsPage(
        tester,
        RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
      );

      await tester.tap(find.byIcon(Icons.download_outlined));
      // The second tap lands on the modal barrier the first tap's sheet is
      // already raising — exactly the guarded no-op FR-011 requires.
      await tester.tap(find.byIcon(Icons.download_outlined), warnIfMissed: false);
      await tester.pump();

      expect(find.byType(ExportSheet), findsOneWidget);
    },
  );

  testWidgets('4: sheet dismissed, download icon tapped again -> a fresh sheet opens', (
    tester,
  ) async {
    await pumpRecordsPage(
      tester,
      RecordsLoaded(entries: [_buildEntry(id: 'e1')], nextCursor: null, isLoadingMore: false),
    );

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(find.byType(ExportSheet), findsOneWidget);

    // Dismiss programmatically rather than tapping "Fechar" directly: the
    // sheet's entrance animation and ExportPendingView's own indeterminate
    // spinner (which animates forever) make tap-position-based interaction
    // on the sheet's content unreliable in a widget test.
    Navigator.of(tester.element(find.byType(ExportSheet))).pop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExportSheet), findsNothing);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(find.byType(ExportSheet), findsOneWidget);
  });

  testWidgets(
    '5: opening/closing the export sheet leaves RecordsBloc\'s own state untouched',
    (tester) async {
      final seeded = RecordsLoaded(
        entries: [_buildEntry(id: 'e1')],
        nextCursor: null,
        isLoadingMore: false,
      );
      await pumpRecordsPage(tester, seeded);

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();
      Navigator.of(tester.element(find.byType(ExportSheet))).pop();
      await tester.pump(const Duration(milliseconds: 300));

      verifyNever(() => recordsBloc.add(any()));
      expect(recordsBloc.state, seeded);
    },
  );
}
