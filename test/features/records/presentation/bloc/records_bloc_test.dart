import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/domain/entities/sync_badge_state.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockEntriesRepository extends Mock implements EntriesRepository {}

Entry _buildEntry({
  required String id,
  DateTime? occurredAt,
  EntrySource source = EntrySource.manual,
  double? similarity,
}) => Entry(
  id: id,
  content: 'content-$id',
  source: source,
  chatMessageId: null,
  occurredAt: occurredAt ?? DateTime(2026, 1, 1),
  tags: const [],
  piiStatus: PiiStatus.pending,
  piiSpans: const [],
  embeddingStatus: EmbeddingStatus.pending,
  mediaDurationSeconds: null,
  serverRevision: 1,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  similarity: similarity,
);

void main() {
  late MockEntriesRepository entriesRepository;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    entriesRepository = MockEntriesRepository();
    when(() => entriesRepository.cachedEntries).thenReturn(const []);
  });

  RecordsBloc buildBloc({Duration debounceDuration = const Duration(milliseconds: 300)}) =>
      RecordsBloc(entriesRepository: entriesRepository, debounceDuration: debounceDuration);

  RecordsLoaded seededLoaded({
    List<Entry>? entries,
    String? nextCursor,
    String searchQuery = '',
    DateRangeOption dateRange = DateRangeOption.allTime,
    Set<EntrySource> entryTypes = const {},
  }) => RecordsLoaded(
    entries: entries ?? [_buildEntry(id: 'e1')],
    nextCursor: nextCursor,
    isLoadingMore: false,
    searchQuery: searchQuery,
    dateRange: dateRange,
    entryTypes: entryTypes,
  );

  group('RecordsStarted', () {
    blocTest<RecordsBloc, RecordsState>(
      'a successful list() emits RecordsLoaded with merged/deduped entries '
      'and isLoadingMore: false',
      setUp: () {
        final entry = _buildEntry(id: 'e1');
        when(
          () => entriesRepository.list(cursor: any(named: 'cursor')),
        ).thenAnswer((_) async => Right(EntriesPage(entries: [entry], nextCursor: 'c2')));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const RecordsStarted()),
      expect: () => [
        const RecordsLoading(),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['e1'])
            .having((s) => s.nextCursor, 'nextCursor', 'c2')
            .having((s) => s.isLoadingMore, 'isLoadingMore', false),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'a non-auth failure emits RecordsLoadFailure and reauthRequired does '
      'not fire',
      setUp: () {
        when(() => entriesRepository.list(cursor: any(named: 'cursor'))).thenAnswer(
          (_) async => const Left(NetworkTimeoutFailure(message: 'timed out', requestId: 'r1')),
        );
      },
      build: buildBloc,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const RecordsStarted());
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        await sub.cancel();
      },
      expect: () => [const RecordsLoading(), isA<RecordsLoadFailure>()],
    );

    blocTest<RecordsBloc, RecordsState>(
      'AuthExpiredFailure emits RecordsLoadFailure AND fires reauthRequired '
      'exactly once',
      setUp: () {
        when(() => entriesRepository.list(cursor: any(named: 'cursor'))).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
      },
      build: buildBloc,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const RecordsStarted());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      expect: () => [const RecordsLoading(), isA<RecordsLoadFailure>()],
    );

    blocTest<RecordsBloc, RecordsState>(
      'a non-auth failure, with entries already present in the on-device '
      'cache, emits RecordsLoaded from that cache with an inline retryable '
      'pageLoadFailure instead of a blank RecordsLoadFailure — the offline '
      'cold-open case (Meus Registros intervention report)',
      setUp: () {
        when(() => entriesRepository.list(cursor: any(named: 'cursor'))).thenAnswer(
          (_) async => const Left(NetworkOfflineFailure(message: 'Failed host lookup', requestId: 'r1')),
        );
        when(
          () => entriesRepository.cachedEntries,
        ).thenReturn([_buildEntry(id: 'cached-1')]);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const RecordsStarted()),
      expect: () => [
        const RecordsLoading(),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['cached-1'])
            .having((s) => s.nextCursor, 'nextCursor', null)
            .having((s) => s.pageLoadFailure, 'pageLoadFailure', isNotNull),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'AuthExpiredFailure, with entries already present in the on-device '
      'cache, emits RecordsLoaded from that cache with no pageLoadFailure '
      '(the reauth overlay is the only signal shown) and still fires '
      'reauthRequired',
      setUp: () {
        when(() => entriesRepository.list(cursor: any(named: 'cursor'))).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
        when(
          () => entriesRepository.cachedEntries,
        ).thenReturn([_buildEntry(id: 'cached-1')]);
      },
      build: buildBloc,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const RecordsStarted());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      expect: () => [
        const RecordsLoading(),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['cached-1'])
            .having((s) => s.pageLoadFailure, 'pageLoadFailure', isNull),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'a fetched page that is itself empty but carries a non-null nextCursor '
      'emits normally with no transition to an empty-account display',
      setUp: () {
        when(
          () => entriesRepository.list(cursor: any(named: 'cursor')),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: 'c2')));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const RecordsStarted()),
      expect: () => [
        const RecordsLoading(),
        isA<RecordsLoaded>()
            .having((s) => s.entries, 'entries', isEmpty)
            .having((s) => s.nextCursor, 'nextCursor', 'c2')
            .having((s) => s.hasReachedEnd, 'hasReachedEnd', false),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'a fetched page containing a chat-sourced entry renders without throwing',
      setUp: () {
        final chatEntry = _buildEntry(id: 'chat-1', source: EntrySource.chat);
        when(
          () => entriesRepository.list(cursor: any(named: 'cursor')),
        ).thenAnswer((_) async => Right(EntriesPage(entries: [chatEntry], nextCursor: null)));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const RecordsStarted()),
      expect: () => [
        const RecordsLoading(),
        isA<RecordsLoaded>().having(
          (s) => s.entries.single.source,
          'source',
          EntrySource.chat,
        ),
      ],
    );
  });

  group('NextPageRequested', () {
    RecordsLoaded loadedState({String? nextCursor, bool isLoadingMore = false}) => RecordsLoaded(
      entries: [_buildEntry(id: 'e1')],
      nextCursor: nextCursor,
      isLoadingMore: isLoadingMore,
    );

    blocTest<RecordsBloc, RecordsState>(
      'while hasReachedEnd is a no-op, no state emitted',
      build: buildBloc,
      seed: () => loadedState(nextCursor: null),
      act: (bloc) => bloc.add(const NextPageRequested()),
      expect: () => <RecordsState>[],
    );

    blocTest<RecordsBloc, RecordsState>(
      'while isLoadingMore is a no-op',
      build: buildBloc,
      seed: () => loadedState(nextCursor: 'c2', isLoadingMore: true),
      act: (bloc) => bloc.add(const NextPageRequested()),
      expect: () => <RecordsState>[],
    );

    blocTest<RecordsBloc, RecordsState>(
      'a successful fetch appends (never replaces) entries, preserving '
      'already-rendered entries\' identity',
      setUp: () {
        final e2 = _buildEntry(id: 'e2');
        when(
          () => entriesRepository.list(cursor: 'c2'),
        ).thenAnswer((_) async => Right(EntriesPage(entries: [e2], nextCursor: null)));
      },
      build: buildBloc,
      seed: () => loadedState(nextCursor: 'c2'),
      act: (bloc) => bloc.add(const NextPageRequested()),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isLoadingMore, 'isLoadingMore', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['e1', 'e2'])
            .having((s) => s.isLoadingMore, 'isLoadingMore', false),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'an AuthExpiredFailure leaves entries/nextCursor unchanged, pageLoadFailure '
      'stays null, isLoadingMore resets to false, and reauthRequired fires',
      setUp: () {
        when(() => entriesRepository.list(cursor: 'c2')).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
      },
      build: buildBloc,
      seed: () => loadedState(nextCursor: 'c2'),
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const NextPageRequested());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isLoadingMore, 'isLoadingMore', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['e1'])
            .having((s) => s.nextCursor, 'nextCursor', 'c2')
            .having((s) => s.isLoadingMore, 'isLoadingMore', false)
            .having((s) => s.pageLoadFailure, 'pageLoadFailure', isNull),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'a non-auth failure leaves entries unchanged, sets pageLoadFailure, and '
      'does not fire reauthRequired',
      setUp: () {
        when(() => entriesRepository.list(cursor: 'c2')).thenAnswer(
          (_) async => const Left(NetworkTimeoutFailure(message: 'timed out', requestId: 'r1')),
        );
      },
      build: buildBloc,
      seed: () => loadedState(nextCursor: 'c2'),
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const NextPageRequested());
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        await sub.cancel();
      },
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isLoadingMore, 'isLoadingMore', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['e1'])
            .having((s) => s.isLoadingMore, 'isLoadingMore', false)
            .having((s) => s.pageLoadFailure, 'pageLoadFailure', isNotNull),
      ],
    );
  });

  group('PageLoadRetried', () {
    blocTest<RecordsBloc, RecordsState>(
      'from RecordsLoadFailure re-attempts the first page',
      setUp: () {
        when(
          () => entriesRepository.list(cursor: any(named: 'cursor')),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: buildBloc,
      seed: () => const RecordsLoadFailure(
        NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'),
      ),
      act: (bloc) => bloc.add(const PageLoadRetried()),
      expect: () => [const RecordsLoading(), isA<RecordsLoaded>()],
    );

    blocTest<RecordsBloc, RecordsState>(
      'from a pageLoadFailure re-attempts the same nextCursor, not a reload',
      setUp: () {
        when(
          () => entriesRepository.list(cursor: 'c2'),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: buildBloc,
      seed: () => RecordsLoaded(
        entries: [_buildEntry(id: 'e1')],
        nextCursor: 'c2',
        isLoadingMore: false,
        pageLoadFailure: const NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'),
      ),
      act: (bloc) => bloc.add(const PageLoadRetried()),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isLoadingMore, 'isLoadingMore', true),
        isA<RecordsLoaded>().having((s) => s.pageLoadFailure, 'pageLoadFailure', isNull),
      ],
      verify: (_) {
        verify(() => entriesRepository.list(cursor: 'c2')).called(1);
        verifyNever(() => entriesRepository.list(cursor: null));
      },
    );
  });

  group('RecordsLocalCacheRefreshed', () {
    blocTest<RecordsBloc, RecordsState>(
      'a newly cachedEntries-held entry appears merged into entries, deduped '
      'by id if also later re-fetched',
      setUp: () {
        final cached = _buildEntry(id: 'local-1');
        when(() => entriesRepository.cachedEntries).thenReturn([cached]);
      },
      build: buildBloc,
      seed: () => RecordsLoaded(
        entries: [_buildEntry(id: 'e1')],
        nextCursor: null,
        isLoadingMore: false,
      ),
      act: (bloc) => bloc.add(const RecordsLocalCacheRefreshed()),
      expect: () => [
        isA<RecordsLoaded>().having(
          (s) => s.entries.map((e) => e.id).toSet(),
          'entry ids',
          {'e1', 'local-1'},
        ),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'dispatched while state is not RecordsLoaded is a no-op',
      build: buildBloc,
      act: (bloc) => bloc.add(const RecordsLocalCacheRefreshed()),
      expect: () => <RecordsState>[],
    );
  });

  group('User Story 4 — sync badge state-preservation under session trouble', () {
    blocTest<RecordsBloc, RecordsState>(
      'entries and every entry\'s derived badge state are unaffected by an '
      'AuthExpiredFailure page-fetch failure',
      setUp: () {
        when(() => entriesRepository.list(cursor: 'c2')).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
      },
      build: buildBloc,
      seed: () => RecordsLoaded(
        entries: [_buildEntry(id: 'e1')],
        nextCursor: 'c2',
        isLoadingMore: false,
      ),
      act: (bloc) => bloc.add(const NextPageRequested()),
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.entries.map((e) => e.id).toList(), ['e1']);
        expect(
          finalState.entries.map((e) => SyncBadge.derive(null)).toList(),
          [SyncBadgeState.synchronized],
        );
      },
    );
  });

  group('SearchTextChanged / SearchDebounceElapsed (debounce + supersession)', () {
    blocTest<RecordsBloc, RecordsState>(
      'SearchTextChanged("a"), "an", "ans" fired within the debounce window '
      '-> exactly one search() call, with the final text only',
      setUp: () {
        when(
          () => entriesRepository.search(
            q: any(named: 'q'),
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right([]));
      },
      build: () => buildBloc(debounceDuration: Duration.zero),
      seed: seededLoaded,
      act: (bloc) {
        bloc.add(const SearchTextChanged('a'));
        bloc.add(const SearchTextChanged('an'));
        bloc.add(const SearchTextChanged('ans'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verify(() => entriesRepository.search(q: 'ans', source: null, dateFrom: null, dateTo: null))
            .called(1);
        verifyNever(() => entriesRepository.search(q: 'a', source: null, dateFrom: null, dateTo: null));
        verifyNever(
          () => entriesRepository.search(q: 'an', source: null, dateFrom: null, dateTo: null),
        );
      },
    );

    blocTest<RecordsBloc, RecordsState>(
      'SearchTextChanged("a") then SearchTextChanged("") before the timer '
      'fires -> search() is never called; a filter-only/unfiltered refetch '
      'happens instead',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: () => buildBloc(debounceDuration: Duration.zero),
      seed: seededLoaded,
      act: (bloc) {
        bloc.add(const SearchTextChanged('a'));
        bloc.add(const SearchTextChanged(''));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verifyNever(
          () => entriesRepository.search(
            q: any(named: 'q'),
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        );
        verify(() => entriesRepository.list(source: null, dateFrom: null, dateTo: null)).called(1);
      },
    );
  });

  group('FilterSheetApplied', () {
    blocTest<RecordsBloc, RecordsState>(
      '1 entry type + a date range, no query -> a single list(source:, '
      'dateFrom:, dateTo:) call, cursor-paginated',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: EntrySource.audio,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async => Right(EntriesPage(entries: [_buildEntry(id: 'e2')], nextCursor: 'c2')),
        );
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) => bloc.add(
        const FilterSheetApplied(dateRange: DateRangeOption.thisWeek, entryTypes: {EntrySource.audio}),
      ),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isApplyingCriteria, 'isApplyingCriteria', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['e2'])
            .having((s) => s.nextCursor, 'nextCursor', 'c2')
            .having((s) => s.isApplyingCriteria, 'isApplyingCriteria', false),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      '2 entry types, no query -> two list() calls (one per type, limit: '
      '50), merged+deduped+sorted by occurredAt desc, nextCursor: null',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: EntrySource.audio,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
            limit: 50,
          ),
        ).thenAnswer(
          (_) async => Right(
            EntriesPage(
              entries: [_buildEntry(id: 'audio-1', occurredAt: DateTime(2026, 1, 2))],
              nextCursor: null,
            ),
          ),
        );
        when(
          () => entriesRepository.list(
            source: EntrySource.photo,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
            limit: 50,
          ),
        ).thenAnswer(
          (_) async => Right(
            EntriesPage(
              entries: [_buildEntry(id: 'photo-1', occurredAt: DateTime(2026, 1, 3))],
              nextCursor: null,
            ),
          ),
        );
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) => bloc.add(
        const FilterSheetApplied(
          dateRange: DateRangeOption.allTime,
          entryTypes: {EntrySource.audio, EntrySource.photo},
        ),
      ),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isApplyingCriteria, 'isApplyingCriteria', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entry ids', ['photo-1', 'audio-1'])
            .having((s) => s.nextCursor, 'nextCursor', isNull),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      '2 entry types + an active query -> two search() calls, '
      'merged+deduped+sorted by similarity desc',
      setUp: () {
        // The bloc's own "currently active query" is tracked internally and
        // only set by a dispatched SearchTextChanged/SearchDebounceElapsed —
        // seeding RecordsLoaded.searchQuery alone (a display mirror) does
        // not set it, so the initial debounce-triggered fetch (single-type,
        // no filter yet) must be stubbed too.
        when(
          () => entriesRepository.search(
            q: 'ansiedade',
            source: null,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right([]));
        when(
          () => entriesRepository.search(
            q: 'ansiedade',
            source: EntrySource.audio,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async => Right([_buildEntry(id: 'audio-1', similarity: 0.3)]),
        );
        when(
          () => entriesRepository.search(
            q: 'ansiedade',
            source: EntrySource.photo,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async => Right([_buildEntry(id: 'photo-1', similarity: 0.9)]),
        );
      },
      build: () => buildBloc(debounceDuration: Duration.zero),
      seed: seededLoaded,
      act: (bloc) async {
        bloc.add(const SearchTextChanged('ansiedade'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(
          const FilterSheetApplied(
            dateRange: DateRangeOption.allTime,
            entryTypes: {EntrySource.audio, EntrySource.photo},
          ),
        );
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.entries.map((e) => e.id).toList(), ['photo-1', 'audio-1']);
      },
    );

    blocTest<RecordsBloc, RecordsState>(
      'two FilterSheetApplied events fired back-to-back, the first '
      'repository call resolving after the second -> the first call\'s '
      'result never reaches emit; only the second renders (FR-005a)',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: EntrySource.audio,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Right(EntriesPage(entries: [_buildEntry(id: 'stale')], nextCursor: null));
        });
        when(
          () => entriesRepository.list(
            source: EntrySource.photo,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async => Right(EntriesPage(entries: [_buildEntry(id: 'fresh')], nextCursor: null)),
        );
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) async {
        bloc.add(
          const FilterSheetApplied(dateRange: DateRangeOption.allTime, entryTypes: {EntrySource.audio}),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          const FilterSheetApplied(dateRange: DateRangeOption.allTime, entryTypes: {EntrySource.photo}),
        );
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.entries.map((e) => e.id).toList(), ['fresh']);
      },
    );
  });

  group('FilterChipRemoved / FiltersAndSearchCleared', () {
    blocTest<RecordsBloc, RecordsState>(
      'FilterChipRemoved(DateRangeChip) -> dateRange resets to allTime, '
      'refetch fires with the remaining criteria only',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: buildBloc,
      seed: seededLoaded,
      // The bloc's own currently-applied dateRange is only set by a
      // dispatched FilterSheetApplied — establish it first, then remove it.
      act: (bloc) async {
        bloc.add(
          const FilterSheetApplied(dateRange: DateRangeOption.thisWeek, entryTypes: {}),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(const FilterChipRemoved(DateRangeChip(DateRangeOption.thisWeek)));
      },
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.dateRange, DateRangeOption.allTime);
        verify(() => entriesRepository.list(source: null, dateFrom: null, dateTo: null)).called(1);
      },
    );

    blocTest<RecordsBloc, RecordsState>(
      'FilterChipRemoved(EntryTypeChip(audio)) with {audio, photo} selected '
      '-> only audio is removed; refetch runs with {photo}',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: EntrySource.audio,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
            limit: 50,
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
        when(
          () => entriesRepository.list(
            source: EntrySource.photo,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
            limit: 50,
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
        when(
          () => entriesRepository.list(
            source: EntrySource.photo,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: buildBloc,
      seed: seededLoaded,
      // The bloc's own currently-applied entryTypes is only set by a
      // dispatched FilterSheetApplied — establish {audio, photo} first.
      act: (bloc) async {
        bloc.add(
          const FilterSheetApplied(
            dateRange: DateRangeOption.allTime,
            entryTypes: {EntrySource.audio, EntrySource.photo},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(const FilterChipRemoved(EntryTypeChip(EntrySource.audio)));
      },
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.entryTypes, {EntrySource.photo});
        verify(
          () => entriesRepository.list(source: EntrySource.photo, dateFrom: null, dateTo: null),
        ).called(1);
      },
    );

    blocTest<RecordsBloc, RecordsState>(
      'FiltersAndSearchCleared while a query + filters are active -> query/'
      'dateRange/entryTypes all reset; one refetch call with no criteria',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: buildBloc,
      seed: () => seededLoaded(
        searchQuery: 'ansiedade',
        dateRange: DateRangeOption.thisWeek,
        entryTypes: {EntrySource.audio},
      ),
      act: (bloc) => bloc.add(const FiltersAndSearchCleared()),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isApplyingCriteria, 'isApplyingCriteria', true),
        isA<RecordsLoaded>()
            .having((s) => s.searchQuery, 'searchQuery', '')
            .having((s) => s.dateRange, 'dateRange', DateRangeOption.allTime)
            .having((s) => s.entryTypes, 'entryTypes', isEmpty),
      ],
      verify: (_) {
        verify(() => entriesRepository.list(source: null, dateFrom: null, dateTo: null)).called(1);
      },
    );
  });

  group('Criteria-change failures and retry', () {
    blocTest<RecordsBloc, RecordsState>(
      'a non-auth criteria-change failure -> entries/criteria fields '
      'unchanged, criteriaLoadFailure set, isApplyingCriteria: false',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async =>
              const Left(NetworkTimeoutFailure(message: 'timed out', requestId: 'r1')),
        );
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) => bloc.add(const FiltersAndSearchCleared()),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isApplyingCriteria, 'isApplyingCriteria', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entries', ['e1'])
            .having((s) => s.isApplyingCriteria, 'isApplyingCriteria', false)
            .having((s) => s.criteriaLoadFailure, 'criteriaLoadFailure', isNotNull),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'an AuthExpiredFailure criteria-change failure -> reauthRequired '
      'fires, entries unchanged, criteriaLoadFailure stays null',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const FiltersAndSearchCleared());
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isApplyingCriteria, 'isApplyingCriteria', true),
        isA<RecordsLoaded>()
            .having((s) => s.entries.map((e) => e.id).toList(), 'entries', ['e1'])
            .having((s) => s.criteriaLoadFailure, 'criteriaLoadFailure', isNull),
      ],
    );

    blocTest<RecordsBloc, RecordsState>(
      'CriteriaLoadRetried after criteriaLoadFailure is set -> re-attempts '
      'with the same last-applied criteria',
      setUp: () {
        // The bloc's own currently-applied query is only set by a
        // dispatched SearchTextChanged — establish it via a first, failing
        // fetch, then verify the retry reuses that same query.
        var callCount = 0;
        when(
          () => entriesRepository.search(
            q: 'ansiedade',
            source: null,
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? const Left(NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'))
              : Right([_buildEntry(id: 'e2')]);
        });
      },
      build: () => buildBloc(debounceDuration: Duration.zero),
      seed: seededLoaded,
      act: (bloc) async {
        bloc.add(const SearchTextChanged('ansiedade'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const CriteriaLoadRetried());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.entries.map((e) => e.id).toList(), ['e2']);
        expect(finalState.criteriaLoadFailure, isNull);
        verify(
          () => entriesRepository.search(q: 'ansiedade', source: null, dateFrom: null, dateTo: null),
        ).called(2);
      },
    );

    blocTest<RecordsBloc, RecordsState>(
      'CriteriaLoadRetried succeeds after a prior criteriaLoadFailure, '
      'simulating reconnection, where some cached IDs also appear in the '
      'fresh response -> emitted entries equals the fresh response exactly, '
      'no duplicate ID (SC-006: a full replace, never a merge)',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer(
          (_) async => Right(
            EntriesPage(entries: [_buildEntry(id: 'e1'), _buildEntry(id: 'e3')], nextCursor: null),
          ),
        );
      },
      build: buildBloc,
      seed: () => RecordsLoaded(
        entries: [_buildEntry(id: 'e1'), _buildEntry(id: 'e2')],
        nextCursor: null,
        isLoadingMore: false,
        dateRange: DateRangeOption.thisWeek,
        criteriaLoadFailure: const NetworkOfflineFailure(message: 'no connection', requestId: 'r2'),
      ),
      act: (bloc) => bloc.add(const CriteriaLoadRetried()),
      verify: (bloc) {
        final finalState = bloc.state as RecordsLoaded;
        expect(finalState.entries.map((e) => e.id).toList(), ['e1', 'e3']);
        expect(finalState.entries.map((e) => e.id).toSet(), hasLength(2));
      },
    );
  });

  group('RecordsLocalCacheRefreshed — guarded while criteria active', () {
    blocTest<RecordsBloc, RecordsState>(
      'while hasAnyActiveCriteria is true -> no-op, state unchanged',
      setUp: () {
        when(() => entriesRepository.cachedEntries).thenReturn([_buildEntry(id: 'local-1')]);
      },
      build: buildBloc,
      seed: () => seededLoaded(searchQuery: 'ansiedade'),
      act: (bloc) => bloc.add(const RecordsLocalCacheRefreshed()),
      expect: () => <RecordsState>[],
    );

    blocTest<RecordsBloc, RecordsState>(
      'while no criteria active -> unchanged RF07 behavior, cachedEntries merged in',
      setUp: () {
        when(() => entriesRepository.cachedEntries).thenReturn([_buildEntry(id: 'local-1')]);
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) => bloc.add(const RecordsLocalCacheRefreshed()),
      expect: () => [
        isA<RecordsLoaded>().having(
          (s) => s.entries.map((e) => e.id).toSet(),
          'entry ids',
          {'e1', 'local-1'},
        ),
      ],
    );
  });

  group('FR-009 — zero-result criteria state', () {
    blocTest<RecordsBloc, RecordsState>(
      'a zero-result search/filter combination on a non-empty account '
      'yields isEmptyForCriteria: true',
      setUp: () {
        when(
          () => entriesRepository.list(
            source: any(named: 'source'),
            dateFrom: any(named: 'dateFrom'),
            dateTo: any(named: 'dateTo'),
          ),
        ).thenAnswer((_) async => const Right(EntriesPage(entries: [], nextCursor: null)));
      },
      build: buildBloc,
      seed: seededLoaded,
      act: (bloc) => bloc.add(
        const FilterSheetApplied(dateRange: DateRangeOption.thisMonth, entryTypes: {}),
      ),
      expect: () => [
        isA<RecordsLoaded>().having((s) => s.isApplyingCriteria, 'isApplyingCriteria', true),
        isA<RecordsLoaded>().having((s) => s.isEmptyForCriteria, 'isEmptyForCriteria', true),
      ],
    );
  });
}
