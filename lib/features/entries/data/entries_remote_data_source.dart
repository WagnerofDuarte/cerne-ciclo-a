import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:fpdart/fpdart.dart';

/// The only class that calls `ApiClient.call('entries-create', ...)` and
/// parses the full [Entry] response shape (data-model.md,
/// contracts/entries-repository.md). Never sends
/// `occurredAt`/`mediaDurationSeconds`/`chatMessageId` in the request body.
class EntriesRemoteDataSource {
  const EntriesRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
  }) async {
    final result = await _apiClient.call(
      'entries-create',
      method: 'POST',
      body: {'content': content, 'source': source.name},
    );

    return result.flatMap(_parseEntry);
  }

  Either<Failure, Entry> _parseEntry(Map<String, dynamic> data) {
    try {
      final entry = Entry(
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
      );
      return Right(entry);
    } on TypeError {
      return const Left(
        ValidationFailure(message: 'Malformed entries response', requestId: ''),
      );
    } on FormatException {
      return const Left(
        ValidationFailure(message: 'Malformed entries response', requestId: ''),
      );
    }
  }
}
