# Data Model: P-RF07 — Multi-source history (timeline)

Source: spec.md §Key Entities, requirements.md §§1 (RF07), 6.2, 8, 13; `docs/input/backend/sync-badge.md`;
`docs/input/backend/api/openapi.yaml`'s `/entries` (list) and `/entries/{id}` schemas;
`docs/input/prototype/prototype-extract.md` §§2.4, 3, 6. This unit extends the `entries` feature's shared
`Entry`/`EntriesRepository` (RF01) with two new read methods, and adds one new feature folder's worth of
domain helpers and presentation (`records/`, R8) — it introduces no new backend-shaped entity beyond widening
one existing enum (R2).

## `Entry` (`lib/features/entries/domain/entities/entry.dart`) — extended, not replaced

Every field RF01 already modeled (`id`, `content`, `source`, `chatMessageId`, `occurredAt`, `tags`,
`piiStatus`, `piiSpans`, `embeddingStatus`, `mediaDurationSeconds`, `serverRevision`, `createdAt`, `updatedAt`)
is unchanged in shape — this unit reads `serverRevision`/`updatedAt` (sync-badge.md's two fields) and `tags`
(read-only chips), which RF01 already carries but never renders. One change:

```dart
enum EntrySource { manual, audio, photo, chat }   // chat added (research.md R2)
```

## `EntriesPage` (`lib/features/entries/domain/entities/entries_page.dart`) — NEW

The shape of one `GET /entries` response, minus the fields this unit never uses (`meta.total`, and every
`source`/`dateFrom`/`dateTo` filter parameter — reserved for RF06).

| Field | Type | Notes |
|---|---|---|
| `entries` | `List<Entry>` | `data`, in the order the backend returns it (newest-occurred-first, per the resolved ordering Clarification). |
| `nextCursor` | `String?` | `meta.nextCursor` verbatim; `null` means this was the last page. |

```dart
class EntriesPage extends Equatable {
  const EntriesPage({required this.entries, required this.nextCursor});
  final List<Entry> entries;
  final String? nextCursor;
}
```

## `EntriesRepository` — extended (`lib/features/entries/domain/repositories/entries_repository.dart`)

```dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({required String content, required EntrySource source}); // unchanged (RF01)
  List<Entry> get cachedEntries;                                                                   // unchanged (RF01)
  Future<Either<Failure, EntriesPage>> list({String? cursor});                                      // NEW
  Future<Either<Failure, Entry>> getById(String id);                                                // NEW
}
```

- **`list`** → `GET /entries` (`entries-list`), query parameters `cursor` (when non-null) only — no `limit`
  override (backend default 20), no `source`/`dateFrom`/`dateTo` (filters are RF06's).
- **`getById`** → `GET /entries/:id` (`entries-get`), `pathSegments: [id]`. Implemented and tested; no call
  site in this unit's UI flow (research.md R7).
- Both retry exactly once through `SessionRepository.refresh()` on `AuthExpiredFailure` before giving up
  (research.md R4) — see `contracts/entries-repository-extension.md` for the exact sequence. `create()` is
  untouched.

### `EntriesRemoteDataSource` — extended (`lib/features/entries/data/entries_remote_data_source.dart`)

Adds `list({String? cursor})` and `getById(String id)`, both parsing responses through the *same* private
`_parseEntry` the existing `create()` already uses (made reusable across a single object and a list of
objects) — no duplicated parsing logic. `list()` additionally parses `meta.nextCursor`.

### `EntriesRepositoryImpl` — extended (`lib/features/entries/data/entries_repository_impl.dart`)

Gains one new constructor dependency: `SessionRepository` (`session/domain/repositories/session_repository.dart`
— a cross-feature *domain* interface, the same shape `SessionRepositoryImpl` already depends on `auth`'s
`Account`). `cachedEntries`/`create()` behavior is unchanged.

## `ApiClient` — extended (`lib/core/network/api_client.dart`)

```dart
Future<Either<Failure, Map<String, dynamic>>> call(
  String function, {
  required String method,
  Map<String, dynamic>? body,
  List<String>? pathSegments,
  Map<String, dynamic>? queryParameters,   // NEW (research.md R1)
  AuthMode authMode = AuthMode.userSession,
})
```

`queryParameters` is passed straight through to `Dio.request()`. Every existing call site (`entries-create`,
`auth-session`, `auth-refresh`, `media-ocr`) is unaffected — the parameter defaults to omitted.

## `SyncBadgeState` / `LocalWriteOutcome` (`lib/features/records/domain/entities/sync_badge_state.dart`) — NEW

```dart
enum SyncBadgeState { synchronized, synchronizing, error }
enum LocalWriteOutcome { pending, failed }

class SyncBadge {
  const SyncBadge._();
  static SyncBadgeState derive(LocalWriteOutcome? localWrite) => switch (localWrite) {
    null => SyncBadgeState.synchronized,
    LocalWriteOutcome.pending => SyncBadgeState.synchronizing,
    LocalWriteOutcome.failed => SyncBadgeState.error,
  };
}
```

A pure, total function over `sync-badge.md`'s model (research.md R6). `RecordsBloc` calls it with
`localWrite: null` for every entry it ever renders — both of its entry sources (`EntriesRepository.list()`'s
results, `.cachedEntries`) are, by construction, already server-confirmed. Never depends on session/auth state
(FR-005), by having no session-related input at all.

**Mapping to the prototype's sync badge** (`prototype-extract.md` §3/§6 — reuses existing `DesignTokens`
verbatim, no new token):

| `SyncBadgeState` | Dot color | Label |
|---|---|---|
| `synchronized` | `DesignTokens.colorSuccess` (`#4C6B4F`) | "sincronizado" |
| `synchronizing` | `DesignTokens.colorWarningSync` (`#C98A3E`) | "sincronizando" |
| `error` | `DesignTokens.colorError` (`#B3402A`) | "erro de sync" |

## `DateGroup` / `DateGrouper` (`lib/features/records/domain/entities/date_group.dart`) — NEW

Maps spec.md's "Entry Timeline Page" grouping requirement (FR-002) to a pure function, independent of widget
code so it's directly unit-testable (RNF07).

```dart
class DateGroup extends Equatable {
  const DateGroup({required this.label, required this.entries});
  final String label;            // "Hoje" | "Ontem" | "{day} de {monthName}" (research.md R9)
  final List<Entry> entries;     // newest-to-oldest by occurredAt (resolved ordering Clarification)
}

class DateGrouper {
  const DateGrouper._();
  static List<DateGroup> group(List<Entry> entries, {DateTime? now});
}
```

- Input `entries` is assumed already sorted newest-to-oldest (see `EntryMerger` below, which guarantees this
  for `RecordsBloc`'s own data) — `group()` only buckets, it never re-sorts within or across groups.
  Groups themselves come out newest-to-oldest because the input is.
- Bucketing compares each entry's `occurredAt.toLocal()` calendar day against `(now ?? DateTime.now()).toLocal()`'s —
  the device's local calendar day (spec.md Assumptions), not UTC.
- `now` is an optional override purely for deterministic unit tests ("today" fixed at a known instant); production call sites omit it.

## `EntryMerger` (`lib/features/records/domain/entities/entry_merger.dart`) — NEW

Implements spec.md's resolved Clarification 3 (dedupe-by-ID, preferring the fresher copy).

```dart
class EntryMerger {
  const EntryMerger._();
  static List<Entry> merge({required List<Entry> primary, required List<Entry> secondary}) {
    // union by id, primary's copy wins on a shared id, result sorted newest-to-oldest by occurredAt
  }
}
```

`RecordsBloc` calls `EntryMerger.merge(primary: <freshly fetched or already-displayed entries>, secondary:
entriesRepository.cachedEntries)` every time it has a new batch to show (research.md R3) — never inside
`EntriesRepositoryImpl`.

## `RecordsEvent` (`lib/features/records/presentation/bloc/records_event.dart`) — NEW

| Event | When |
|---|---|
| `RecordsStarted` | `RecordsPage.initState` — triggers the first page fetch. |
| `NextPageRequested` | The list's `ScrollController` crosses a near-bottom threshold, and `!hasReachedEnd && !isLoadingMore`. |
| `PageLoadRetried` | The user taps "Tentar novamente" on a failed first load (`RecordsLoadFailure`) or a failed further-page load (`RecordsLoaded.pageLoadFailure`). |
| `RecordsLocalCacheRefreshed` | `RecordsPage`, once the insertion-modal `showModalBottomSheet` future resolves (research.md R10) — re-merges `cachedEntries` into the currently displayed list, no network call. |

## `RecordsState` (`lib/features/records/presentation/bloc/records_state.dart`) — NEW

Maps spec.md's "Entry Timeline Page" key entity directly to this sealed state's `RecordsLoaded` fields
(entries fetched so far + the cursor to continue from) — no separate domain class for it (research.md-style
reasonable decision: nothing else needs this shape outside the bloc that owns it).

```dart
sealed class RecordsState {}

class RecordsLoading extends RecordsState {}

class RecordsLoadFailure extends RecordsState {
  const RecordsLoadFailure(this.failure);
  final Failure failure;   // any failure type, including AuthExpiredFailure (research.md — see below)
}

class RecordsLoaded extends RecordsState {
  const RecordsLoaded({
    required this.entries,        // merged + deduped, newest-to-oldest
    required this.nextCursor,
    required this.isLoadingMore,
    this.pageLoadFailure,         // a further-page fetch failed; entries above stay intact, retryable
  });
  final List<Entry> entries;
  final String? nextCursor;
  final bool isLoadingMore;
  final Failure? pageLoadFailure;

  bool get hasReachedEnd => nextCursor == null;
  bool get isEmpty => entries.isEmpty;   // RecordsPage renders "Vazio" for this, never a separate event
}
```

- **First-load failure, any cause (including `AuthExpiredFailure`)** → `RecordsLoadFailure` — never the empty
  state, so a true zero-entries account is never confused with "couldn't load" (research.md's reasoning under
  R5/R7). The one-shot `reauthRequired` stream (next section) still fires in the `AuthExpiredFailure` case, on
  top of this state — the overlay appears over the retryable error screen.
- **Further-page failure, `AuthExpiredFailure`** → `entries`/`nextCursor` are left exactly as they were,
  `isLoadingMore` resets to `false` (so the next scroll-near-bottom re-attempts the same, unconsumed cursor);
  `pageLoadFailure` is **not** set for this case — only the one-shot stream fires. This is what makes FR-007's
  "without discarding the entries already loaded or the current scroll position... restored exactly as it
  was" true by construction (nothing in `RecordsState` changed).
- **Further-page failure, any other cause** (timeout, offline, validation, ...) → `pageLoadFailure` set,
  `isLoadingMore` resets to `false`, entries unchanged — a retryable inline banner at the bottom of the list
  (FR-009/Edge Cases).

## `RecordsBloc` (`lib/features/records/presentation/bloc/records_bloc.dart`) — NEW

```dart
class RecordsBloc extends Bloc<RecordsEvent, RecordsState> {
  RecordsBloc({required EntriesRepository entriesRepository});

  Stream<void> get reauthRequired;   // one-shot (research.md R5) — fired on a post-retry AuthExpiredFailure
}
```

Depends only on `EntriesRepository` (never `SessionRepository`, never `ConnectivityChecker` — research.md
R4/R11) — the one domain-layer dependency this bloc needs. Never imports `SessionBloc` or any of its
event/state types (requirements.md RF07's own acceptance criterion).

## Widgets (`lib/features/records/presentation/widgets/`, `pages/records_page.dart`) — NEW

Not separately contracted (pure prototype-fidelity rendering, no new state/logic beyond what's above):

- `records_page.dart` — `Scaffold` with the prototype's header (back arrow, title, inert download icon —
  FR-008), inert search bar + funnel button (FR-008), a `ListView` driven by `RecordsLoaded.entries` grouped
  through `DateGrouper`, a `ScrollController` that survives `BlocBuilder` rebuilds (never recreated, so scroll
  position is never lost — FR-003/FR-007), and the `reauthRequired` subscription (research.md R5).
- `record_card.dart` — one entry: spine + icon colored by `source` (table below), monospace time
  (`occurredAt.toLocal()`, `HH:mm`), `SyncBadgeDot` (table above), text excerpt (`content`, no truncation logic
  beyond what the card's fixed layout naturally clips), tag chips (`EntryTag.name`, only when `tags.isNotEmpty`
  — FR-002/Acceptance Scenario 2).
- `records_empty_state.dart` — notebook icon, "Nenhum registro ainda", "Criar primeiro registro" button
  calling the shared `openInsertionModal()` (research.md R10).
- `sync_badge_dot.dart` — the 8px dot + mono label pair, parameterized by `SyncBadgeState`.

**Origin marker mapping** (`prototype-extract.md`'s `sourceMeta`, verbatim hex — reuses existing `DesignTokens`,
no new color token; Phosphor icon names mapped to this app's existing Material-icon convention, same mapping
style RF01/RF02 already used for their own icons):

| `EntrySource` | Spine/icon color | Material icon (Phosphor equivalent) |
|---|---|---|
| `manual` | `DesignTokens.colorPrimary` (`#1F3D34`) | `Icons.edit_outlined` (`ph-pencil-simple`) |
| `audio` | `DesignTokens.colorSecondary` (`#7C8B6F`) | `Icons.mic_none` (`ph-microphone`) |
| `photo` | `DesignTokens.colorTextSecondary` (`#6B6255`) | `Icons.image_outlined` (`ph-image`) |
| `chat` | `DesignTokens.colorAccent` (`#C98A3E`) | `Icons.chat_bubble_outline` (`ph-chat-circle-text`) |

## Routing / DI changes

- `lib/core/routing/app_router.dart`: `AppRoutes.records`'s builder wraps `RecordsPage` in
  `BlocProvider<RecordsBloc>(create: (_) => getIt<RecordsBloc>()..add(const RecordsStarted()))`, replacing the
  direct `RecordsPlaceholderPage()` builder. `records_placeholder_page.dart` is deleted.
- `lib/core/di/service_locator.dart`: `EntriesRepositoryImpl`'s registration gains `sessionRepository:
  getIt<SessionRepository>()`; one new `getIt.registerFactory<RecordsBloc>(...)`.
