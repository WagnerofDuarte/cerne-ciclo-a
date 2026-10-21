# Contract: `ChatSessionsBloc` (`lib/features/chat/presentation/bloc/chat_sessions_bloc.dart`)

Directly mirrors `RecordsBloc`'s own first-page/next-page/retry shape (RF07), narrowed to one call
(`ChatRepository.listSessions`) with no search/filter axis. Depends only on `ChatRepository` — never
`ChatBloc`, `SessionBloc`, or `ConnectivityChecker` (research.md R7).

```dart
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
}
```

## `SessionsStarted` / `SessionsRefreshRequested` — both load page 1 (research.md R7)

```dart
Future<void> _onStarted(SessionsStarted event, Emitter<ChatSessionsState> emit) async {
  emit(const ChatSessionsLoading());
  await _loadFirstPage(emit);
}

Future<void> _onRefreshRequested(SessionsRefreshRequested event, Emitter<ChatSessionsState> emit) async {
  // Unlike _onStarted, never regresses a populated ChatSessionsLoaded back to ChatSessionsLoading —
  // the drawer's existing list stays visible while a fresh page 1 loads underneath it.
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
        emit(ChatSessionsLoaded(sessions: cached, nextCursor: null, isLoadingMore: false));
      }
    },
    (page) => emit(ChatSessionsLoaded(sessions: page.sessions, nextCursor: page.nextCursor, isLoadingMore: false)),
  );
}
```

## `SessionsNextPageRequested` (FR-008)

```dart
Future<void> _onNextPageRequested(SessionsNextPageRequested event, Emitter<ChatSessionsState> emit) async {
  final current = state;
  if (current is! ChatSessionsLoaded || current.hasReachedEnd || current.isLoadingMore) return;

  final generation = ++_fetchGeneration;
  emit(current.copyWith(isLoadingMore: true, pageLoadFailure: null));
  final result = await _chatRepository.listSessions(cursor: current.nextCursor);
  if (generation != _fetchGeneration) return;

  result.match(
    (failure) {
      if (failure is AuthExpiredFailure) {
        _reauthController.add(null);
        emit(current.copyWith(isLoadingMore: false));
      } else {
        emit(current.copyWith(isLoadingMore: false, pageLoadFailure: failure));
      }
    },
    (page) => emit(current.copyWith(
      sessions: [...current.sessions, ...page.sessions],
      nextCursor: page.nextCursor, isLoadingMore: false, pageLoadFailure: null,
    )),
  );
}
```

## `SessionsPageLoadRetried`

```dart
Future<void> _onPageLoadRetried(SessionsPageLoadRetried event, Emitter<ChatSessionsState> emit) async {
  final current = state;
  if (current is ChatSessionsLoadFailure) {
    await _loadFirstPage(emit);
  } else if (current is ChatSessionsLoaded && current.pageLoadFailure != null) {
    add(const SessionsNextPageRequested());
  }
}
```

`close()`: closes `_reauthController` (no `Timer`/subscription to cancel here — simpler than `RecordsBloc`'s
own `close()`, since this bloc has no debounce and no live connectivity subscription of its own).

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `SessionsStarted` with a successful first page | `ChatSessionsLoaded(sessions: [...], nextCursor: <backend's own value>)` |
| 2 | `SessionsStarted` fails outright, nothing cached | `ChatSessionsLoadFailure(failure)` |
| 3 | `SessionsStarted` fails, but `cachedSessions` is non-empty (offline, previously fetched) | `ChatSessionsLoaded(sessions: <cached>, nextCursor: null)` — FR-011/Clarification 3 |
| 4 | `SessionsRefreshRequested` fired while `ChatSessionsLoaded` is already showing sessions, and the refresh itself fails | the existing `sessions` list is **not** cleared/replaced by this failure — stays exactly as it was (never regresses to `ChatSessionsLoading`/`ChatSessionsLoadFailure` once something is already shown) |
| 5 | `SessionsNextPageRequested` when `hasReachedEnd` is already `true` | no repository call |
| 6 | `SessionsNextPageRequested` succeeds | `sessions` grows by exactly the new page's items, no duplicates, `nextCursor` updated (SC-007) |
| 7 | A next-page fetch returns `AuthExpiredFailure` | `reauthRequired` fires; `sessions`/`nextCursor` unchanged, `isLoadingMore` resets to `false`, no `pageLoadFailure` (same "no visible disruption" rule `RecordsBloc._fetchNextPage` already follows) |
| 8 | Two `SessionsNextPageRequested` fired back-to-back before the first resolves | the second is a no-op while `isLoadingMore` is already `true` — exactly one in-flight next-page call at a time |
