import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:fpdart/fpdart.dart';

const _malformedEntriesFailure = ValidationFailure(
  message: 'Malformed entries response',
  requestId: '',
);

/// The only class that calls `ApiClient.call('entries-create'/'entries-list'/
/// 'entries-get', ...)` and parses the [Entry]/[EntriesPage] response shapes
/// (data-model.md, contracts/entries-repository-extension.md). Never sends
/// `occurredAt`/`mediaDurationSeconds`/`chatMessageId` in a request body.
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

  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? limit,
  }) async {
    final queryParameters = <String, String>{
      'cursor': ?cursor,
      'source': ?source?.name,
      'dateFrom': ?dateFrom?.toUtc().toIso8601String(),
      'dateTo': ?dateTo?.toUtc().toIso8601String(),
      'limit': ?limit?.toString(),
    };
    final result = await _apiClient.call(
      'entries-list',
      method: 'GET',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
      unwrapData: false,
    );

    return result.flatMap(_parseEntriesPage);
  }

  Future<Either<Failure, Entry>> getById(String id) async {
    final result = await _apiClient.call(
      'entries-get',
      method: 'GET',
      pathSegments: [id],
    );

    return result.flatMap(_parseEntry);
  }

  Future<Either<Failure, List<Entry>>> search({
    String? q,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,
  }) async {
    final result = await _apiClient.call(
      'entries-search',
      method: 'GET',
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (source != null) 'source': source.name,
        if (dateFrom != null) 'dateFrom': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'dateTo': dateTo.toUtc().toIso8601String(),
        'limit': limit.toString(),
      },
      unwrapData: false,
    );

    return result.flatMap(_parseSearchResults);
  }

  Either<Failure, List<Entry>> _parseSearchResults(Map<String, dynamic> body) {
    try {
      final entries = (body['data'] as List<dynamic>)
          .map((e) => _parseEntryFields(e as Map<String, dynamic>))
          .toList();
      return Right(entries);
    } on TypeError {
      return const Left(_malformedEntriesFailure);
    } on FormatException {
      return const Left(_malformedEntriesFailure);
    }
  }

  Either<Failure, Entry> _parseEntry(Map<String, dynamic> data) {
    try {
      return Right(_parseEntryFields(data));
    } on TypeError {
      return const Left(_malformedEntriesFailure);
    } on FormatException {
      return const Left(_malformedEntriesFailure);
    }
  }

  // The full response body for `entries-list` is `{"data": [...], "meta":
  // {"nextCursor": ...}}` — `ApiClient.call(..., unwrapData: false)` returns
  // it verbatim since the inner "data" here is an array, not an object.
  Either<Failure, EntriesPage> _parseEntriesPage(Map<String, dynamic> body) {
    try {
      final entries = (body['data'] as List<dynamic>)
          .map((e) => _parseEntryFields(e as Map<String, dynamic>))
          .toList();
      final meta = body['meta'] as Map<String, dynamic>;
      return Right(
        EntriesPage(
          entries: entries,
          nextCursor: meta['nextCursor'] as String?,
        ),
      );
    } on TypeError {
      return const Left(_malformedEntriesFailure);
    } on FormatException {
      return const Left(_malformedEntriesFailure);
    }
  }

  Entry _parseEntryFields(Map<String, dynamic> data) {
    return Entry(
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
}
