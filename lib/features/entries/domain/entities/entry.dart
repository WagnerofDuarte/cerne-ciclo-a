import 'package:equatable/equatable.dart';

/// `chat` is RF10's own addition — this unit creates only these three
/// (research.md R8).
enum EntrySource { manual, audio, photo }

enum PiiStatus { pending, clean, flagged, failed }

enum EmbeddingStatus { pending, ready, failed }

class EntryTag extends Equatable {
  const EntryTag({required this.id, required this.name});

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

class PiiSpan extends Equatable {
  const PiiSpan({required this.start, required this.end, required this.type});

  final int start;
  final int end;
  final String type;

  @override
  List<Object?> get props => [start, end, type];
}

/// The full shape of `POST /entries`' response (data-model.md) — every field
/// is `required` in the OpenAPI schema on every response, so none is
/// optional to model here (research.md R8).
class Entry extends Equatable {
  const Entry({
    required this.id,
    required this.content,
    required this.source,
    required this.chatMessageId,
    required this.occurredAt,
    required this.tags,
    required this.piiStatus,
    required this.piiSpans,
    required this.embeddingStatus,
    required this.mediaDurationSeconds,
    required this.serverRevision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String content;
  final EntrySource source;
  final String? chatMessageId;
  final DateTime occurredAt;
  final List<EntryTag> tags;
  final PiiStatus piiStatus;
  final List<PiiSpan> piiSpans;
  final EmbeddingStatus embeddingStatus;
  final int? mediaDurationSeconds;
  final int serverRevision;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    content,
    source,
    chatMessageId,
    occurredAt,
    tags,
    piiStatus,
    piiSpans,
    embeddingStatus,
    mediaDurationSeconds,
    serverRevision,
    createdAt,
    updatedAt,
  ];
}
