import 'dart:async';

import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/entities/chat_title_deriver.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

/// The Home/Chat screen's own live conversation — streaming, retry, lazy
/// session creation, composer gating (contracts/chat-bloc.md). Depends only
/// on `ChatRepository` + `ConnectivityChecker` — never `ChatSessionsBloc`
/// nor `SessionBloc` (research.md R7).
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required ChatRepository chatRepository,
    required ConnectivityChecker connectivityChecker,
  }) : _chatRepository = chatRepository, // ignore: prefer_initializing_formals
       _connectivityChecker = connectivityChecker, // ignore: prefer_initializing_formals
       super(const ChatLoading()) {
    on<ChatStarted>(_onStarted);
    on<ConversationSelected>(_onConversationSelected);
    on<NewConversationRequested>(_onNewConversationRequested);
    on<MessageSubmitted>(_onMessageSubmitted);
    on<MessageRetryRequested>(_onMessageRetryRequested);
    on<ChatConnectivityChanged>(_onConnectivityChanged);
    _connectivitySubscription = connectivityChecker.onConnectivityChanged.listen(
      (isOnline) => add(ChatConnectivityChanged(isOnline)),
    );
  }

  final ChatRepository _chatRepository;
  final ConnectivityChecker _connectivityChecker;
  late final StreamSubscription<bool> _connectivitySubscription;
  final _reauthController = StreamController<void>.broadcast();

  /// Guards against a resolved/superseded turn's late emit (defensive,
  /// research.md R9) — bumped on every new turn and on every conversation
  /// switch/new-conversation request.
  int _turnGeneration = 0;

  /// A one-shot side effect, not a state (research.md R3/R7) —
  /// `HomeChatShellPage` listens to this to raise the "Sessão expirada"
  /// overlay.
  Stream<void> get reauthRequired => _reauthController.stream;

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    final isOnline = await _connectivityChecker.hasConnection();
    final lastId = await _chatRepository.lastActiveSessionId;
    if (lastId == null) {
      emit(
        ChatReady(
          sessionId: null,
          messages: const [],
          isOffline: !isOnline,
          awaitingResponse: false,
        ),
      );
      return;
    }
    await _loadSession(lastId, emit, isOffline: !isOnline);
  }

  Future<void> _onConversationSelected(
    ConversationSelected event,
    Emitter<ChatState> emit,
  ) async {
    _turnGeneration++;
    final isOnline = await _connectivityChecker.hasConnection();
    await _loadSession(event.sessionId, emit, isOffline: !isOnline);
  }

  Future<void> _onNewConversationRequested(
    NewConversationRequested event,
    Emitter<ChatState> emit,
  ) async {
    _turnGeneration++;
    final current = state;
    final isOffline = current is ChatReady ? current.isOffline : false;
    await _chatRepository.setLastActiveSessionId(null);
    emit(
      ChatReady(
        sessionId: null,
        messages: const [],
        isOffline: isOffline,
        awaitingResponse: false,
      ),
    );
  }

  void _onConnectivityChanged(
    ChatConnectivityChanged event,
    Emitter<ChatState> emit,
  ) {
    final current = state;
    if (current is! ChatReady) return;
    emit(current.copyWith(isOffline: !event.isOnline));
  }

  /// The shared fetch-with-cache-fallback path (Clarification 3).
  Future<void> _loadSession(
    String sessionId,
    Emitter<ChatState> emit, {
    required bool isOffline,
  }) async {
    final result = await _chatRepository.listMessages(sessionId);
    await result.match(
      (failure) async {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        final cached = _chatRepository.cachedMessages(sessionId);
        if (cached == null) {
          // Never opened while online — the "standard no-connection state"
          // instead of any content (Edge Cases).
          emit(
            ChatReady(
              sessionId: sessionId,
              messages: const [],
              isOffline: isOffline,
              awaitingResponse: false,
              loadFailure: failure,
            ),
          );
        } else {
          emit(
            ChatReady(
              sessionId: sessionId,
              messages: cached,
              isOffline: isOffline,
              awaitingResponse: false,
            ),
          );
        }
      },
      (messages) async {
        await _chatRepository.setLastActiveSessionId(sessionId);
        emit(
          ChatReady(
            sessionId: sessionId,
            messages: messages,
            isOffline: isOffline,
            awaitingResponse: false,
          ),
        );
      },
    );
  }

  Future<void> _onMessageSubmitted(
    MessageSubmitted event,
    Emitter<ChatState> emit,
  ) async {
    final current = state;
    if (current is! ChatReady || !current.canSend) return;

    if (!await _connectivityChecker.hasConnection()) {
      // FR-012 — blocked client-side, never attempted. The composer's own
      // isOffline flag (R8's live stream) reflects this on its own shortly.
      return;
    }

    final generation = ++_turnGeneration;
    final now = DateTime.now();
    final optimisticUser = ChatMessage(
      id: 'local-${now.microsecondsSinceEpoch}',
      sessionId: current.sessionId ?? '',
      role: ChatRole.user,
      content: event.text,
      seq: current.messages.length,
      status: ChatMessageStatus.complete,
      retryCount: 0,
      createdAt: now,
    );
    final optimisticAssistant = ChatMessage(
      id: 'local-${now.microsecondsSinceEpoch}-response',
      sessionId: current.sessionId ?? '',
      role: ChatRole.assistant,
      content: '',
      seq: current.messages.length + 1,
      status: ChatMessageStatus.streaming,
      retryCount: 0,
      createdAt: now,
    );
    emit(
      current.copyWith(
        messages: [...current.messages, optimisticUser, optimisticAssistant],
        awaitingResponse: true,
      ),
    );

    String sessionId;
    if (current.sessionId == null) {
      final created = await _chatRepository.createSession(
        title: ChatTitleDeriver.derive(event.text),
      );
      if (generation != _turnGeneration) return;
      final maybeId = created.match((_) => null, (s) => s.id);
      if (maybeId == null) {
        final failure = created.getLeft().toNullable()!;
        _failTurn(emit, optimisticAssistant.id, failure);
        return;
      }
      sessionId = maybeId;
      await _chatRepository.setLastActiveSessionId(sessionId);
    } else {
      sessionId = current.sessionId!;
    }

    final stream = _chatRepository.sendMessage(
      sessionId: sessionId,
      content: event.text,
    );
    await _consumeTurn(
      stream,
      emit,
      generation: generation,
      sessionId: sessionId,
      optimisticUserId: optimisticUser.id,
      optimisticAssistantId: optimisticAssistant.id,
    );
  }

  Future<void> _onMessageRetryRequested(
    MessageRetryRequested event,
    Emitter<ChatState> emit,
  ) async {
    final current = state;
    if (current is! ChatReady || current.awaitingResponse) {
      return;
    }
    final index = current.messages.indexWhere(
      (m) =>
          m.role == ChatRole.assistant &&
          m.status == ChatMessageStatus.failed &&
          _userMessageIdFor(current.messages, m) == event.userMessageId,
    );
    if (index == -1) return;
    if (!await _connectivityChecker.hasConnection()) return; // FR-012

    final userMessage = current.messages[index - 1];
    if (userMessage.isOptimistic) {
      // The turn's very first `createSession` call failed (FR-006) — there
      // is no persisted session/message yet for `retryMessage` to target, so
      // re-run the same lazy-creation path `_onMessageSubmitted` takes.
      await _retryLazySessionCreation(current, index, userMessage, emit);
      return;
    }
    if (current.sessionId == null) return;

    final generation = ++_turnGeneration;
    final now = DateTime.now();
    final placeholder = ChatMessage(
      id: 'local-${now.microsecondsSinceEpoch}-retry',
      sessionId: current.sessionId!,
      role: ChatRole.assistant,
      content: '',
      seq: current.messages[index].seq,
      status: ChatMessageStatus.streaming,
      retryCount: current.messages[index].retryCount + 1,
      createdAt: now,
    );
    final updatedMessages = [...current.messages];
    updatedMessages[index] = placeholder;
    emit(current.copyWith(messages: updatedMessages, awaitingResponse: true));

    final stream = _chatRepository.retryMessage(
      sessionId: current.sessionId!,
      userMessageId: event.userMessageId,
    );
    await _consumeTurn(
      stream,
      emit,
      generation: generation,
      sessionId: current.sessionId!,
      optimisticUserId: null,
      optimisticAssistantId: placeholder.id,
    );
  }

  /// Retries a turn whose lazy `createSession` call (FR-010) itself failed
  /// before any session ever existed — reuses `createSession` +
  /// `sendMessage` with the original user message's own content, exactly as
  /// `_onMessageSubmitted` does for a brand-new conversation.
  Future<void> _retryLazySessionCreation(
    ChatReady current,
    int index,
    ChatMessage userMessage,
    Emitter<ChatState> emit,
  ) async {
    final generation = ++_turnGeneration;
    final now = DateTime.now();
    final placeholder = ChatMessage(
      id: 'local-${now.microsecondsSinceEpoch}-retry',
      sessionId: userMessage.sessionId,
      role: ChatRole.assistant,
      content: '',
      seq: current.messages[index].seq,
      status: ChatMessageStatus.streaming,
      retryCount: current.messages[index].retryCount + 1,
      createdAt: now,
    );
    final updatedMessages = [...current.messages];
    updatedMessages[index] = placeholder;
    emit(current.copyWith(messages: updatedMessages, awaitingResponse: true));

    final created = await _chatRepository.createSession(
      title: ChatTitleDeriver.derive(userMessage.content),
    );
    if (generation != _turnGeneration) return;
    final maybeId = created.match((_) => null, (s) => s.id);
    if (maybeId == null) {
      final failure = created.getLeft().toNullable()!;
      _failTurn(emit, placeholder.id, failure);
      return;
    }
    await _chatRepository.setLastActiveSessionId(maybeId);

    final latest = state;
    if (latest is! ChatReady || generation != _turnGeneration) return;
    emit(latest.copyWith(sessionId: maybeId));

    final stream = _chatRepository.sendMessage(
      sessionId: maybeId,
      content: userMessage.content,
    );
    await _consumeTurn(
      stream,
      emit,
      generation: generation,
      sessionId: maybeId,
      optimisticUserId: userMessage.id,
      optimisticAssistantId: placeholder.id,
    );
  }

  /// Shared `emit.forEach`-driven stream consumption for both a fresh send
  /// and a retry.
  Future<void> _consumeTurn(
    Stream<Either<Failure, ChatStreamEvent>> stream,
    Emitter<ChatState> emit, {
    required int generation,
    required String sessionId,
    required String? optimisticUserId,
    required String optimisticAssistantId,
  }) async {
    var assistantId = optimisticAssistantId;
    await emit.forEach<Either<Failure, ChatStreamEvent>>(
      stream,
      onData: (result) {
        final latest = state;
        if (generation != _turnGeneration || latest is! ChatReady) {
          return latest;
        }
        return result.match((failure) {
          if (failure is AuthExpiredFailure) _reauthController.add(null);
          return _applyFailure(latest, assistantId, failure);
        }, (event) => switch (event) {
          MessageCreated() => () {
            assistantId = event.assistantMessageId;
            return _reconcileIds(
              latest,
              optimisticUserId,
              event.userMessageId,
              optimisticAssistantId,
              event.assistantMessageId,
            );
          }(),
          ContextReceived() => latest,
          TokenReceived(delta: final d) => _appendToken(latest, assistantId, d),
          StreamDone(assistantMessageId: final id) =>
            _completeMessage(latest, id).copyWith(awaitingResponse: false),
        });
      },
    );
    await _reconcileSilentFailure(emit, sessionId, assistantId, generation);
  }

  /// A failure yielded as (or before) the stream's very first item leaves the
  /// bubble `failed` with empty content even though the backend may have
  /// kept generating in the background and already persisted the full
  /// answer by the time the stream closed (e.g. a transient network drop
  /// right after `message_created`, before any token arrives). One
  /// best-effort refetch here closes that gap without needing the user to
  /// leave and come back. Only acts on an empty-content failure — a failure
  /// after partial tokens (FR-005) is left exactly as the stream reported
  /// it. Note this is a best-effort recovery for a genuinely slow backend,
  /// not a substitute for parsing the stream correctly in the first place —
  /// it loses the race whenever the backend is still generating (slow/live
  /// answers can take several seconds longer than this one refetch waits
  /// for).
  Future<void> _reconcileSilentFailure(
    Emitter<ChatState> emit,
    String sessionId,
    String assistantId,
    int generation,
  ) async {
    final seeded = state;
    if (seeded is! ChatReady || generation != _turnGeneration) return;
    final index = seeded.messages.indexWhere((m) => m.id == assistantId);
    if (index == -1) return;
    final message = seeded.messages[index];
    if (message.status != ChatMessageStatus.failed || message.content.isNotEmpty) {
      return;
    }

    final result = await _chatRepository.listMessages(sessionId);
    if (generation != _turnGeneration) return;
    result.match((_) {}, (serverMessages) {
      ChatMessage? persisted;
      for (final m in serverMessages) {
        if (m.role == ChatRole.assistant && m.seq == message.seq) {
          persisted = m;
          break;
        }
      }
      final resolved = persisted;
      if (resolved == null ||
          resolved.status != ChatMessageStatus.complete ||
          resolved.content.isEmpty) {
        return;
      }
      final latest = state;
      if (latest is! ChatReady || generation != _turnGeneration) return;
      final updated = [
        for (final m in latest.messages) if (m.id == assistantId) resolved else m,
      ];
      emit(latest.copyWith(messages: updated));
    });
  }

  void _failTurn(
    Emitter<ChatState> emit,
    String assistantId,
    Failure failure,
  ) {
    final latest = state;
    if (latest is! ChatReady) return;
    emit(_applyFailure(latest, assistantId, failure));
  }

  /// `null` for a retry's `userMessageId` — a retry never targets an
  /// optimistic question, only an already-persisted one.
  ChatReady _reconcileIds(
    ChatReady current,
    String? optimisticUserId,
    String realUserId,
    String optimisticAssistantId,
    String realAssistantId,
  ) {
    final updated = [
      for (final m in current.messages)
        if (optimisticUserId != null && m.id == optimisticUserId)
          _withId(m, realUserId)
        else if (m.id == optimisticAssistantId)
          _withId(m, realAssistantId)
        else
          m,
    ];
    return current.copyWith(messages: updated);
  }

  ChatMessage _withId(ChatMessage message, String id) => ChatMessage(
    id: id,
    sessionId: message.sessionId,
    role: message.role,
    content: message.content,
    seq: message.seq,
    status: message.status,
    retryCount: message.retryCount,
    createdAt: message.createdAt,
  );

  ChatReady _appendToken(ChatReady current, String assistantId, String delta) {
    final updated = [
      for (final m in current.messages)
        if (m.id == assistantId) _withContent(m, m.content + delta) else m,
    ];
    return current.copyWith(messages: updated);
  }

  // The backend's `done` SSE event carries no authoritative `content`
  // (contracts/zod/chat.ts's `sseDoneEventSchema` has only
  // `assistantMessageId`/`finishReason`) — the message's own content, built
  // up from this turn's `TokenReceived` deltas, is already the full answer.
  ChatReady _completeMessage(ChatReady current, String assistantId) {
    final updated = [
      for (final m in current.messages)
        if (m.id == assistantId) _withStatus(m, ChatMessageStatus.complete) else m,
    ];
    return current.copyWith(messages: updated);
  }

  /// Keeps whatever partial `content` had already accumulated — never
  /// removed, hidden, or blanked (FR-005).
  ChatReady _applyFailure(
    ChatReady current,
    String assistantId,
    Failure failure,
  ) {
    final updated = [
      for (final m in current.messages)
        if (m.id == assistantId) _withStatus(m, ChatMessageStatus.failed) else m,
    ];
    return current.copyWith(messages: updated, awaitingResponse: false);
  }

  ChatMessage _withContent(ChatMessage message, String content) => ChatMessage(
    id: message.id,
    sessionId: message.sessionId,
    role: message.role,
    content: content,
    seq: message.seq,
    status: message.status,
    retryCount: message.retryCount,
    createdAt: message.createdAt,
  );

  ChatMessage _withStatus(ChatMessage message, ChatMessageStatus status) =>
      ChatMessage(
        id: message.id,
        sessionId: message.sessionId,
        role: message.role,
        content: message.content,
        seq: message.seq,
        status: status,
        retryCount: message.retryCount,
        createdAt: message.createdAt,
      );

  /// Position-matching (research.md R10) — the id of the user message
  /// immediately preceding [message] in [messages], or `null` if it isn't
  /// immediately preceded by one.
  String? _userMessageIdFor(List<ChatMessage> messages, ChatMessage message) {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index <= 0) return null;
    final preceding = messages[index - 1];
    return preceding.role == ChatRole.user ? preceding.id : null;
  }

  @override
  Future<void> close() {
    unawaited(_connectivitySubscription.cancel());
    unawaited(_reauthController.close());
    return super.close();
  }
}
