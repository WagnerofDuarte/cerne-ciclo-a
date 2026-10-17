import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
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

  RecordsBloc buildBloc() => RecordsBloc(entriesRepository: entriesRepository);

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
}
