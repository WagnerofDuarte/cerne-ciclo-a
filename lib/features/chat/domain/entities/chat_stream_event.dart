import 'package:equatable/equatable.dart';

/// The parsed shape of a `chat-messages-send`/`chat-messages-retry` SSE
/// stream's events (data-model.md). No `ErrorEvent` variant — both a
/// business-level `error` SSE frame and a transport-level `DioException`
/// become a `Left(Failure)` on the same `Stream<Either<Failure,
/// ChatStreamEvent>>` (research.md R1/R2), so callers only ever need one
/// failure-handling branch per stream.
sealed class ChatStreamEvent extends Equatable {
  const ChatStreamEvent();
}

class MessageCreated extends ChatStreamEvent {
  const MessageCreated({
    required this.userMessageId,
    required this.assistantMessageId,
  });

  final String userMessageId;
  final String assistantMessageId;

  @override
  List<Object?> get props => [userMessageId, assistantMessageId];
}

class ContextReceived extends ChatStreamEvent {
  const ContextReceived();

  @override
  List<Object?> get props => [];
}

class TokenReceived extends ChatStreamEvent {
  const TokenReceived(this.delta);

  final String delta;

  @override
  List<Object?> get props => [delta];
}

class StreamDone extends ChatStreamEvent {
  const StreamDone({required this.assistantMessageId});

  final String assistantMessageId;

  @override
  List<Object?> get props => [assistantMessageId];
}
