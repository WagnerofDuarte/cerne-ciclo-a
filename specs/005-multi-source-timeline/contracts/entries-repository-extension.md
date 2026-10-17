# Contract: `EntriesRepository` extension (`lib/features/entries/domain/repositories/entries_repository.dart`)

Extends the interface `specs/003-multimodal-capture/contracts/entries-repository.md` already defines
(`create`, `cachedEntries`, both unchanged) with the two read methods this unit needs. Still the single seam
every feature reading or writing entries depends on — `records/` is simply its first reader.

```dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({required String content, required EntrySource source}); // unchanged
  List<Entry> get cachedEntries;                                                                   // unchanged
  Future<Either<Failure, EntriesPage>> list({String? cursor});
  Future<Either<Failure, Entry>> getById(String id);
}
```

## `EntriesRepositoryImpl.list()` (orchestration, data layer)

```dart
Future<Either<Failure, EntriesPage>> list({String? cursor}) async {
  final result = await _remoteDataSource.list(cursor: cursor);
  return result.match(
    (failure) => failure is AuthExpiredFailure
        ? await _retryAfterSilentRefresh(() => _remoteDataSource.list(cursor: cursor))
        : Left(failure),
    (page) => Right(page),
  );
}
```

## `EntriesRepositoryImpl.getById()` (orchestration, data layer)

Identical shape, over `_remoteDataSource.getById(id)` instead.

## The shared retry helper (private to `EntriesRepositoryImpl`)

```dart
Future<Either<Failure, T>> _retryAfterSilentRefresh<T>(
  Future<Either<Failure, T>> Function() retry,
) async {
  final refreshed = await _sessionRepository.refresh();
  return refreshed.match(
    (_) => Left(const AuthExpiredFailure(message: 'Session could not be renewed', requestId: '')),
    (_) => retry(),   // exactly one retry — no loop, no second refresh attempt
  );
}
```

- **Exactly one retry.** If the retried call *also* comes back `AuthExpiredFailure` (a pathological
  double-expiry), it is returned to the caller as-is — no second refresh attempt, no loop. This is a
  deliberately simple, bounded policy; nothing in spec.md requires more.
- **The `Left` branch always normalizes to a fresh `AuthExpiredFailure`**, regardless of what the refresh
  attempt itself failed with (`AuthInvalidFailure` for no stored refresh token, or whatever `/auth/refresh`
  itself returned) — callers (`RecordsBloc`) only ever need to know "could not be silently renewed," not the
  refresh call's own internal failure shape, mirroring how `CheckSessionUseCase` (specs/001) already
  normalizes every unrenewable-session case down to one outcome rather than leaking the refresh call's raw
  failure type upward.
- **`create()` is untouched** — out of this unit's scope (research.md R4).

## `EntriesRemoteDataSource` additions (data layer)

```dart
Future<Either<Failure, EntriesPage>> list({String? cursor}) {
  return _apiClient
      .call('entries-list', method: 'GET', queryParameters: cursor == null ? null : {'cursor': cursor})
      .flatMap(_parseEntriesPage);
}

Future<Either<Failure, Entry>> getById(String id) {
  return _apiClient
      .call('entries-get', method: 'GET', pathSegments: [id])
      .flatMap(_parseEntry);   // the same private parser create() already uses
}
```

- `_parseEntry` (existing, `create()`'s private parser) is reused verbatim for a single object; a new
  `_parseEntriesPage` parses `data` (a list, each element through the same per-entry field logic `_parseEntry`
  already has — factored so neither duplicates the other) and `meta.nextCursor`.
- Malformed-response parsing failures (`TypeError`/`FormatException`) map to `ValidationFailure`, exactly like
  `create()`'s existing `_parseEntry` catch clauses — no new failure-mapping behavior.

## `ApiClient.call()` (core layer) — `queryParameters` addition

```dart
Future<Either<Failure, Map<String, dynamic>>> call(
  String function, {
  required String method,
  Map<String, dynamic>? body,
  List<String>? pathSegments,
  Map<String, dynamic>? queryParameters,
  AuthMode authMode = AuthMode.userSession,
}) async {
  // ...unchanged URL-building...
  final response = await _dio.request<Map<String, dynamic>>(
    url,
    data: body,
    queryParameters: queryParameters,   // NEW — passed straight through to dio
    options: Options(method: method, headers: {...}),
  );
  // ...unchanged response handling...
}
```

Every existing call site (`entries-create`, `auth-session`, `auth-refresh`, `media-ocr`) omits the new
parameter and is byte-for-byte unaffected.

## Who depends on this

`RecordsBloc` (`list`/`getById`, via `EntriesRepository` only — never `EntriesRemoteDataSource`/`ApiClient`
directly, same layering every existing feature already observes). No other unit yet calls `list()`/`getById()`
— RF06 (semantic search) is the next likely caller, reusing the same silent-refresh-and-retry behavior for
free.

## Test scenarios this contract owns (RNF07/RNF09 — for `/speckit-tasks` to schedule, not built here)

| # | Scenario | Expected |
|---|---|---|
| 1 | `list()` succeeds on the first attempt | `Right(EntriesPage(...))`, no refresh call made |
| 2 | `list()` fails `AuthExpiredFailure`, refresh succeeds, retry succeeds | `Right(EntriesPage(...))`, exactly 2 remote calls + 1 refresh call |
| 3 | `list()` fails `AuthExpiredFailure`, refresh itself fails | `Left(AuthExpiredFailure)`, no second refresh attempt |
| 4 | `list()` fails any other code (timeout/offline/validation/...) | `Left(<that failure>)` unchanged, no refresh attempted |
| 5 | `getById()` — same 4 scenarios as `list()` | same shapes |
| 6 | `list(cursor: 'abc')` | `ApiClient.call` receives `queryParameters: {'cursor': 'abc'}` |
| 7 | `list()` (no cursor) | `ApiClient.call` receives `queryParameters: null` |
| 8 | Response containing a `chat`-sourced entry | Parses without throwing, `EntrySource.chat` |
