# Contract: `EntriesRepository.search()` + `.list()` extension

(`lib/features/entries/domain/repositories/entries_repository.dart`,
`lib/features/entries/data/entries_remote_data_source.dart`,
`lib/features/entries/data/entries_repository_impl.dart`)

## `list()` — extended

```dart
Future<Either<Failure, EntriesPage>> list({
  String? cursor,
  EntrySource? source,
  DateTime? dateFrom,
  DateTime? dateTo,
  int? limit,
});
```

`EntriesRemoteDataSource.list()`:

```dart
Future<Either<Failure, EntriesPage>> list({
  String? cursor,
  EntrySource? source,
  DateTime? dateFrom,
  DateTime? dateTo,
  int? limit,
}) async {
  final result = await _apiClient.call(
    'entries-list',
    method: 'GET',
    queryParameters: {
      if (cursor != null) 'cursor': cursor,
      if (source != null) 'source': source.name,
      if (dateFrom != null) 'dateFrom': dateFrom.toUtc().toIso8601String(),
      if (dateTo != null) 'dateTo': dateTo.toUtc().toIso8601String(),
      if (limit != null) 'limit': limit.toString(),
    },
    unwrapData: false,
  );
  return result.flatMap(_parseEntriesPage);
}
```

`queryParameters` is omitted entirely (passed as `null`, not `{}`) when every field above is `null` — matches
`ApiClient.call`'s existing `Map<String, dynamic>?` signature (RF07's `cursor`-only call site is the
degenerate case of this same map-building expression and is unaffected).

## `search()` — NEW

```dart
Future<Either<Failure, List<Entry>>> search({
  String? q,
  EntrySource? source,
  DateTime? dateFrom,
  DateTime? dateTo,
  int limit = 50,
});
```

`EntriesRemoteDataSource.search()`:

```dart
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
```

`_parseEntryFields` (shared with `_parseEntry`/`_parseEntriesPage`) gains one more optional read:

```dart
similarity: (data['similarity'] as num?)?.toDouble(),
```

`EntriesRepositoryImpl.search()`:

```dart
@override
Future<Either<Failure, List<Entry>>> search({
  String? q,
  EntrySource? source,
  DateTime? dateFrom,
  DateTime? dateTo,
  int limit = 50,
}) async {
  final result = await _remoteDataSource.search(
    q: q, source: source, dateFrom: dateFrom, dateTo: dateTo, limit: limit,
  );
  return result.match(
    (failure) => failure is AuthExpiredFailure
        ? _retryAfterSilentRefresh(
            () => _remoteDataSource.search(q: q, source: source, dateFrom: dateFrom, dateTo: dateTo, limit: limit),
          )
        : Future.value(Left(failure)),
    (entries) => Future.value(Right(entries)),
  );
}
```

Identical shape to `list()`/`getById()`'s existing `_retryAfterSilentRefresh` call — exactly one retry, no
loop, no new helper.

## Test scenarios this contract owns (for `/speckit-tasks` to schedule)

| # | Scenario | Expected |
|---|---|---|
| 1 | `list(source: EntrySource.audio)` | request's `queryParameters` includes `source: 'audio'`, no `dateFrom`/`dateTo`/`limit` keys |
| 2 | `list(dateFrom: d1, dateTo: d2)` | both sent as UTC ISO-8601 strings |
| 3 | `list()` with every new param omitted | `queryParameters` identical to RF07's original call shape (no regression) |
| 4 | `search(q: 'ansiedade')` | `entries-search` called with `q`, default `limit: 50`, no `source`/`dateFrom`/`dateTo` |
| 5 | `search()` response includes a `similarity` value per entry | parsed into `Entry.similarity`, non-null |
| 6 | `list()`/`search()` response omits `similarity` | `Entry.similarity` is `null` (no `TypeError`) |
| 7 | `search()` → `AuthExpiredFailure` → silent refresh succeeds | retried exactly once, final result is the retry's |
| 8 | `search()` → `AuthExpiredFailure` → silent refresh also fails | returns `AuthExpiredFailure`, no second retry |
| 9 | `search()` with an empty `q` string | `q` key omitted entirely from `queryParameters` (never sends `q=`) |
| 10 | Malformed `entries-search` response (missing a required field) | `ValidationFailure`, not a thrown exception |
