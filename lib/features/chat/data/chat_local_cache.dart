import 'dart:convert';

import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// On-device, cross-restart persistence for chat (research.md R4) —
/// Keychain-backed, same pattern `EntriesLocalCache` already establishes.
/// Four **independent** storage keys so one write never clobbers another.
class ChatLocalCache {
  ChatLocalCache({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _sessionsKey = 'chatSessionsLocalCache';
  static const _messagesKey = 'chatMessagesLocalCache';
  static const _lastActiveKey = 'chatLastActiveSessionId';
  static const _savedMessageEntryIdsKey = 'chatSavedMessageEntryIds';

  Future<List<ChatSession>> readSessions() async {
    final raw = await _storage.read(key: _sessionsKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => _sessionFromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> writeSessions(List<ChatSession> sessions) {
    final encoded = jsonEncode(sessions.map(_sessionToJson).toList());
    return _storage.write(key: _sessionsKey, value: encoded);
  }

  Future<Map<String, List<ChatMessage>>> readAllMessages() async {
    final raw = await _storage.read(key: _messagesKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (sessionId, messages) => MapEntry(
          sessionId,
          (messages as List<dynamic>)
              .map((m) => _messageFromJson(m as Map<String, dynamic>))
              .toList(),
        ),
      );
    } on FormatException {
      return const {};
    } on TypeError {
      return const {};
    }
  }

  Future<void> writeMessagesForSession(
    String sessionId,
    List<ChatMessage> messages,
  ) async {
    final all = await readAllMessages();
    final updated = {...all, sessionId: messages};
    final encoded = jsonEncode(
      updated.map(
        (sid, msgs) => MapEntry(sid, msgs.map(_messageToJson).toList()),
      ),
    );
    await _storage.write(key: _messagesKey, value: encoded);
  }

  Future<String?> readLastActiveSessionId() {
    return _storage.read(key: _lastActiveKey);
  }

  Future<void> writeLastActiveSessionId(String? sessionId) {
    if (sessionId == null) {
      return _storage.delete(key: _lastActiveKey);
    }
    return _storage.write(key: _lastActiveKey, value: sessionId);
  }

  Future<Map<String, String>> readSavedMessageEntryIds() async {
    final raw = await _storage.read(key: _savedMessageEntryIdsKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } on FormatException {
      return const {};
    } on TypeError {
      return const {};
    }
  }

  Future<void> writeSavedMessageEntryIds(Map<String, String> ids) {
    return _storage.write(key: _savedMessageEntryIdsKey, value: jsonEncode(ids));
  }

  Map<String, dynamic> _sessionToJson(ChatSession s) => {
    'id': s.id,
    'title': s.title,
    'personaSnapshot': s.personaSnapshot.name,
    'userMessageCount': s.userMessageCount,
    'lastUserMessageAt': s.lastUserMessageAt?.toUtc().toIso8601String(),
    'createdAt': s.createdAt.toUtc().toIso8601String(),
    'updatedAt': s.updatedAt.toUtc().toIso8601String(),
  };

  ChatSession _sessionFromJson(Map<String, dynamic> data) => ChatSession(
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

  Map<String, dynamic> _messageToJson(ChatMessage m) => {
    'id': m.id,
    'sessionId': m.sessionId,
    'role': m.role.name,
    'content': m.content,
    'seq': m.seq,
    'status': m.status.name,
    'retryCount': m.retryCount,
    'createdAt': m.createdAt.toUtc().toIso8601String(),
  };

  ChatMessage _messageFromJson(Map<String, dynamic> data) => ChatMessage(
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
