import 'package:equatable/equatable.dart';

/// `chat` exists here even though no capture flow in this unit ever produces
/// one — `GET /entries` is origin-agnostic and can return a `chat`-sourced
/// entry (e.g., from seed/test data) before RF04/RF10 (the features that
/// will eventually create one) exist, so parsing must recognize all four
/// values rather than throwing on the fourth (research.md R2).
enum EntrySource { manual, audio, photo, chat }

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
    this.similarity,
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

  /// 0.0–1.0, only ever non-null when parsed from `entries-search`'s
  /// response (data-model.md).
  final double? similarity;

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
    similarity,
  ];
}
