# Contract: `CreateEntryUseCase` / `EntriesRepository.create` / `EntriesRemoteDataSource.create` extension

Extends the interface `specs/003-multimodal-capture/contracts/entries-repository.md` and
`specs/003-multimodal-capture/contracts/save-usecases.md` already define — `create`'s existing two required
parameters (`content`, `source`) are unchanged; this unit only adds two optional named ones, exactly the
extension `create_entry_usecase.dart`'s own doc comment has named since RF01 shipped.

```dart
class CreateEntryUseCase {
  const CreateEntryUseCase(this._repository);
  final EntriesRepository _repository;

  Future<Either<Failure, Entry>> call(
    String content,
    EntrySource source, {
    String? chatMessageId,
    DateTime? occurredAt,
  }) => _repository.create(
    content: content,
    source: source,
    chatMessageId: chatMessageId,
    occurredAt: occurredAt,
  );
}
```

```dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    String? chatMessageId,
    DateTime? occurredAt,
  });
  // list / getById / search / cachedEntries — unchanged, see 003/005/006's own contracts
}
```

## `EntriesRepositoryImpl.create()` (orchestration, data layer) — unchanged shape, 2 new pass-through params

```dart
Future<Either<Failure, Entry>> create({
  required String content,
  required EntrySource source,
  String? chatMessageId,
  DateTime? occurredAt,
}) async {
  await _ensureLocalCacheLoaded();
  final result = await _remoteDataSource.create(
    content: content,
    source: source,
    chatMessageId: chatMessageId,
    occurredAt: occurredAt,
  );
  return result.match(
    (failure) => Future.value(Left(failure)),
    (entry) async {
      await _cacheAndPersist([entry]);
      return Right(entry);
    },
  );
}
```

No retry-on-`AuthExpiredFailure` is added here (research.md R9) — `create()` has never had one (RF01), and
this unit doesn't add it; `ChatBloc`'s own `_onBookmarkTapped` fires `reauthRequired` on that specific failure
instead (contracts/chat-bloc-bookmark-extension.md).

## `EntriesRemoteDataSource.create()` (data layer) — request body gains 2 optional fields

```dart
Future<Either<Failure, Entry>> create({
  required String content,
  required EntrySource source,
  String? chatMessageId,
  DateTime? occurredAt,
}) async {
  final result = await _apiClient.call(
    'entries-create',
    method: 'POST',
    body: {
      'content': content,
      'source': source.name,
      if (chatMessageId != null) 'chatMessageId': chatMessageId,
      if (occurredAt != null) 'occurredAt': occurredAt.toUtc().toIso8601String(),
    },
  );
  return result.flatMap(_parseEntry);   // unchanged — Entry.chatMessageId/occurredAt already parsed since RF01
}
```

The class's own doc comment ("Never sends `occurredAt`/`mediaDurationSeconds`/`chatMessageId` in a request
body") is updated to drop `occurredAt`/`chatMessageId` from that list — `mediaDurationSeconds` still never
sent by any caller in this app.

## Who depends on this

`ChatBloc._onBookmarkTapped` (contracts/chat-bloc-bookmark-extension.md) is the only new caller, passing both
new parameters. Every existing caller — `SaveTextEntryUseCase`, `ConfirmEntrySaveUseCase` (RF01/RF02) — omits
both and is unaffected.

## Test scenarios this contract owns (RNF07/RNF09 — for `/speckit-tasks` to schedule, not built here)

| # | Scenario | Expected |
|---|---|---|
| 1 | `create(content, EntrySource.manual)` — no new params | Request body unchanged (no `chatMessageId`/`occurredAt` keys) — confirms zero regression for every existing caller |
| 2 | `create(content, EntrySource.chat, chatMessageId: 'uuid-1', occurredAt: t)` | Request body includes both: `{'chatMessageId': 'uuid-1', 'occurredAt': t.toUtc().toIso8601String()}` alongside `content`/`source` |
| 3 | `create(..., chatMessageId: 'uuid-1')` without `occurredAt` | Only `chatMessageId` added; no `occurredAt` key present |
| 4 | Backend responds `200` with an entry whose `chatMessageId` equals a value already saved once before (simulating the idempotent-retry path) | `Right(Entry(...))` parsed normally — no special client-side handling needed; `_cacheAndPersist` upserts by `id`, same as any other `create()` result |
| 5 | `create()` fails `NetworkOfflineFailure`/`NetworkTimeoutFailure`/`ValidationFailure` (the 3 RNF09 scenarios, already covered by RF01's own tests for this endpoint) | `Left(<that failure>)`, unchanged — confirms the extension didn't alter existing failure-mapping behavior |
| 6 | `create()` fails `AuthExpiredFailure` | `Left(AuthExpiredFailure)` — no silent retry attempted inside `EntriesRepositoryImpl.create()` itself (research.md R9); the caller (`ChatBloc`) is responsible for any reauth signaling |
