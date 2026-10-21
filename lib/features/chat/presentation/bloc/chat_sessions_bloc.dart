import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The side menu's "CONVERSAS" list — paginated, offline-cached, directly
/// mirroring `RecordsBloc`'s own first-page/next-page/retry shape (RF07).
/// Depends only on `ChatRepository` — never `ChatBloc`, `SessionBloc`, or
/// `ConnectivityChecker` (research.md R7).
class ChatSessionsBloc extends Bloc<ChatSessionsEvent, ChatSessionsState> {
  ChatSessionsBloc({required ChatRepository chatRepository})
    : _chatRepository = chatRepository, // ignore: prefer_initializing_formals
      super(const ChatSessionsLoading()) {
    on<SessionsStarted>(_onStarted);
    on<SessionsRefreshRequested>(_onRefreshRequested);
    on<SessionsNextPageRequested>(_onNextPageRequested);
    on<SessionsPageLoadRetried>(_onPageLoadRetried);
  }

  final ChatRepository _chatRepository;
  final _reauthController = StreamController<void>.broadcast();
  int _fetchGeneration = 0;

  Stream<void> get reauthRequired => _reauthController.stream;

  Future<void> _onStarted(
    SessionsStarted event,
    Emitter<ChatSessionsState> emit,
  ) async {
    emit(const ChatSessionsLoading());
    await _loadFirstPage(emit);
  }

  Future<void> _onRefreshRequested(
    SessionsRefreshRequested event,
    Emitter<ChatSessionsState> emit,
  ) async {
    // Unlike _onStarted, never regresses a populated ChatSessionsLoaded back
    // to ChatSessionsLoading — the drawer's existing list stays visible
    // while a fresh page 1 loads underneath it.
    await _loadFirstPage(emit);
  }

  Future<void> _loadFirstPage(Emitter<ChatSessionsState> emit) async {
    final generation = ++_fetchGeneration;
    final result = await _chatRepository.listSessions();
    if (generation != _fetchGeneration) return;

    result.match(
      (failure) {
        final cached = _chatRepository.cachedSessions;
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        if (cached.isEmpty) {
          emit(ChatSessionsLoadFailure(failure));
        } else {
          emit(
            ChatSessionsLoaded(sessions: cached, nextCursor: null, isLoadingMore: false),
          );
        }
      },
      (page) => emit(
        ChatSessionsLoaded(
          sessions: page.sessions,
          nextCursor: page.nextCursor,
          isLoadingMore: false,
        ),
      ),
    );
  }

  Future<void> _onNextPageRequested(
    SessionsNextPageRequested event,
    Emitter<ChatSessionsState> emit,
  ) async {
    final current = state;
    if (current is! ChatSessionsLoaded || current.hasReachedEnd || current.isLoadingMore) {
      return;
    }

    final generation = ++_fetchGeneration;
    emit(current.copyWith(isLoadingMore: true, pageLoadFailure: null));
    final result = await _chatRepository.listSessions(cursor: current.nextCursor);
    if (generation != _fetchGeneration) return;

    result.match(
      (failure) {
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
          emit(current.copyWith(isLoadingMore: false, pageLoadFailure: null));
        } else {
          emit(current.copyWith(isLoadingMore: false, pageLoadFailure: failure));
        }
      },
      (page) => emit(
        current.copyWith(
          sessions: [...current.sessions, ...page.sessions],
          nextCursor: page.nextCursor,
          isLoadingMore: false,
          pageLoadFailure: null,
        ),
      ),
    );
  }

  Future<void> _onPageLoadRetried(
    SessionsPageLoadRetried event,
    Emitter<ChatSessionsState> emit,
  ) async {
    final current = state;
    if (current is ChatSessionsLoadFailure) {
      await _loadFirstPage(emit);
    } else if (current is ChatSessionsLoaded && current.pageLoadFailure != null) {
      add(const SessionsNextPageRequested());
    }
  }

  @override
  Future<void> close() {
    unawaited(_reauthController.close());
    return super.close();
  }
}
