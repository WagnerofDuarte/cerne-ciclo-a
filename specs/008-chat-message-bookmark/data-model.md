# Data Model: P-RF10 — Save a chat message as an entry

Source: spec.md §Key Entities; requirements.md §§1 (RF10), 6.2/6.3, 8, 13; `docs/input/backend/api/
openapi.yaml`'s `/entries` POST schema; `docs/input/backend/error-taxonomy.md`;
`docs/input/prototype/prototype-extract.md` §2.2 and `cerne-prototype.html`'s own bookmark markup. Extends two
already-existing feature folders (`lib/features/chat/`, `lib/features/entries/`) — no new feature folder.

## `BookmarkStatus` (`lib/features/chat/domain/entities/bookmark_status.dart`) — NEW

```dart
/// The four sub-states prototype-extract.md's "Tela 1 — Bookmark" names
/// verbatim. Per-message, per-viewer UI state (spec.md Key Entities) — never
/// persisted itself; the entry it may produce is the persisted side effect.
enum BookmarkStatus { idle, saving, saved, error }
```

No `Equatable`, no constructor logic — a bare enum, same tier as `EntrySource`/`ChatRole`. Zero
`package:flutter`/`chat/data/` import (RNF06/Principle V).

**Transitions** (FR-002/FR-003/FR-004/FR-005/FR-007):

```
        (tap)                (success)
 idle ────────► saving ────────────────► saved   (terminal — no tap handler, research.md R8)
        ▲                         │
        │                         │ (failure — any cause, research.md R10)
        │                         ▼
        └─────────(tap)───────── error  (retryable — tap re-enters `saving`)
```

A tap while `saving` is ignored (FR-007); a tap on an `isOptimistic` message (research.md R6) is also
ignored, regardless of its (always-`idle`, since it can never have been saved yet) status.

## `CreateEntryUseCase` (`lib/features/entries/domain/usecases/create_entry_usecase.dart`) — EXTENDED

```dart
class CreateEntryUseCase {
  const CreateEntryUseCase(this._repository);
  final EntriesRepository _repository;

  Future<Either<Failure, Entry>> call(
    String content,
    EntrySource source, {
    String? chatMessageId,   // NEW — research.md R2
    DateTime? occurredAt,    // NEW — research.md R2/R3
  }) => _repository.create(
    content: content,
    source: source,
    chatMessageId: chatMessageId,
    occurredAt: occurredAt,
  );
}
```

Every existing call site (`SaveTextEntryUseCase`, `ConfirmEntrySaveUseCase`) omits both new parameters and is
unaffected — only the chat bookmark flow ever passes them.

## `EntriesRepository`/`EntriesRepositoryImpl`/`EntriesRemoteDataSource.create` — EXTENDED

```dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    String? chatMessageId,   // NEW
    DateTime? occurredAt,    // NEW
  });
  // list / getById / search / cachedEntries — unchanged
}
```

`EntriesRepositoryImpl.create()`'s own orchestration (local-cache-load, remote call, cache-and-persist on
success) is unchanged in shape — it only threads the two new parameters through to
`_remoteDataSource.create(...)`.

`EntriesRemoteDataSource.create()`'s request body gains the two fields, each included only when non-null:

```dart
body: {
  'content': content,
  'source': source.name,
  if (chatMessageId != null) 'chatMessageId': chatMessageId,
  if (occurredAt != null) 'occurredAt': occurredAt.toUtc().toIso8601String(),
}
```

Matches `entries-create`'s OpenAPI request schema exactly — `chatMessageId` (`format: uuid`, optional),
`occurredAt` (`format: date-time`, optional). `mediaDurationSeconds` stays unsent (no caller in this app ever
provides it, unchanged from RF01/RF02). The response-parsing side (`_parseEntryFields`) is already complete —
`Entry.chatMessageId`/`Entry.occurredAt` have existed since RF01 (data-model.md, 003-multimodal-capture) for
exactly this future use.

See `contracts/create-entry-usecase-chat-extension.md` for the full signatures and test-scenario table.

## `ChatRepository`/`ChatRepositoryImpl`/`ChatLocalCache` — EXTENDED

```dart
abstract class ChatRepository {
  // createSession / listSessions / cachedSessions / listMessages / cachedMessages /
  // setLastActiveSessionId / lastActiveSessionId / sendMessage / retryMessage — unchanged

  /// FR-008's device-local, best-effort "already saved" record, keyed by
  /// `ChatMessage.id`. Not the source of correctness (research.md R1) — the
  /// backend's own `entries-create` idempotency is. Safe to read only after
  /// this session's local-cache load has resolved, the same guarantee every
  /// other `ChatRepositoryImpl` method already awaits internally.
  String? savedEntryIdFor(String chatMessageId);

  /// Persists [entryId] against [chatMessageId] in the record above — called
  /// once per successful chat-sourced entry creation.
  Future<void> recordMessageSaved({required String chatMessageId, required String entryId});
}
```

`ChatLocalCache` gains one new, independent key (research.md R1):

```dart
static const _savedMessageEntryIdsKey = 'chatSavedMessageEntryIds';

Future<Map<String, String>> readSavedMessageEntryIds();
Future<void> writeSavedMessageEntryIds(Map<String, String> ids);
```

On-disk shape:

```jsonc
// key: chatSavedMessageEntryIds
{"<chatMessageId>": "<entryId>", ...}
```

`ChatRepositoryImpl` adds one in-memory field (`Map<String, String> _savedMessageEntryIds = {}`), populated
inside the existing `_ensureLocalCacheLoaded()` future alongside `_cachedSessions`/`_cachedMessages`:

```dart
Future<void> _ensureLocalCacheLoaded() {
  return _localCacheLoad ??= () async {
    _cachedSessions = await _localCache.readSessions();
    _cachedMessages.addAll(await _localCache.readAllMessages());
    _savedMessageEntryIds = await _localCache.readSavedMessageEntryIds();   // NEW
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

See `contracts/chat-repository-bookmark-extension.md` for the full test-scenario table.

## `ChatEvent`/`ChatState`/`ChatBloc` — EXTENDED

New event:

| Event | When |
|---|---|
| `BookmarkTapped(String messageId)` | Tapping a bookmark in `idle` or `error` on a user message. |

```dart
class BookmarkTapped extends ChatEvent {
  const BookmarkTapped(this.messageId);
  final String messageId;
  @override List<Object?> get props => [messageId];
}
```

`ChatReady` gains one new field:

```dart
class ChatReady extends ChatState {
  const ChatReady({
    required this.sessionId,
    required this.messages,
    required this.isOffline,
    required this.awaitingResponse,
    this.loadFailure,
    this.bookmarks = const {},          // NEW — Map<String, BookmarkStatus>, keyed by ChatMessage.id
  });

  // ...existing fields...
  final Map<String, BookmarkStatus> bookmarks;

  BookmarkStatus bookmarkStatusFor(String messageId) =>
      bookmarks[messageId] ?? BookmarkStatus.idle;

  // copyWith(...) gains a matching optional `bookmarks` parameter, defaulting to `this.bookmarks`
  // props gains `bookmarks`
}
```

Defaulting to `const {}` means every existing `ChatReady(...)` construction that doesn't concern itself with
bookmarks (the two empty-conversation constructions in `_onStarted`/`_onNewConversationRequested`) is
unchanged; only `_loadSession`'s two "has messages" branches pass `bookmarks: _seedBookmarks(messages)`
explicitly.

`ChatBloc` gains one new constructor dependency and one new handler:

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required ChatRepository chatRepository,
    required ConnectivityChecker connectivityChecker,
    required CreateEntryUseCase createEntryUseCase,   // NEW
  }) : ... {
    // ...existing on<...> registrations...
    on<BookmarkTapped>(_onBookmarkTapped);   // NEW
  }
  final CreateEntryUseCase _createEntryUseCase;   // NEW
}
```

```dart
Map<String, BookmarkStatus> _seedBookmarks(List<ChatMessage> messages) {
  final result = <String, BookmarkStatus>{};
  for (final m in messages) {
    if (m.role != ChatRole.user) continue;
    if (_chatRepository.savedEntryIdFor(m.id) != null) result[m.id] = BookmarkStatus.saved;
  }
  return result;
}

Future<void> _onBookmarkTapped(BookmarkTapped event, Emitter<ChatState> emit) async {
  final current = state;
  if (current is! ChatReady) return;
  final index = current.messages.indexWhere((m) => m.id == event.messageId);
  if (index == -1) return;
  final message = current.messages[index];
  if (message.role != ChatRole.user || message.isOptimistic) return;   // research.md R6
  final status = current.bookmarkStatusFor(message.id);
  if (status == BookmarkStatus.saving || status == BookmarkStatus.saved) return;   // FR-003/FR-007

  emit(current.copyWith(bookmarks: {...current.bookmarks, message.id: BookmarkStatus.saving}));

  final created = await _createEntryUseCase(
    message.content,
    EntrySource.chat,
    chatMessageId: message.id,
    occurredAt: message.createdAt,
  );

  final latest = state;
  if (latest is! ChatReady) return;

  await created.match(
    (failure) async {
      if (failure is AuthExpiredFailure) _reauthController.add(null);   // research.md R9
      emit(latest.copyWith(bookmarks: {...latest.bookmarks, message.id: BookmarkStatus.error}));
    },
    (entry) async {
      await _chatRepository.recordMessageSaved(chatMessageId: message.id, entryId: entry.id);
      final afterRecord = state;
      if (afterRecord is! ChatReady) return;
      emit(afterRecord.copyWith(bookmarks: {...afterRecord.bookmarks, message.id: BookmarkStatus.saved}));
    },
  );
}
```

`_loadSession`'s two emit sites gain `bookmarks: _seedBookmarks(<messages>)` (the cache-fallback branch and
the online-success branch each pass their own `messages` list through it). No other existing handler
(`_onMessageSubmitted`, `_onMessageRetryRequested`, `_consumeTurn` and its helpers) changes — the `bookmarks`
map simply passes through unchanged on every `copyWith` they already call, via its default.

See `contracts/chat-bloc-bookmark-extension.md` for the full handler and test-scenario table.

## Widgets — `bookmark_button.dart` (NEW), `chat_message_bubble.dart` (extended)

```dart
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({required this.status, this.onTap, super.key});
  final BookmarkStatus status;
  final VoidCallback? onTap;   // only ever non-null for idle/error (research.md R8)
}
```

Renders one `Icon`/spinner per state, 16 dp, no `GestureDetector` at all when `status` is `saving`/`saved`
(research.md R8):

| `BookmarkStatus` | Visual | Color | Tappable |
|---|---|---|---|
| `idle` | `Icons.bookmark_border` | `colorTextSecondary` | yes |
| `saving` | rotating-arc spinner (`CaptureLoadingIndicator`'s technique, 16 dp) | `colorTextSecondary` | no |
| `saved` | `Icons.check` | `colorAccent` | no |
| `error` | `Icons.error_outline` | `colorError` | yes |

`chat_message_bubble.dart`'s `_isUser` branch replaces its bare bubble `Container` with:

```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.end,
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(/* existing bubble, unchanged */),
    const SizedBox(width: DesignTokens.spacingBookmarkGap),
    BookmarkButton(status: bookmarkStatus, onTap: onBookmarkTap),
  ],
)
```

`ChatMessageBubble` gains two new, optional constructor parameters (`bookmarkStatus`/`onBookmarkTap`), read
only inside the `_isUser` branch — the assistant branch never references them, so FR-001 holds by
construction. `home_chat_shell_page.dart`'s `ListView.builder` passes
`bookmarkStatus: chatReady.bookmarkStatusFor(message.id)` and
`onBookmarkTap: () => context.read<ChatBloc>().add(BookmarkTapped(message.id))` on every call — harmless no-ops
for assistant messages since the widget never reads them outside `_isUser`.

**Token additions** (research.md R7 — exact prototype values, Principle IV):

| Token | Value | Used for |
|---|---|---|
| `sizeBookmarkIcon` | `16` (double, dp) | `BookmarkButton`'s icon/spinner size |
| `spacingBookmarkGap` | `6` (double, dp) | Gap between the user bubble and `BookmarkButton` in `chat_message_bubble.dart` |

**Token reuse** (no new color token):

| Element | Token |
|---|---|
| `idle`/`saving` icon color | `DesignTokens.colorTextSecondary` |
| `saved` icon color | `DesignTokens.colorAccent` |
| `error` icon color | `DesignTokens.colorError` |

## DI (`lib/core/di/service_locator.dart`) — one registration updated, none added

```dart
// Chat (P-RF04, + P-RF10's CreateEntryUseCase dependency)
getIt.registerFactory<ChatBloc>(
  () => ChatBloc(
    chatRepository: getIt<ChatRepository>(),
    connectivityChecker: getIt<ConnectivityChecker>(),
    createEntryUseCase: getIt<CreateEntryUseCase>(),   // NEW — already registered by the Entries section above it
  ),
);
```

`CreateEntryUseCase` is already registered as a `lazySingleton` by RF01's own Entries section, which the
Entries-before-Chat ordering in `service_locator.dart` already places earlier in the file — no reordering
needed.
