# Contract: `ChatRepository`/`ChatRepositoryImpl`/`ChatLocalCache` bookmark extension

Extends the interface `specs/007-chat-memory-rag/contracts/chat-repository.md` already defines (every
existing member unchanged) with the one new read/write pair FR-008 needs — a device-local, best-effort record
of which chat messages have already produced an entry (research.md R1).

```dart
abstract class ChatRepository {
  // createSession / listSessions / cachedSessions / listMessages / cachedMessages /
  // setLastActiveSessionId / lastActiveSessionId / sendMessage / retryMessage — unchanged

  String? savedEntryIdFor(String chatMessageId);

  Future<void> recordMessageSaved({required String chatMessageId, required String entryId});
}
```

## `ChatLocalCache` additions (data layer)

```dart
static const _savedMessageEntryIdsKey = 'chatSavedMessageEntryIds';   // 4th independent key

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
```

Same malformed-data-returns-empty fallback shape every other `ChatLocalCache`/`EntriesLocalCache` read method
already uses — a corrupted or unreadable record degrades to "nothing known saved yet," never a crash; the
backend's own idempotency (not this cache) is what still prevents a duplicate entry if that happens (research.md
R1).

## `ChatRepositoryImpl` additions (data layer)

```dart
Map<String, String> _savedMessageEntryIds = {};

Future<void> _ensureLocalCacheLoaded() {
  return _localCacheLoad ??= () async {
    _cachedSessions = await _localCache.readSessions();
    _cachedMessages.addAll(await _localCache.readAllMessages());
    _savedMessageEntryIds = await _localCache.readSavedMessageEntryIds();   // NEW line in the existing future
  }();
}

@override
String? savedEntryIdFor(String chatMessageId) => _savedMessageEntryIds[chatMessageId];

@override
Future<void> recordMessageSaved({required String chatMessageId, required String entryId}) async {
  _savedMessageEntryIds = {..._savedMessageEntryIds, chatMessageId: entryId};
  await _localCache.writeSavedMessageEntryIds(_savedMessageEntryIds);
}
```

- **`savedEntryIdFor` is synchronous and does not itself await `_ensureLocalCacheLoaded()`.** It is only ever
  called by `ChatBloc._seedBookmarks`, strictly after `listMessages(sessionId)` has already resolved inside
  `_loadSession` — and `listMessages()` already awaits `_ensureLocalCacheLoaded()` unconditionally before
  returning, in both its success and (post-retry) failure paths. By the time `_seedBookmarks` runs, the map is
  therefore guaranteed populated. Calling `savedEntryIdFor` from anywhere that has *not* first awaited one of
  `createSession`/`listSessions`/`listMessages` would not have this guarantee — no such call site exists in
  this unit.
- **`recordMessageSaved` always persists**, even if the in-memory map already happened to contain the same
  pair (e.g. a retried save after a lost local record) — a harmless, idempotent overwrite.

## Who depends on this

`ChatBloc._seedBookmarks`/`_onBookmarkTapped` only (contracts/chat-bloc-bookmark-extension.md) — no other unit
yet calls `savedEntryIdFor`/`recordMessageSaved`.

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `readSavedMessageEntryIds()` with nothing ever written | `{}` |
| 2 | `writeSavedMessageEntryIds({'m1': 'e1'})` then `readSavedMessageEntryIds()` | `{'m1': 'e1'}` |
| 3 | `readSavedMessageEntryIds()` over corrupted/non-JSON stored data | `{}` (no throw) |
| 4 | `ChatRepositoryImpl.savedEntryIdFor('m1')` before any local-cache-loading call has ever run | `null` (the untouched initial `{}` — this is the expected pre-load state; `ChatBloc` never calls it in this state, see note above) |
| 5 | `listMessages(sessionId)` succeeds, then `savedEntryIdFor('m1')` where `'m1'` was previously recorded | returns the recorded `entryId`, confirming the local-cache load populated `_savedMessageEntryIds` as part of `_ensureLocalCacheLoaded()` |
| 6 | `recordMessageSaved(chatMessageId: 'm1', entryId: 'e1')` | `_localCache.writeSavedMessageEntryIds` is called with a map containing `{'m1': 'e1'}` merged with whatever was already in memory; a subsequent `savedEntryIdFor('m1')` returns `'e1'` without a new storage read |
| 7 | `recordMessageSaved` called twice for the same `chatMessageId` with the same `entryId` (simulating a retried save after a lost local record, research.md R1/FR-004) | Second call is a harmless overwrite — no error, map still has exactly one entry for that id |
