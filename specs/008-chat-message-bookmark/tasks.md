---

description: "Task list for P-RF10 — Save a chat message as an entry"
---

# Tasks: P-RF10 — Save a chat message as an entry

**Input**: Design documents from `/specs/008-chat-message-bookmark/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — all present and read.

**Tests**: Included. The Testing section of plan.md and the RNF07 (≥80% domain coverage)/RNF09 (15/15 error
scenarios) gates `plan.md`'s Constitution Check marks "PASS (gate carried into tasks)" make test coverage a
project requirement for this unit, not optional polish. Every contract's own scenario table
(`contracts/*.md`) is scheduled below against the test file it belongs in.

**Organization**: Tasks are grouped by user story (spec.md's four, in priority order: US1/US2 both P1, US3/US4
both P2). Foundational tasks build the shared plumbing (enum, tokens, the extended `CreateEntryUseCase` seam,
the device-local "already saved" record) every story depends on but that is not itself a user-facing scenario.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on an incomplete task)
- **[Story]**: US1/US2/US3/US4 — which spec.md user story this task belongs to
- Exact file paths are given in every description

## Path Conventions

Single Flutter project. No new feature folder — every change lands inside the two already-existing folders
this unit bridges: `lib/features/chat/`, `lib/features/entries/`, plus `lib/core/design_tokens.dart` and
`lib/core/di/service_locator.dart`. Tests mirror `lib/` under `test/`.

---

## Phase 1: Setup

**Purpose**: Confirm the starting state before extending it — no project-structure or dependency changes are
needed for this unit (plan.md: "No new feature folder... No additions" to `pubspec.yaml`).

- [X] T001 Run `fvm flutter analyze` and `fvm flutter test` from the repo root to confirm a clean, green
  baseline before making any change in this unit.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared plumbing every user story depends on — the `BookmarkStatus` enum, the two new
visual tokens, the extended `CreateEntryUseCase`/`EntriesRepository` seam, and the device-local "already
saved" record on `ChatRepository`. None of this is itself a user-facing scenario; it is what Phase 3+ builds
on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 [P] Create `lib/features/chat/domain/entities/bookmark_status.dart` with
  `enum BookmarkStatus { idle, saving, saved, error }` — a bare enum (no `Equatable`, no `package:flutter`
  import, no `chat/data/` import), matching prototype-extract.md's four named sub-states one-to-one
  (data-model.md; RNF06/Principle V — confirmed against `domain_purity_test.dart`).

- [X] T003 [P] Add two new constants to `lib/core/design_tokens.dart`, alongside the existing
  `size*`/`spacing*` constants: `static const double sizeBookmarkIcon = 16;` and
  `static const double spacingBookmarkGap = 6;` — exact pixel values transcribed from
  `docs/input/prototype/cerne-prototype.html`'s own inline bookmark markup, not rounded to the existing 4dp
  grid (research.md R7, Principle IV).

- [X] T004 Extend the abstract `EntriesRepository.create` in
  `lib/features/entries/domain/repositories/entries_repository.dart`: add two new optional named parameters,
  `String? chatMessageId` and `DateTime? occurredAt` (both default `null`), to the existing
  `{required String content, required EntrySource source}` signature. `list`/`getById`/`search`/
  `cachedEntries` are unchanged.

- [X] T005 [P] Extend `CreateEntryUseCase.call` in
  `lib/features/entries/domain/usecases/create_entry_usecase.dart`: add the same two optional named
  parameters and pass them through to `_repository.create(...)`. Every existing positional call site
  (`SaveTextEntryUseCase`, `ConfirmEntrySaveUseCase`) must remain valid, unchanged, since it only ever calls
  `_createEntryUseCase(content, source)` positionally. (depends on T004)

- [X] T006 [P] Extend `EntriesRepositoryImpl.create` in
  `lib/features/entries/data/entries_repository_impl.dart`: thread `chatMessageId`/`occurredAt` straight
  through to `_remoteDataSource.create(...)`. The orchestration shape (`_ensureLocalCacheLoaded()` → remote
  call → `_cacheAndPersist` on success) is otherwise unchanged; no retry-on-`AuthExpiredFailure` is added here
  (research.md R9 — `create()` has never had one). (depends on T004)

- [X] T007 [P] Extend `EntriesRemoteDataSource.create` in
  `lib/features/entries/data/entries_remote_data_source.dart`: add `chatMessageId`/`occurredAt` to the
  request body only when each is non-null —
  `if (chatMessageId != null) 'chatMessageId': chatMessageId` and
  `if (occurredAt != null) 'occurredAt': occurredAt.toUtc().toIso8601String()` — exactly matching
  `entries-create`'s OpenAPI request schema (`chatMessageId`: `format: uuid`, optional; `occurredAt`:
  `format: date-time`, optional). Update the class's own doc comment, which currently reads "Never sends
  `occurredAt`/`mediaDurationSeconds`/`chatMessageId` in a request body", to drop `occurredAt`/`chatMessageId`
  from that list (`mediaDurationSeconds` still never sent). (depends on T004)

- [X] T008 [P] Add the 6 scenarios from `contracts/create-entry-usecase-chat-extension.md`'s scenario table
  across `test/features/entries/domain/usecases/create_entry_usecase_test.dart`,
  `test/features/entries/data/entries_remote_data_source_test.dart`, and
  `test/features/entries/data/entries_repository_impl_test.dart`: (1) a call with no new params leaves the
  request body unchanged (zero regression for existing callers); (2) `chatMessageId` + `occurredAt` both
  present and correctly formatted in the body; (3) `chatMessageId` only — no `occurredAt` key present; (4) a
  `200` response whose `chatMessageId` matches a value already saved once (simulated idempotent retry) parses
  to `Right(Entry(...))` with no special handling; (5) the existing `NetworkOfflineFailure`/
  `NetworkTimeoutFailure`/`ValidationFailure` mappings are unchanged; (6) `AuthExpiredFailure` passes through
  as `Left` with no retry attempted inside `EntriesRepositoryImpl.create()` itself. (depends on T005, T006,
  T007)

- [X] T009 [P] Add a 4th independent key to `lib/features/chat/data/chat_local_cache.dart`:
  `static const _savedMessageEntryIdsKey = 'chatSavedMessageEntryIds'`, plus
  `Future<Map<String, String>> readSavedMessageEntryIds()` and
  `Future<void> writeSavedMessageEntryIds(Map<String, String> ids)`, JSON-encoded, following the exact
  malformed-data-returns-`{}` fallback (`on FormatException`/`on TypeError`) the file's other three keys
  (`_sessionsKey`/`_messagesKey`/`_lastActiveKey`) already use.

- [X] T010 [P] Add two new members to the abstract `ChatRepository` in
  `lib/features/chat/domain/repositories/chat_repository.dart`: `String? savedEntryIdFor(String chatMessageId)`
  and `Future<void> recordMessageSaved({required String chatMessageId, required String entryId})`.
  `createSession`/`listSessions`/`cachedSessions`/`listMessages`/`cachedMessages`/`setLastActiveSessionId`/
  `lastActiveSessionId`/`sendMessage`/`retryMessage` are unchanged.

- [X] T011 Implement `savedEntryIdFor`/`recordMessageSaved` in
  `lib/features/chat/data/chat_repository_impl.dart`: add `Map<String, String> _savedMessageEntryIds = {}`;
  load it inside the existing `_ensureLocalCacheLoaded()` future (alongside `_cachedSessions`/
  `_cachedMessages`) via `_localCache.readSavedMessageEntryIds()`; `savedEntryIdFor` reads the map
  synchronously (safe because every caller — see T017 — only calls it after `listMessages()` has already
  awaited that future); `recordMessageSaved` upserts the map (`{..._savedMessageEntryIds, chatMessageId:
  entryId}`) and persists it via `writeSavedMessageEntryIds`, unconditionally (a harmless overwrite on a
  repeat). (depends on T009, T010)

- [X] T012 [P] Create `test/features/chat/data/chat_local_cache_test.dart` covering scenarios 1-3 from
  `contracts/chat-repository-bookmark-extension.md`: (1) `readSavedMessageEntryIds()` with nothing ever
  written → `{}`; (2) `writeSavedMessageEntryIds({'m1': 'e1'})` then read → `{'m1': 'e1'}`; (3) corrupted/
  non-JSON stored data → `{}`, no throw. (depends on T009)

- [X] T013 [P] Add scenarios 4-7 from `contracts/chat-repository-bookmark-extension.md` to
  `test/features/chat/data/chat_repository_impl_test.dart`: (4) `savedEntryIdFor('m1')` before any
  local-cache-loading call has run → `null`; (5) after `listMessages(sessionId)` resolves, `savedEntryIdFor`
  for a previously-recorded id returns that `entryId`; (6) `recordMessageSaved` calls
  `_localCache.writeSavedMessageEntryIds` with the merged map, and a subsequent `savedEntryIdFor` returns it
  without a new storage read; (7) `recordMessageSaved` called twice for the same `chatMessageId`/`entryId`
  pair is a harmless overwrite — no error, exactly one entry in the map for that id. (depends on T011)

**Checkpoint**: Shared plumbing (enum, tokens, extended create-entry seam, device-local "already saved"
record) complete and tested — user story implementation can now begin.

---

## Phase 3: User Story 1 - Turning a message you just wrote into a journal entry (Priority: P1) 🎯 MVP

**Goal**: Tapping a user message's bookmark creates a journal entry (`source: chat`, matching
`chatMessageId`) via `CreateEntryUseCase`, showing `idle` → `saving` → `saved`, and that `saved` state
survives navigating away/restarting the app (FR-008).

**Independent Test**: Send a chat message, tap its bookmark, confirm a new entry exists with that message's
content, `source: chat`, and a `chatMessageId` pointing back to it; reopen the conversation (and restart the
app) and confirm the bookmark still shows `saved`.

### Implementation for User Story 1

- [X] T014 [US1] Add `BookmarkTapped` event to `lib/features/chat/presentation/bloc/chat_event.dart`:
  `class BookmarkTapped extends ChatEvent { const BookmarkTapped(this.messageId); final String messageId;
  @override List<Object?> get props => [messageId]; }`, alongside the existing `ChatStarted`/
  `ConversationSelected`/etc. events.

- [X] T015 [US1] Add a `bookmarks` field to `ChatReady` in
  `lib/features/chat/presentation/bloc/chat_state.dart`: `final Map<String, BookmarkStatus> bookmarks`,
  defaulting to `const {}` in the constructor (so the two empty-conversation constructions in
  `_onStarted`/`_onNewConversationRequested` are unaffected); add
  `BookmarkStatus bookmarkStatusFor(String messageId) => bookmarks[messageId] ?? BookmarkStatus.idle`; extend
  `copyWith` with an optional `Map<String, BookmarkStatus>? bookmarks` parameter (default `this.bookmarks`,
  matching the existing `messages`/`isOffline`/`awaitingResponse` parameter style, not the `loadFailure`
  sentinel style since `bookmarks` is never explicitly cleared to empty); add `bookmarks` to `props`. Import
  `bookmark_status.dart`. (depends on T002)

- [X] T016 [US1] In `lib/features/chat/presentation/bloc/chat_bloc.dart`: add a `required CreateEntryUseCase
  createEntryUseCase` constructor parameter and `final CreateEntryUseCase _createEntryUseCase` field;
  register `on<BookmarkTapped>(_onBookmarkTapped)` alongside the existing `on<...>` registrations; import
  `create_entry_usecase.dart` and `entry.dart` (for the `EntrySource` enum) from `features/entries/domain/`
  only — never `EntriesRepository`/`EntriesRemoteDataSource` (FR-009, confirmed against the new
  `test/architecture/no_cross_feature_data_imports_test.dart`, which is scoped to exactly this constraint;
  `no_bloc_imports_bloc_test.dart` only catches bloc-to-bloc imports and cannot see this). (depends on T014,
  T005)

- [X] T017 [US1] Add a private helper to `chat_bloc.dart`:
  `Map<String, BookmarkStatus> _seedBookmarks(List<ChatMessage> messages)` — for every message with
  `role == ChatRole.user`, if `_chatRepository.savedEntryIdFor(m.id) != null` set that id to
  `BookmarkStatus.saved` in the result map; otherwise leave it absent (i.e. `idle`). Pure given its two
  inputs. (depends on T010, T015)

- [X] T018 [US1] Call `_seedBookmarks(...)` from both of `_loadSession`'s "has messages" emit branches in
  `chat_bloc.dart` — the cache-fallback branch (`cached != null`) and the online-success branch — passing
  `bookmarks: _seedBookmarks(<that branch's own messages list>)`. The no-cache-fallback branch (`messages:
  const []`) is left on the default `bookmarks: const {}`. (depends on T017)

- [X] T019 [US1] Implement `Future<void> _onBookmarkTapped(BookmarkTapped event, Emitter<ChatState> emit)` in
  `chat_bloc.dart` per `contracts/chat-bloc-bookmark-extension.md`: return (no-op) if `state` is not
  `ChatReady`, if no message matches `event.messageId`, if that message's `role != ChatRole.user`, if
  `message.isOptimistic` (research.md R6 — real id not yet assigned by `message_created`), or if
  `bookmarkStatusFor(message.id)` is already `saving` or `saved` (FR-003/FR-007); otherwise emit `bookmarks`
  with that id set to `saving`, call
  `_createEntryUseCase(message.content, EntrySource.chat, chatMessageId: message.id, occurredAt:
  message.createdAt)`, re-read `state` (bail if no longer `ChatReady` — Edge Cases' navigate-away-mid-save),
  then on `Left(failure)` fire `_reauthController.add(null)` if `failure is AuthExpiredFailure` (research.md
  R9) and emit that id as `error`; on `Right(entry)` call `_chatRepository.recordMessageSaved(chatMessageId:
  message.id, entryId: entry.id)` and emit that id as `saved`. No pre-flight connectivity check (research.md
  R10 — a genuine offline failure surfaces as the ordinary `Left(NetworkOfflineFailure)`). (depends on T016,
  T011, T015)

- [X] T020 [US1] Update the `ChatBloc` registration in `lib/core/di/service_locator.dart`'s Chat section to
  pass `createEntryUseCase: getIt<CreateEntryUseCase>()` (already registered as a `lazySingleton` by the
  Entries section earlier in the same file — no reordering needed). (depends on T016)

- [X] T021 [P] [US1] Create `lib/features/chat/presentation/widgets/bookmark_button.dart`:
  `BookmarkButton({required BookmarkStatus status, VoidCallback? onTap, Key? key})` rendering one icon/spinner
  per status, all at `DesignTokens.sizeBookmarkIcon` — `idle`: `Icons.bookmark_border`, color
  `DesignTokens.colorTextSecondary`, tappable (`onTap` wired); `saving`: the same `RotationTransition`-over-
  fixed-sweep-`CircularProgressIndicator` technique `CaptureLoadingIndicator`
  (`lib/features/capture/presentation/widgets/capture_status_views.dart`) already uses, resized to
  `sizeBookmarkIcon`, color `colorTextSecondary`, **no** tap region at all; `saved`: `Icons.check`, color
  `DesignTokens.colorAccent`, **no** tap region; `error`: `Icons.error_outline` (same glyph/color pairing
  `RecognitionErrorView` already uses for the "red warning" semantic), color `DesignTokens.colorError`,
  tappable. Omit the `GestureDetector` entirely (not merely set `onTap: null`) for `saving`/`saved` — FR-003's
  literal "carries no tap handler" (research.md R8). (depends on T002, T003)

- [X] T022 [US1] Extend `lib/features/chat/presentation/widgets/chat_message_bubble.dart`: add two new
  optional constructor parameters, `BookmarkStatus? bookmarkStatus` and `VoidCallback? onBookmarkTap`, read
  only inside the `_isUser` branch; wrap that branch's existing bubble `Container` and a new
  `BookmarkButton(status: bookmarkStatus ?? BookmarkStatus.idle, onTap: onBookmarkTap)` in a `Row`
  (`crossAxisAlignment: CrossAxisAlignment.end`, `mainAxisSize: MainAxisSize.min`, a
  `SizedBox(width: DesignTokens.spacingBookmarkGap)` between them), in place of the bare bubble `Container`.
  The assistant branch (`_StatusLine`'s callers, the non-`_isUser` path) is untouched and never instantiates
  `BookmarkButton` — FR-001's "no exceptions" holds by construction, not by an added conditional. (depends on
  T021)

- [X] T023 [US1] Wire bookmark status/tap into
  `lib/features/home/presentation/pages/home_chat_shell_page.dart`'s `ListView.builder`: on every
  `ChatMessageBubble(...)` call, add `bookmarkStatus: chatReady?.bookmarkStatusFor(message.id)` and
  `onBookmarkTap: () => context.read<ChatBloc>().add(BookmarkTapped(message.id))`. (depends on T022, T014)

- [X] T024 [P] [US1] Add scenarios 1-2 from `contracts/chat-bloc-bookmark-extension.md` to
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`: add
  `class MockCreateEntryUseCase extends Mock implements CreateEntryUseCase {}` and pass a
  `MockCreateEntryUseCase` to every existing `ChatBloc(...)` construction in the file; (1) `_loadSession`
  resolving with a mix of messages, one of which has `savedEntryIdFor` returning a non-null id, seeds
  `bookmarks` to exactly `{thatId: BookmarkStatus.saved}` — other user/assistant messages are absent (report
  `idle`); (2) `BookmarkTapped('m1')` on an `idle` user message transitions `saving` → `saved`, calling
  `_createEntryUseCase` exactly once with `(content, EntrySource.chat, chatMessageId: 'm1', occurredAt:
  m1.createdAt)` and `_chatRepository.recordMessageSaved(chatMessageId: 'm1', entryId: entry.id)` exactly
  once. (depends on T019)

- [X] T024a [P] [US1] Add scenario 7 from `contracts/chat-bloc-bookmark-extension.md` to
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`: `BookmarkTapped(optimisticUserMessage.id)` (a
  `'local-...'`-id message, before `message_created` arrives) → no-op, `_createEntryUseCase` never called
  (research.md R6). (depends on T019, T024)

- [X] T024b [P] [US1] Add scenario 8 from the same contract to the same test file: `BookmarkTapped
  (assistantMessage.id)` dispatched directly at the handler level (defensive — the UI itself never dispatches
  this per FR-001) → no-op, `_createEntryUseCase` never called. (depends on T019, T024)

- [X] T024c [US1] Add scenario 9 from the same contract to the same test file: `BookmarkTapped('m1')` in
  flight, followed by `ConversationSelected('other-session')` dispatched before it resolves, then the save
  resolves `Right(entry)` → the now-current `ChatReady` for `'other-session'` is unaffected (its `messages`
  don't contain `'m1'`), and `_chatRepository.recordMessageSaved` is still called exactly once (Edge Cases:
  "the bookmark reflects whatever the save ultimately resolved to"). (depends on T019, T024)

- [X] T024d [US1] Add scenario 10 from the same contract to the same test file: a full `BookmarkTapped('m1')`
  → `Right(entry)` round trip, immediately followed by re-dispatching `ConversationSelected(sessionId)` for the
  same session (simulating navigate-away-and-back) → the reloaded `ChatReady.bookmarks['m1']` is
  `BookmarkStatus.saved`, confirming `_seedBookmarks` picks up `recordMessageSaved`'s persisted write on the
  very next load — FR-008/SC-005's actual save-then-reload mechanism, not just the hand-seeded map scenario 1
  already tests. (depends on T019, T024, T011)

- [X] T025 [P] [US1] Create `test/features/chat/presentation/widgets/bookmark_button_test.dart`: one widget
  test per `BookmarkStatus` value confirming the correct icon/spinner and color, and that `idle`/`error` have
  a tappable region (tapping invokes `onTap`) while `saving`/`saved` do not (no `GestureDetector` found).
  (depends on T021)

- [X] T026 [P] [US1] Extend `test/features/chat/presentation/widgets/chat_message_bubble_test.dart`: a
  user-message bubble built with `bookmarkStatus: BookmarkStatus.idle` (and separately `.saved`) renders a
  `BookmarkButton` reflecting that status, laid out in a `Row` beside the bubble. (depends on T022)

- [ ] T027 [US1] Manual verification — quickstart.md "Story 1" steps 1-4: send a message, tap its bookmark
  (spinner → ochre check), open "Meus Registros" and confirm the new entry's content/`source: chat`/
  `chatMessageId` match the message exactly; leave and return to the conversation, then fully restart the app
  and reopen it, confirming the bookmark still shows `saved` (FR-008).

**Checkpoint**: User Story 1 (the MVP) is fully functional and independently testable.

---

## Phase 4: User Story 2 - Saving the same message twice never creates a duplicate (Priority: P1)

**Goal**: Confirm the duplicate-prevention guarantee holds both for an already-`saved` bookmark (no re-tap
possible) and for a message the device has lost its local record of (idempotent backend retry).

**Independent Test**: Save a message, then force a second save attempt for it (e.g. by clearing the device's
local "already saved" record and tapping again); confirm exactly one entry exists afterward.

### Implementation for User Story 2

No new production code — FR-004's guarantee is the combination of FR-003's non-tappable `saved` state
(T021/T022, US1) and the backend's own idempotency (`error-taxonomy.md`: "never `409`, always `200`"), both
already built. This story adds the verification that guarantee actually holds.

- [X] T028 [P] [US2] Add scenario 6 from `contracts/chat-bloc-bookmark-extension.md` to
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`: `BookmarkTapped('m1')` where `m1`'s current
  `bookmarkStatusFor` is already `saved` → `_createEntryUseCase` is never called. (depends on T024)

- [X] T029 [P] [US2] Add a test to `test/features/chat/presentation/widgets/bookmark_button_test.dart`
  re-asserting, at the widget level (not just the bloc guard), that a `saved`-status `BookmarkButton` has no
  tappable region at all. (depends on T025)

- [X] T030 [P] [US2] Add a test to `test/features/chat/data/chat_repository_impl_test.dart` simulating the
  "device has no local record of an already-successful save" path: with `_savedMessageEntryIds` empty (as if
  the local cache were cleared/reinstalled), `savedEntryIdFor('m1')` returns `null`; after
  `recordMessageSaved(chatMessageId: 'm1', entryId: 'e1')` runs (simulating the idempotent backend returning
  the same entry on retry), `savedEntryIdFor('m1')` returns `'e1'` — confirming the record self-heals on the
  very next successful save regardless of what it previously held. (depends on T013)

- [ ] T031 [US2] Manual verification — quickstart.md "Story 2" steps 1-2: confirm an already-`saved` bookmark
  fires no network call even where tapped; clear/forget the device's local chat cache, reopen the same
  conversation (bookmark renders `idle` again), tap it, and confirm "Meus Registros" still shows exactly one
  entry for that message — never two.

**Checkpoint**: User Stories 1 and 2 both hold — retrying a save, with or without a local record of a prior
success, never creates a second entry.

---

## Phase 5: User Story 3 - A failed save never disrupts the conversation (Priority: P2)

**Goal**: A save failure (any cause) lands the bookmark in a retryable `error` state without blocking,
delaying, or otherwise affecting any other part of the chat screen.

**Independent Test**: Force a save to fail (e.g. no connection); confirm the bookmark shows `error` while the
rest of the conversation keeps working, then retry it once the failure condition is gone and confirm it
reaches `saved`.

### Implementation for User Story 3

No new production code — the `_onBookmarkTapped` failure branch (T019) already implements this; this story
adds the verification specific to failure handling and non-blocking behavior.

- [X] T032 [P] [US3] Add scenario 3 from `contracts/chat-bloc-bookmark-extension.md` to
  `test/features/chat/presentation/bloc/chat_bloc_test.dart`: `BookmarkTapped('m1')` where
  `_createEntryUseCase` resolves `Left(NetworkOfflineFailure(...))` → `bookmarks['m1']` ends `error`;
  `recordMessageSaved` is never called. (depends on T024)

- [X] T033 [P] [US3] Add scenario 4 from the same contract to the same test file: `Left(AuthExpiredFailure(...))`
  → `bookmarks['m1']` ends `error` and `reauthRequired` emits exactly one event (research.md R9). (depends on
  T024)

- [X] T034 [P] [US3] Add scenario 5 from the same contract to the same test file: `BookmarkTapped('m1')`
  dispatched twice back-to-back before the first resolves → `_createEntryUseCase` is called exactly once
  (FR-007). (depends on T024)

- [X] T035 [P] [US3] Add a test to `test/features/chat/presentation/widgets/bookmark_button_test.dart`
  confirming an `error`-status `BookmarkButton` is tappable and invokes `onTap` — the retry path FR-005
  requires. (depends on T025)

- [X] T036 [US3] Add a `bloc_test` scenario to `test/features/chat/presentation/bloc/chat_bloc_test.dart`
  confirming FR-006: with a `BookmarkTapped` in flight (or already resolved to `error`) for one message, a
  concurrently-dispatched `MessageSubmitted` or `ConversationSelected` proceeds exactly as it would with no
  bookmark activity at all — `_onBookmarkTapped` never touches `awaitingResponse` or `messages`. (depends on
  T019, T024)

- [ ] T037 [US3] Manual verification — quickstart.md "Story 3" steps 1-4: force offline and tap a bookmark
  (`saving` → `error`, never stuck); while it's `error`, send a message/scroll/tap a different bookmark and
  confirm all keep working independently; go back online and retap the failed bookmark to `saved`; separately,
  force `AUTH_EXPIRED` mid-save and confirm the "Sessão expirada" overlay appears while the bookmark itself
  ends `error` (retryable), succeeding normally after re-authenticating.

**Checkpoint**: Save failures of any cause are contained to their own bookmark, always retryable, and provably
non-blocking to the rest of the screen.

---

## Phase 6: User Story 4 - Only your own messages can become entries (Priority: P2)

**Goal**: The bookmark control is present on every user message and absent from every assistant message, with
no exceptions.

**Independent Test**: Inspect a conversation with both message types and confirm the bookmark renders only on
user messages.

### Implementation for User Story 4

No new production code — T022 already never instantiates `BookmarkButton` in the assistant branch, by
construction. This story adds the verification across message statuses.

- [X] T038 [P] [US4] Add a test to `test/features/chat/presentation/widgets/chat_message_bubble_test.dart`
  confirming the assistant-message branch never builds a `BookmarkButton`, for every `ChatMessageStatus`
  (`streaming`, `complete`, `failed`) and regardless of whatever `bookmarkStatus`/`onBookmarkTap` values are
  passed to the widget. (depends on T022)

- [X] T039 [US4] Add a test to `test/features/home/presentation/pages/home_chat_shell_page_test.dart`
  rendering a mixed message list — including at least one streaming and one failed assistant message —
  asserting exactly one `BookmarkButton` per user message and zero on any assistant message (SC-004).
  (depends on T023)

- [ ] T040 [US4] Manual verification — quickstart.md "Story 4": inspect a conversation containing both message
  types (including a streaming and a failed assistant response) and confirm the bookmark appears only on user
  messages, with no exceptions.

**Checkpoint**: All four user stories are independently functional and verified.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: The gates plan.md's Constitution Check marks "carried into tasks," plus the unit's own scope
boundary (FR-010).

- [X] T041 [P] Run `fvm flutter analyze` across the full, extended codebase — confirms RNF06's import-shape
  lint stays clean.

- [X] T042 [P] Run `dart test/architecture/no_bloc_imports_bloc_test.dart`,
  `dart test/architecture/domain_purity_test.dart`, and
  `dart test/architecture/no_cross_feature_data_imports_test.dart` (the last one already exists and passes
  against the pre-RF10 codebase; it is the one that actually catches `chat_bloc.dart` importing
  `EntriesRepository`/`EntriesRemoteDataSource` directly, which neither of the other two can see) unmodified
  against the extended `lib/features/chat/` — confirms no new bloc, no new flutter/data import in
  `chat/domain/`, and no direct entries-repository/data-source import in `chat/presentation/bloc/` (Constitution
  Principle V/RNF06, FR-009).

- [X] T043 Run `fvm flutter test --coverage`, then
  `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info` and
  `genhtml coverage/domain.info -o coverage/domain-html`; confirm `bookmark_status.dart` and every new
  `ChatBloc` branch (`_seedBookmarks`, `_onBookmarkTapped`'s guards/success/failure paths) meet RNF07's ≥80%
  domain-coverage gate.

- [X] T044 Cross-check that every scenario in `contracts/create-entry-usecase-chat-extension.md` (6),
  `contracts/chat-repository-bookmark-extension.md` (7), and `contracts/chat-bloc-bookmark-extension.md` (10)
  has a corresponding passing test from T008/T012/T013/T024/T024a-T024d/T028/T030/T032-T034/T036 — satisfying
  RNF09's idempotent-retry and `AuthExpiredFailure` → `reauthRequired` rows added on top of RF01's existing 3
  base failure scenarios for `entries-create`.

- [ ] T045 Manual edge-case pass from quickstart.md "Edge cases worth exercising manually": double-tap before
  resolve (exactly one network call); tap on a still-optimistic (`'local-...'`-id) message (silent no-op,
  research.md R6); content at/near the entry length limit (succeeds, or surfaces as a normal `error` without
  crashing); navigate away mid-save and back (bookmark reflects the real outcome on reload, never a stale
  `saving`).

- [X] T046 Scope-boundary check (FR-010): `git diff` against `main` touches only the files plan.md's Scale/
  Scope lists (`bookmark_status.dart`, `bookmark_button.dart`, `create_entry_usecase.dart`,
  `entries_repository.dart`/`entries_repository_impl.dart`/`entries_remote_data_source.dart`,
  `chat_repository.dart`/`chat_repository_impl.dart`/`chat_local_cache.dart`, `chat_event.dart`/`chat_state.dart`/
  `chat_bloc.dart`, `chat_message_bubble.dart`, `home_chat_shell_page.dart`, `design_tokens.dart`,
  `service_locator.dart`, plus their test files) — confirms no `records/`, `export/`, `dashboard/`, backend, or
  `docs/input/` file was touched.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational. Delivers the MVP end-to-end.
- **User Story 2 (Phase 4)**: Depends on Foundational *and* on User Story 1's `_onBookmarkTapped`/
  `BookmarkButton` (T019/T021/T024) existing to verify against — it adds no new production code.
- **User Story 3 (Phase 5)**: Same — depends on Foundational and US1's T019/T021/T024, adds no new production
  code.
- **User Story 4 (Phase 6)**: Depends on Foundational and US1's T022/T023, adds no new production code.
- **Polish (Phase 7)**: Depends on all four user stories being complete.

### Within Each Phase

- Foundational: T004 gates T005/T006/T007 (all three extend callers of the interface T004 changes); T009/T010
  are independent of each other and of T002-T008, but T011 needs both.
- User Story 1: T014/T015 (event/state shapes) gate T016 (bloc wiring), which gates T017→T018→T019→T020. T021
  (widget) is independent of the bloc chain and only needs T002/T003; T022 needs T021; T023 needs T022 and
  T014. Tests T024-T026 need their respective implementation tasks done first.
- User Stories 2-4: each task lists its own single prerequisite from Foundational/US1 above; tasks within a
  phase are otherwise independent of each other.

### Parallel Opportunities

- All of T002, T003, T009, T010 (Foundational) can run in parallel — four different files, no shared
  dependency.
- T005, T006, T007 can run in parallel once T004 is done.
- T012 and T013 (chat-repository tests) can run in parallel once T011 is done.
- In User Story 1, T021 (the `BookmarkButton` widget) can be built in parallel with T014-T020 (the bloc/event/
  state chain) — they only converge at T022.
- Every `[P]`-marked test task within US2/US3/US4 can run in parallel with its siblings in the same phase.

---

## Parallel Example: Foundational Phase

```bash
# Launch together — four independent files:
Task: "Create BookmarkStatus enum in lib/features/chat/domain/entities/bookmark_status.dart"
Task: "Add sizeBookmarkIcon/spacingBookmarkGap to lib/core/design_tokens.dart"
Task: "Add chatSavedMessageEntryIds key to lib/features/chat/data/chat_local_cache.dart"
Task: "Add savedEntryIdFor/recordMessageSaved to lib/features/chat/domain/repositories/chat_repository.dart"

# Once the EntriesRepository interface (T004) is extended, launch together:
Task: "Extend CreateEntryUseCase.call with chatMessageId/occurredAt"
Task: "Extend EntriesRepositoryImpl.create to pass the two params through"
Task: "Extend EntriesRemoteDataSource.create to add the two fields to the request body"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (blocks everything).
3. Complete Phase 3: User Story 1 — tap a message, get a persisted, restart-safe entry.
4. **STOP and VALIDATE**: run quickstart.md Story 1 manually; this is already a demoable, shippable increment.

### Incremental Delivery

1. Setup + Foundational → shared plumbing ready.
2. User Story 1 → the MVP: save, persist, survive restart.
3. User Story 2 → verify the duplicate-prevention guarantee US1's own code already provides.
4. User Story 3 → verify failure isolation/retry US1's own code already provides.
5. User Story 4 → verify the user-only placement US1's own code already provides by construction.
6. Polish → coverage/lint/architecture gates, FR-010 scope check.

Unlike a typical feature where each story adds new code, US2-US4 here are deliberately verification-only
phases: the single `_onBookmarkTapped` handler and `ChatMessageBubble`/`BookmarkButton` composition built in
US1 already satisfy FR-004 (dedup), FR-005/FR-006/FR-007 (failure isolation), and FR-001 (user-only placement)
by construction (per spec.md's own Assumptions and research.md R6/R8/R9/R10) — so their phases schedule the
tests and manual checks that prove it, not new production code.

---

## Notes

- `[P]` tasks touch different files with no dependency on an incomplete task in the same phase.
- `[Story]` labels trace every task back to spec.md's own four user stories.
- Tests are included per contract scenario table (`contracts/*.md`) — run them and confirm they pass, not just
  that they exist.
- Commit after each task or logical group.
- Stop at any checkpoint to validate a story independently before moving on.
