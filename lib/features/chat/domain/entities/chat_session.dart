import 'package:equatable/equatable.dart';

/// The agent persona snapshot stored on a session at creation time. Read-only
/// here (FR-014) — this unit never writes it back; no UI to change it.
enum ChatPersona { analitico, empatico, socratico }

/// The shape of both `chat-sessions-create`'s and `chat-sessions-list`'s
/// response (data-model.md). Every field is `required` in the OpenAPI
/// schema, mirroring `Entry`'s own precedent (RF01).
class ChatSession extends Equatable {
  const ChatSession({
    required this.id,
    required this.title,
    required this.personaSnapshot,
    required this.userMessageCount,
    required this.lastUserMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ChatPersona personaSnapshot;
  final int userMessageCount;

  /// Nullable per schema; in practice always non-null once listed
  /// (spec.md Key Entities).
  final DateTime? lastUserMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    title,
    personaSnapshot,
    userMessageCount,
    lastUserMessageAt,
    createdAt,
    updatedAt,
  ];
}
