import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/records/domain/entities/entry_merger.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/bloc/records_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The one bloc behind "Meus Registros" (contracts/records-bloc.md). Depends
/// only on `EntriesRepository` — never `SessionRepository`,
/// `ConnectivityChecker`, nor `SessionBloc` or any of its event/state types
/// (research.md R4/R5/R11, requirements.md RF07's own acceptance criterion).
class RecordsBloc extends Bloc<RecordsEvent, RecordsState> {
  RecordsBloc({required this._entriesRepository}) : super(const RecordsLoading()) {
    on<RecordsStarted>(_onStarted);
    on<NextPageRequested>(_onNextPageRequested);
    on<PageLoadRetried>(_onPageLoadRetried);
    on<RecordsLocalCacheRefreshed>(_onLocalCacheRefreshed);
  }

  final EntriesRepository _entriesRepository;
  final _reauthController = StreamController<void>.broadcast();

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
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        emit(RecordsLoadFailure(failure));
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
    emit(
      RecordsLoaded(
        entries: current.entries,
        nextCursor: current.nextCursor,
        isLoadingMore: true,
      ),
    );
    final result = await _entriesRepository.list(cursor: current.nextCursor);
    result.match(
      (failure) {
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
          // entries/cursor unchanged, isLoadingMore resets to false, no
          // pageLoadFailure — FR-007's "restored exactly as it was" holds
          // by construction.
          emit(
            RecordsLoaded(
              entries: current.entries,
              nextCursor: current.nextCursor,
              isLoadingMore: false,
            ),
          );
        } else {
          emit(
            RecordsLoaded(
              entries: current.entries,
              nextCursor: current.nextCursor,
              isLoadingMore: false,
              pageLoadFailure: failure,
            ),
          );
        }
      },
      (page) => emit(
        RecordsLoaded(
          entries: EntryMerger.merge(
            primary: current.entries + page.entries,
            secondary: _entriesRepository.cachedEntries,
          ),
          nextCursor: page.nextCursor,
          isLoadingMore: false,
        ),
      ),
    );
  }

  void _onLocalCacheRefreshed(
    RecordsLocalCacheRefreshed event,
    Emitter<RecordsState> emit,
  ) {
    final current = state;
    if (current is! RecordsLoaded) return;
    emit(
      RecordsLoaded(
        entries: EntryMerger.merge(
          primary: current.entries,
          secondary: _entriesRepository.cachedEntries,
        ),
        nextCursor: current.nextCursor,
        isLoadingMore: current.isLoadingMore,
        pageLoadFailure: current.pageLoadFailure,
      ),
    );
  }

  @override
  Future<void> close() {
    unawaited(_reauthController.close());
    return super.close();
  }
}
