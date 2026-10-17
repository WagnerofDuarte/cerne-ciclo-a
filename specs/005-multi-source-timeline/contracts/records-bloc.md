# Contract: `RecordsBloc` (`lib/features/records/presentation/bloc/records_bloc.dart`)

The one bloc behind "Meus Registros." Depends only on `EntriesRepository` (domain interface) — never
`SessionRepository`, `ConnectivityChecker`, nor (critically, requirements.md RF07's own acceptance criterion)
`SessionBloc` or any of its event/state types.

```dart
class RecordsBloc extends Bloc<RecordsEvent, RecordsState> {
  RecordsBloc({required this._entriesRepository}) : super(RecordsLoading()) {
    on<RecordsStarted>(_onStarted);
    on<NextPageRequested>(_onNextPageRequested);
    on<PageLoadRetried>(_onPageLoadRetried);
    on<RecordsLocalCacheRefreshed>(_onLocalCacheRefreshed);
  }

  final EntriesRepository _entriesRepository;
  final _reauthController = StreamController<void>.broadcast();
  Stream<void> get reauthRequired => _reauthController.stream;
}
```

## `_onStarted` / `_onPageLoadRetried` (first page)

```dart
Future<void> _onStarted(RecordsStarted event, Emitter<RecordsState> emit) async {
  emit(RecordsLoading());
  await _loadFirstPage(emit);
}

Future<void> _onPageLoadRetried(PageLoadRetried event, Emitter<RecordsState> emit) async {
  final current = state;
  if (current is RecordsLoadFailure) {
    emit(RecordsLoading());
    await _loadFirstPage(emit);
  } else if (current is RecordsLoaded && current.pageLoadFailure != null) {
    await _fetchNextPage(current, emit);   // retries the same unconsumed cursor
  }
}

Future<void> _loadFirstPage(Emitter<RecordsState> emit) async {
  final result = await _entriesRepository.list();
  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) _reauthController.add(null);   // research.md R5 — fires regardless
      emit(RecordsLoadFailure(failure));                                 // never the empty state (data-model.md)
    },
    (page) => emit(RecordsLoaded(
      entries: EntryMerger.merge(primary: page.entries, secondary: _entriesRepository.cachedEntries),
      nextCursor: page.nextCursor,
      isLoadingMore: false,
    )),
  );
}
```

## `_onNextPageRequested` (further pages)

```dart
Future<void> _onNextPageRequested(NextPageRequested event, Emitter<RecordsState> emit) async {
  final current = state;
  if (current is! RecordsLoaded || current.hasReachedEnd || current.isLoadingMore) return;
  await _fetchNextPage(current, emit);
}

Future<void> _fetchNextPage(RecordsLoaded current, Emitter<RecordsState> emit) async {
  emit(RecordsLoaded(
    entries: current.entries, nextCursor: current.nextCursor, isLoadingMore: true,
  ));
  final result = await _entriesRepository.list(cursor: current.nextCursor);
  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) {
        _reauthController.add(null);
        // entries/cursor unchanged, isLoadingMore resets to false, no pageLoadFailure — FR-007
        emit(RecordsLoaded(entries: current.entries, nextCursor: current.nextCursor, isLoadingMore: false));
      } else {
        emit(RecordsLoaded(
          entries: current.entries, nextCursor: current.nextCursor,
          isLoadingMore: false, pageLoadFailure: failure,   // retryable banner, entries untouched (FR-009)
        ));
      }
    },
    (page) => emit(RecordsLoaded(
      entries: EntryMerger.merge(primary: current.entries + page.entries, secondary: _entriesRepository.cachedEntries),
      nextCursor: page.nextCursor,
      isLoadingMore: false,
    )),
  );
}
```

- If the fetched page is itself empty but `nextCursor` is non-null (Edge Cases — "most recent page of entries
  is itself empty... paging continues to load those older groups"), this still emits a normal `RecordsLoaded`
  with no new entries added and the new `nextCursor` carried forward — `RecordsPage`'s `ScrollController`
  listener simply requests the *next* page too, since `hasReachedEnd` is still `false`.
- Reaching the true end (`nextCursor: null`) just stops future `NextPageRequested` dispatch (`hasReachedEnd`
  guard above) — "no error, no 'end of list' case to treat as a failure" (Edge Cases) is satisfied by there
  being no distinct state for it at all.

## `_onLocalCacheRefreshed` (research.md R10 — after the insertion modal closes)

```dart
void _onLocalCacheRefreshed(RecordsLocalCacheRefreshed event, Emitter<RecordsState> emit) {
  final current = state;
  if (current is! RecordsLoaded) return;   // nothing to merge into before the first page even loads
  emit(RecordsLoaded(
    entries: EntryMerger.merge(primary: current.entries, secondary: _entriesRepository.cachedEntries),
    nextCursor: current.nextCursor, isLoadingMore: current.isLoadingMore,
    pageLoadFailure: current.pageLoadFailure,
  ));
}
```

No network call — purely re-reads `EntriesRepository.cachedEntries` (already updated by `CreateEntryUseCase`
by the time the modal's `showModalBottomSheet` future resolves) and re-merges (FR-004, SC-001).

## `close()`

```dart
@override
Future<void> close() {
  unawaited(_reauthController.close());
  return super.close();
}
```

## `RecordsPage`'s responsibilities (presentation, not part of the bloc — this is where `SessionBloc` is imported)

```dart
class _RecordsPageState extends State<RecordsPage> {
  late final StreamSubscription<void> _reauthSubscription;
  final _scrollController = ScrollController();   // never recreated — preserves scroll position (FR-003/FR-007)

  @override
  void initState() {
    super.initState();
    _reauthSubscription = context.read<RecordsBloc>().reauthRequired.listen((_) {
      context.read<SessionBloc>().add(const AuthExpiredDetected());   // the only cross-bloc touch point — lives in a widget, not a BLoC
    });
    _scrollController.addListener(_maybeRequestNextPage);
  }

  void _maybeRequestNextPage() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<RecordsBloc>().add(const NextPageRequested());
    }
  }

  Future<void> _openEmptyStateCreate(BuildContext context) async {
    await openInsertionModal(context);   // research.md R10 — shared with Home/Chat's "+"
    if (mounted) context.read<RecordsBloc>().add(const RecordsLocalCacheRefreshed());
  }
}
```

## Test scenarios this contract owns (for `/speckit-tasks` to schedule)

| # | Scenario | Expected |
|---|---|---|
| 1 | `RecordsStarted`, repository returns a page | `RecordsLoaded` with merged/deduped entries, `isLoadingMore: false` |
| 2 | `RecordsStarted`, repository fails (non-auth) | `RecordsLoadFailure`, `reauthRequired` does **not** fire |
| 3 | `RecordsStarted`, repository fails `AuthExpiredFailure` | `RecordsLoadFailure` **and** `reauthRequired` fires exactly once |
| 4 | `NextPageRequested` while `hasReachedEnd` | no-op, no state emitted |
| 5 | `NextPageRequested` while `isLoadingMore` | no-op (no duplicate concurrent fetch) |
| 6 | `NextPageRequested` succeeds | entries appended, not replaced; existing entries' identity preserved |
| 7 | `NextPageRequested` fails `AuthExpiredFailure` | entries/`nextCursor` unchanged, `pageLoadFailure` stays `null`, `reauthRequired` fires |
| 8 | `NextPageRequested` fails (non-auth) | entries unchanged, `pageLoadFailure` set, `reauthRequired` does not fire |
| 9 | `PageLoadRetried` from `RecordsLoadFailure` | re-attempts the first page |
| 10 | `PageLoadRetried` from a `pageLoadFailure` | re-attempts the same `nextCursor`, not a reload |
| 11 | `RecordsLocalCacheRefreshed` after a local `create()` | the newly cached entry appears, deduped if also later re-fetched |
| 12 | Fetched page is empty but `nextCursor` non-null | emits normally; no transition to an empty-account display |
| 13 | A fetched page contains a `chat`-sourced entry | renders without throwing (depends on research.md R2) |

Architecture check (requirements.md RF07's own acceptance criterion, verified by a new
`test/architecture/no_bloc_imports_bloc_test.dart` for `/speckit-tasks` to schedule): no file under any
`presentation/bloc/` folder imports another feature's `presentation/bloc/` path. `records_bloc.dart` must pass
this; `records_page.dart` (not a bloc file) is exempt and is exactly where the one sanctioned
`SessionBloc`/`AuthExpiredDetected` import lives.
