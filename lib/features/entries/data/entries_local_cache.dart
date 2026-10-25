import 'dart:convert';

import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// On-device, cross-restart persistence for the entries the user has
/// already seen (the PRD's "local read cache" — requirements.md line 50/125:
/// results from it stay visible offline and reconcile with the server on
/// reconnect, with no duplicates). Keychain-backed, same pattern as
/// `VaultSecureStorage` — journal content is personal data, so it stays
/// encrypted at rest like the PIN it already sits behind.
///
/// Distinct from `EntriesRepositoryImpl`'s in-memory `cachedEntries`: that
/// field only ever held optimistic just-created entries for this process's
/// lifetime (research.md R8, 003-multimodal-capture). This class is what
/// makes that same list survive an app restart, which is what a cold open
/// on an already-offline device needs (closing snapshot at unit completion
/// did not cover this path — see Meus Registros intervention report).
class EntriesLocalCache {
  EntriesLocalCache({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'entriesLocalCache';

  Future<List<Entry>> readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> writeAll(List<Entry> entries) {
    final encoded = jsonEncode(entries.map(_toJson).toList());
    return _storage.write(key: _key, value: encoded);
  }

  /// Deletes this cache's one key — part of account deletion's "any other
  /// locally held user data" clear (FR-019, research.md R9).
  Future<void> clear() => _storage.delete(key: _key);

  Map<String, dynamic> _toJson(Entry e) => {
    'id': e.id,
    'content': e.content,
    'source': e.source.name,
    'chatMessageId': e.chatMessageId,
    'occurredAt': e.occurredAt.toUtc().toIso8601String(),
    'tags': [
      for (final tag in e.tags) {'id': tag.id, 'name': tag.name},
    ],
    'piiStatus': e.piiStatus.name,
    'piiSpans': [
      for (final span in e.piiSpans)
        {'start': span.start, 'end': span.end, 'type': span.type},
    ],
    'embeddingStatus': e.embeddingStatus.name,
    'mediaDurationSeconds': e.mediaDurationSeconds,
    'serverRevision': e.serverRevision,
    'createdAt': e.createdAt.toUtc().toIso8601String(),
    'updatedAt': e.updatedAt.toUtc().toIso8601String(),
    'similarity': e.similarity,
  };

  Entry _fromJson(Map<String, dynamic> data) => Entry(
    id: data['id'] as String,
    content: data['content'] as String,
    source: EntrySource.values.byName(data['source'] as String),
    chatMessageId: data['chatMessageId'] as String?,
    occurredAt: DateTime.parse(data['occurredAt'] as String),
    tags: (data['tags'] as List<dynamic>)
        .map(
          (t) => EntryTag(
            id: (t as Map<String, dynamic>)['id'] as String,
            name: t['name'] as String,
          ),
        )
        .toList(),
    piiStatus: PiiStatus.values.byName(data['piiStatus'] as String),
    piiSpans: (data['piiSpans'] as List<dynamic>)
        .map(
          (s) => PiiSpan(
            start: (s as Map<String, dynamic>)['start'] as int,
            end: s['end'] as int,
            type: s['type'] as String,
          ),
        )
        .toList(),
    embeddingStatus: EmbeddingStatus.values.byName(
      data['embeddingStatus'] as String,
    ),
    mediaDurationSeconds: data['mediaDurationSeconds'] as int?,
    serverRevision: data['serverRevision'] as int,
    createdAt: DateTime.parse(data['createdAt'] as String),
    updatedAt: DateTime.parse(data['updatedAt'] as String),
    similarity: (data['similarity'] as num?)?.toDouble(),
  );
}
