import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/domain/entities/entry_merger.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

/// The one bloc behind "Meus Registros" (contracts/records-bloc.md,
/// contracts/records-bloc-extension.md). Depends only on
/// `EntriesRepository` — never `SessionRepository`, `ConnectivityChecker`,
/// nor `SessionBloc` or any of its event/state types (research.md R4/R5/R11,
/// requirements.md RF07's own acceptance criterion).
class RecordsBloc extends Bloc<RecordsEvent, RecordsState> {
  // The public parameter names (`entriesRepository`/`debounceDuration`) must
  // stay underscore-free; an initializing formal would force the private
  // field names onto them instead.
  RecordsBloc({
    required EntriesRepository entriesRepository,
    Duration debounceDuration = const Duration(milliseconds: 300),
  }) : _entriesRepository = entriesRepository, // ignore: prefer_initializing_formals
       _debounceDuration = debounceDuration, // ignore: prefer_initializing_formals
       super(const RecordsLoading()) {
    on<RecordsStarted>(_onStarted);
    on<NextPageRequested>(_onNextPageRequested);
    on<PageLoadRetried>(_onPageLoadRetried);
    on<RecordsLocalCacheRefreshed>(_onLocalCacheRefreshed);
    on<SearchTextChanged>(_onSearchTextChanged);
    on<SearchDebounceElapsed>(_onSearchDebounceElapsed);
    on<FilterSheetApplied>(_onFilterSheetApplied);
    on<FilterChipRemoved>(_onFilterChipRemoved);
    on<FiltersAndSearchCleared>(_onFiltersAndSearchCleared);
    on<CriteriaLoadRetried>(_onCriteriaLoadRetried);
  }

  final EntriesRepository _entriesRepository;
  final Duration _debounceDuration;
  final _reauthController = StreamController<void>.broadcast();

  String _query = '';
  DateRangeOption _dateRange = DateRangeOption.allTime;
  Set<EntrySource> _entryTypes = {};
  Timer? _debounceTimer;
  int _fetchGeneration = 0;

  /// A one-shot side effect, not a state (research.md R5) —
  /// `RecordsPage` listens to this to raise the "Sessão expirada" overlay.
  Stream<void> get reauthRequired => _reauthController.stream;

  Future<void> _onStarted(RecordsStarted event, Emitter<RecordsState> emit) async {
    emit(const RecordsLoading());
    await _loadFirstPage(emit);
  }

  Future<void> _onPageLoadRetried(PageLoadRetried event, Emitter<RecordsState> emit) async {
    final current = state;
    if (current is RecordsLoadFailure) {
      emit(const RecordsLoading());
      await _loadFirstPage(emit);
    } else if (current is RecordsLoaded && current.pageLoadFailure != null) {
      await _fetchNextPage(current, emit);
    }
  }

  Future<void> _loadFirstPage(Emitter<RecordsState> emit) async {
    final result = await _entriesRepository.list();
    result.match(
      (failure) {
        // Offline (or any other outright) failure on the very first fetch —
        // no `RecordsLoaded` yet exists for `_fetchNextPage`/`_fetchForCriteria`
        // to simply leave untouched, so the on-device cache (populated by
        // any entry this app has ever fetched/created, EntriesLocalCache)
        // is the only thing that can stand in for it here. Falls through to
        // today's blank `RecordsLoadFailure` only when that cache is itself
        // empty (e.g. first-ever launch, already offline).
        final cached = EntryMerger.merge(
          primary: _entriesRepository.cachedEntries,
          secondary: const [],
        );
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
          if (cached.isEmpty) {
            emit(RecordsLoadFailure(failure));
          } else {
            // Mirrors `_fetchNextPage`'s own rule: reauth has its own
            // overlay, so no redundant inline banner here.
            emit(RecordsLoaded(entries: cached, nextCursor: null, isLoadingMore: false));
          }
        } else if (cached.isEmpty) {
          emit(RecordsLoadFailure(failure));
        } else {
          emit(
            RecordsLoaded(
              entries: cached,
              nextCursor: null,
              isLoadingMore: false,
              pageLoadFailure: failure,
            ),
          );
        }
      },
      (page) => emit(
        RecordsLoaded(
          entries: EntryMerger.merge(
            primary: page.entries,
            secondary: _entriesRepository.cachedEntries,
          ),
          nextCursor: page.nextCursor,
          isLoadingMore: false,
        ),
      ),
    );
  }

  Future<void> _onNextPageRequested(
    NextPageRequested event,
    Emitter<RecordsState> emit,
  ) async {
    final current = state;
    if (current is! RecordsLoaded || current.hasReachedEnd || current.isLoadingMore) {
      return;
    }
    await _fetchNextPage(current, emit);
  }

  Future<void> _fetchNextPage(RecordsLoaded current, Emitter<RecordsState> emit) async {
    final generation = ++_fetchGeneration;
    emit(current.copyWith(isLoadingMore: true, pageLoadFailure: null));

    final bounds = _dateRange.boundsAt(DateTime.now());
    final result = await _entriesRepository.list(
      cursor: current.nextCursor,
      source: _entryTypes.isEmpty ? null : _entryTypes.single,
      dateFrom: bounds.from,
      dateTo: bounds.to,
    );
    if (generation != _fetchGeneration) return;

    result.match(
      (failure) {
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
          // entries/cursor unchanged, isLoadingMore resets to false, no
          // pageLoadFailure — FR-007's "restored exactly as it was" holds
          // by construction.
          emit(current.copyWith(isLoadingMore: false, pageLoadFailure: null));
        } else {
          emit(current.copyWith(isLoadingMore: false, pageLoadFailure: failure));
        }
      },
      (page) => emit(
        current.copyWith(
          entries: EntryMerger.merge(
            primary: current.entries + page.entries,
            secondary: _entriesRepository.cachedEntries,
          ),
          nextCursor: page.nextCursor,
          isLoadingMore: false,
          pageLoadFailure: null,
        ),
      ),
    );
  }

  void _onLocalCacheRefreshed(
    RecordsLocalCacheRefreshed event,
    Emitter<RecordsState> emit,
  ) {
    final current = state;
    if (current is! RecordsLoaded || current.hasAnyActiveCriteria) return;
    emit(
      current.copyWith(
        entries: EntryMerger.merge(
          primary: current.entries,
          secondary: _entriesRepository.cachedEntries,
        ),
      ),
    );
  }

  // --- Search text -> debounce -> fetch (FR-001/FR-002, research.md R4/R6) ---

  Future<void> _onSearchTextChanged(SearchTextChanged event, Emitter<RecordsState> emit) async {
    _debounceTimer?.cancel();
    _query = event.text;
    if (event.text.isEmpty) {
      // Acceptance Scenario 3 / Edge Case: no request for empty text —
      // refetch immediately under whatever filters are still active.
      await _fetchForCriteria(emit);
      return;
    }
    _debounceTimer = Timer(
      _debounceDuration,
      () => add(SearchDebounceElapsed(event.text)),
    );
  }

  Future<void> _onSearchDebounceElapsed(
    SearchDebounceElapsed event,
    Emitter<RecordsState> emit,
  ) async {
    // Superseded by a newer keystroke/clear that arrived after the timer fired.
    if (event.text != _query) return;
    await _fetchForCriteria(emit);
  }

  // --- Filter sheet / chips / clear (FR-003/FR-005/FR-007, research.md R1/R6) ---

  Future<void> _onFilterSheetApplied(
    FilterSheetApplied event,
    Emitter<RecordsState> emit,
  ) async {
    _dateRange = event.dateRange;
    _entryTypes = event.entryTypes;
    await _fetchForCriteria(emit);
  }

  Future<void> _onFilterChipRemoved(
    FilterChipRemoved event,
    Emitter<RecordsState> emit,
  ) async {
    switch (event.chip) {
      case DateRangeChip():
        _dateRange = DateRangeOption.allTime;
      case EntryTypeChip(source: final s):
        _entryTypes = {..._entryTypes}..remove(s);
    }
    await _fetchForCriteria(emit);
  }

  Future<void> _onFiltersAndSearchCleared(
    FiltersAndSearchCleared event,
    Emitter<RecordsState> emit,
  ) async {
    _debounceTimer?.cancel();
    _query = '';
    _dateRange = DateRangeOption.allTime;
    _entryTypes = {};
    await _fetchForCriteria(emit);
  }

  Future<void> _onCriteriaLoadRetried(
    CriteriaLoadRetried event,
    Emitter<RecordsState> emit,
  ) async {
    // Re-attempts the exact same last-applied criteria (_query/_dateRange/_entryTypes).
    await _fetchForCriteria(emit);
  }

  // --- The core fetch (bounded-vs-paginated branch — research.md R1, generation guard — R6) ---

  Future<void> _fetchForCriteria(Emitter<RecordsState> emit) async {
    final generation = ++_fetchGeneration;
    final current = state;
    if (current is RecordsLoaded) {
      emit(
        current.copyWith(
          isApplyingCriteria: true,
          searchQuery: _query,
          dateRange: _dateRange,
          entryTypes: _entryTypes,
        ),
      );
    }
    // Nothing to show yet (still on RecordsLoading/RecordsLoadFailure) —
    // RecordsStarted's own _loadFirstPage() owns the very first fetch; this
    // path is only reachable once a RecordsLoaded exists.

    final bounds = _dateRange.boundsAt(DateTime.now());
    final result = await _resolveEntries(
      query: _query,
      dateFrom: bounds.from,
      dateTo: bounds.to,
      types: _entryTypes,
    );
    if (generation != _fetchGeneration) return; // superseded — discard silently (FR-005a)

    result.match(
      (failure) {
        final latest = state;
        if (latest is! RecordsLoaded) return;
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
          // entries/criteria unchanged, no criteriaLoadFailure — same
          // "no visible disruption" rule _fetchNextPage already follows.
          emit(latest.copyWith(isApplyingCriteria: false));
        } else {
          emit(latest.copyWith(isApplyingCriteria: false, criteriaLoadFailure: failure));
        }
      },
      (fetched) {
        final latest = state;
        if (latest is! RecordsLoaded) return;
        emit(
          latest.copyWith(
            entries: fetched.entries,
            nextCursor: fetched.nextCursor, // null whenever bounded (R1)
            isApplyingCriteria: false,
            criteriaLoadFailure: null,
          ),
        );
      },
    );
  }

  /// Picks the shape (single call+cursor vs. bounded fan-out-and-merge) per
  /// research.md R1.
  Future<Either<Failure, ({List<Entry> entries, String? nextCursor})>> _resolveEntries({
    required String query,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required Set<EntrySource> types,
  }) async {
    if (types.length <= 1) {
      final source = types.isEmpty ? null : types.single;
      if (query.isNotEmpty) {
        final result = await _entriesRepository.search(
          q: query,
          source: source,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
        return result.map((entries) => (entries: entries, nextCursor: null));
      }
      final result = await _entriesRepository.list(
        source: source,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      return result.map((page) => (entries: page.entries, nextCursor: page.nextCursor));
    }

    // 2+ entry types — bounded fan-out, one call per type (research.md R1).
    final calls = types.map(
      (source) => query.isNotEmpty
          ? _entriesRepository.search(q: query, source: source, dateFrom: dateFrom, dateTo: dateTo)
          : _entriesRepository
                .list(source: source, dateFrom: dateFrom, dateTo: dateTo, limit: 50)
                .then((r) => r.map((page) => page.entries)),
    );
    final results = await Future.wait(calls);
    for (final r in results) {
      if (r.isLeft()) {
        return r.map((_) => (entries: <Entry>[], nextCursor: null));
      }
    }
    final merged = EntryMerger.mergeMany(
      sources: [for (final r in results) r.getOrElse((_) => [])],
      byRelevance: query.isNotEmpty,
    );
    return Right((entries: merged, nextCursor: null));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    unawaited(_reauthController.close());
    return super.close();
  }
}
