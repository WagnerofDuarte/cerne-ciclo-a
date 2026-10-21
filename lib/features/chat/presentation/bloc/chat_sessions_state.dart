import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:equatable/equatable.dart';

sealed class ChatSessionsState extends Equatable {
  const ChatSessionsState();

  @override
  List<Object?> get props => [];
}

class ChatSessionsLoading extends ChatSessionsState {
  const ChatSessionsLoading();
}

class ChatSessionsLoadFailure extends ChatSessionsState {
  const ChatSessionsLoadFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

class ChatSessionsLoaded extends ChatSessionsState {
  const ChatSessionsLoaded({
    required this.sessions,
    required this.nextCursor,
    required this.isLoadingMore,
    this.pageLoadFailure,
  });

  final List<ChatSession> sessions;
  final String? nextCursor;
  final bool isLoadingMore;

  /// A further-page fetch failed; [sessions] stays intact, retryable.
  final Failure? pageLoadFailure;

  bool get hasReachedEnd => nextCursor == null;

  static const _unset = Object();

  ChatSessionsLoaded copyWith({
    List<ChatSession>? sessions,
    Object? nextCursor = _unset,
    bool? isLoadingMore,
    Object? pageLoadFailure = _unset,
  }) {
    return ChatSessionsLoaded(
      sessions: sessions ?? this.sessions,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      pageLoadFailure: identical(pageLoadFailure, _unset)
          ? this.pageLoadFailure
          : pageLoadFailure as Failure?,
    );
  }

  @override
  List<Object?> get props => [sessions, nextCursor, isLoadingMore, pageLoadFailure];
}
