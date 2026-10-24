import 'dart:convert';

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/error_mapper.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/network/sse_frame.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_sessions_page.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/entities/insight_trigger.dart';
import 'package:fpdart/fpdart.dart';

const _malformedChatFailure = ValidationFailure(
  message: 'Malformed chat response',
  requestId: '',
);

/// The only class that calls `ApiClient.call('chat-sessions-create'/
/// 'chat-sessions-list'/'chat-messages-list', ...)` /
/// `ApiClient.sseStream('chat-messages-send'/'chat-messages-retry', ...)` and
/// parses the [ChatSession]/[ChatMessage]/[ChatStreamEvent] response shapes
/// (data-model.md, contracts/chat-repository.md).
class ChatRemoteDataSource {
  const ChatRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, ChatSession>> createSession({
    required String title,
  }) async {
    final result = await _apiClient.call(
      'chat-sessions-create',
      method: 'POST',
      body: {'title': title},
    );
    return result.flatMap(_parseSession);
  }

  Future<Either<Failure, ChatSessionsPage>> listSessions({
    String? cursor,
    int? limit,
  }) async {
    final queryParameters = <String, String>{
      'cursor': ?cursor,
      'limit': ?limit?.toString(),
    };
    final result = await _apiClient.call(
      'chat-sessions-list',
      method: 'GET',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
      unwrapData: false,
    );
    return result.flatMap(_parseSessionsPage);
  }

  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async {
    final result = await _apiClient.call(
      'chat-messages-list',
      method: 'GET',
      pathSegments: [sessionId],
      unwrapData: false,
    );
    return result.flatMap(_parseMessagesList);
  }

  Stream<Either<Failure, ChatStreamEvent>> sendMessage({
    required String sessionId,
    required String content,
  }) {
    return _apiClient
        .sseStream(
          'chat-messages-send',
          method: 'POST',
          pathSegments: [sessionId],
          body: {'content': content},
        )
        .map(_mapFrame)
        .where((e) => e != null)
        .cast<Either<Failure, ChatStreamEvent>>();
  }

  Stream<Either<Failure, ChatStreamEvent>> retryMessage({
    required String sessionId,
    required String userMessageId,
  }) {
    return _apiClient
        .sseStream(
          'chat-messages-retry',
          method: 'POST',
          pathSegments: [sessionId, userMessageId],
          body: const {},
        )
        .map(_mapFrame)
        .where((e) => e != null)
        .cast<Either<Failure, ChatStreamEvent>>();
  }

  /// `null` for a frame this app ignores outright (`context`, research.md
  /// R2); every other frame maps 1:1 to a [ChatStreamEvent] or, for the
  /// backend-named `error` event, to `Left`.
  Either<Failure, ChatStreamEvent>? _mapFrame(
    Either<Failure, SseFrame> frameResult,
  ) {
    return frameResult.match(
      (failure) => Left(failure),
      (frame) {
        try {
          final decoded = jsonDecode(frame.data) as Map<String, dynamic>;
          return switch (frame.event) {
            'message_created' => Right(
              MessageCreated(
                userMessageId: decoded['userMessageId'] as String,
                assistantMessageId: decoded['assistantMessageId'] as String,
              ),
            ),
            'context' => null,
            // Backend wire format (contracts/zod/chat.ts): the token event's
            // field is `text`, not `delta`, and `done` carries only
            // `assistantMessageId`/`finishReason` — no `content`/`createdAt`.
            // The client finalizes the message from its own locally
            // accumulated token text instead (`ChatBloc._completeMessage`).
            'token' => Right(TokenReceived(decoded['text'] as String)),
            'done' => Right(
              StreamDone(
                assistantMessageId: decoded['assistantMessageId'] as String,
              ),
            ),
            'error' => Left(ErrorMapper.fromResponse(decoded)),
            _ => null,
          };
        } on TypeError {
          return const Left(_malformedChatFailure);
        } on FormatException {
          return const Left(_malformedChatFailure);
        }
      },
    );
  }

  Either<Failure, ChatSession> _parseSession(Map<String, dynamic> data) {
    try {
      return Right(_parseSessionFields(data));
    } on TypeError {
      return const Left(_malformedChatFailure);
    } on FormatException {
      return const Left(_malformedChatFailure);
    }
  }

  // `chat-sessions-list`'s full response body is `{"data": [...], "meta":
  // {"nextCursor": ...}}` — `ApiClient.call(..., unwrapData: false)` returns
  // it verbatim since the inner "data" here is an array, not an object.
  Either<Failure, ChatSessionsPage> _parseSessionsPage(
    Map<String, dynamic> body,
  ) {
    try {
      final sessions = (body['data'] as List<dynamic>)
          .map((s) => _parseSessionFields(s as Map<String, dynamic>))
          .toList();
      final meta = body['meta'] as Map<String, dynamic>;
      return Right(
        ChatSessionsPage(
          sessions: sessions,
          nextCursor: meta['nextCursor'] as String?,
        ),
      );
    } on TypeError {
      return const Left(_malformedChatFailure);
    } on FormatException {
      return const Left(_malformedChatFailure);
    }
  }

  Either<Failure, List<ChatMessage>> _parseMessagesList(
    Map<String, dynamic> body,
  ) {
    try {
      final messages = (body['data'] as List<dynamic>)
          .map((m) => _parseMessageFields(m as Map<String, dynamic>))
          .toList();
      return Right(messages);
    } on TypeError {
      return const Left(_malformedChatFailure);
    } on FormatException {
      return const Left(_malformedChatFailure);
    }
  }

  ChatSession _parseSessionFields(Map<String, dynamic> data) => ChatSession(
    id: data['id'] as String,
    title: data['title'] as String,
    personaSnapshot: ChatPersona.values.byName(
      data['personaSnapshot'] as String,
    ),
    userMessageCount: data['userMessageCount'] as int,
    lastUserMessageAt: (data['lastUserMessageAt'] as String?) == null
        ? null
        : DateTime.parse(data['lastUserMessageAt'] as String),
    createdAt: DateTime.parse(data['createdAt'] as String),
    updatedAt: DateTime.parse(data['updatedAt'] as String),
  );

  Future<Either<Failure, String>> createInsight({
    required String sessionId,
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) async {
    final result = await _apiClient.call(
      'chat-insight-create',
      method: 'POST',
      pathSegments: [sessionId],
      body: {'triggerType': _wireTriggerType(triggerType), 'triggerKey': triggerKey},
    );
    return result.flatMap(_parseInsightContent);
  }

  String _wireTriggerType(InsightTriggerType type) => switch (type) {
    InsightTriggerType.messageCount => 'message_count',
    InsightTriggerType.inactivity => 'inactivity',
  };

  // research.md R7 — collapses the 200-response `status: 'failed'` outcome
  // into the same `Left` channel every transport failure already uses.
  Either<Failure, String> _parseInsightContent(Map<String, dynamic> data) {
    try {
      if ((data['status'] as String?) == 'ready') {
        return Right(data['content'] as String);
      }
      return Left(
        ErrorMapper.fromResponse({
          'code': data['errorCode'],
          'message': 'Proactive insight generation failed',
          'requestId': data['id'],
        }),
      );
    } on TypeError {
      return const Left(_malformedChatFailure);
    }
  }

  ChatMessage _parseMessageFields(Map<String, dynamic> data) => ChatMessage(
    id: data['id'] as String,
    sessionId: data['sessionId'] as String,
    role: ChatRole.values.byName(data['role'] as String),
    content: data['content'] as String,
    seq: data['seq'] as int,
    status: ChatMessageStatus.values.byName(data['status'] as String),
    retryCount: data['retryCount'] as int,
    createdAt: DateTime.parse(data['createdAt'] as String),
  );
}
