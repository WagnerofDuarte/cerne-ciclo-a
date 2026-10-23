# Research: P-RF10 — Save a chat message as an entry

Phase 0 output. Each item is a reasonable technical decision made under Constitution Principle I ("where these
documents are silent, implementers MUST make a reasonable technical decision rather than block on
clarification"). None reopens spec.md's own already-resolved calls (FR-003's `saved`-state non-tappability,
FR-009's "shared interface" requirement) — each item below fills in a mechanical detail those, the OpenAPI
contract, or the prototype extract leave open.

## R1 — Where does "this message was already saved" live for FR-008's restart-safety?

**Decision**: `ChatRepository` (domain) gains two new members:

```dart
String? savedEntryIdFor(String chatMessageId);
Future<void> recordMessageSaved({required String chatMessageId, required String entryId});
```

`savedEntryIdFor` is a synchronous read of an in-memory `Map<String, String>` that `ChatRepositoryImpl` loads
from a new `ChatLocalCache` key (`chatSavedMessageEntryIds`) inside the exact same `_ensureLocalCacheLoaded()`
future every other `ChatRepositoryImpl` method already awaits before returning
(`createSession`/`listSessions`/`listMessages` all await it today). `ChatBloc` only ever calls
`savedEntryIdFor` from inside `_loadSession`, strictly after `listMessages(sessionId)` has resolved — which
means `_ensureLocalCacheLoaded()` has, by construction, already completed, so the read is always safe without
needing its own `await`. `recordMessageSaved` upserts the map and persists it via a new
`ChatLocalCache.writeSavedMessageEntryIds()`, called once, right after a bookmark's `CreateEntryUseCase` call
succeeds.

**Rationale**: this is a device-local, per-viewer convenience exactly as spec.md's own Assumptions describe it
("a device-local record of which messages this client has already saved; that record is a convenience, not a
correctness mechanism") — mirroring the identical shape `ChatLocalCache` already uses for
`chatSessionsLocalCache`/`chatMessagesLocalCache`/`chatLastActiveSessionId` (three independent keys, one
lazy-loaded future, each read only after that future is known to have resolved). Keeping it behind
`ChatRepository` (never exposed as a raw `ChatLocalCache` read to `ChatBloc`) preserves the same
presentation-depends-on-repository-only layering every other bloc in this codebase already observes.

**Alternatives considered**: deriving "already saved" by scanning `EntriesRepository.cachedEntries` for a
`chatMessageId` match — rejected (see plan.md's Complexity Tracking): `cachedEntries` is a synchronous getter
over a *different* feature's own independently-lazy-loaded cache, with no guarantee it has been populated by
the time `ChatBloc` loads a session (nothing in this unit's flow calls any `EntriesRepository` method before
that point), and reading it would add a needless second `entries/`-feature dependency to `ChatBloc` for a
question `chat/`'s own local cache can answer by itself. A brand-new, separate `BookmarkLocalCache` class —
rejected: `ChatLocalCache` already exists, already mirrors `EntriesLocalCache`'s exact per-feature-cache
rationale, and a 4th independent key costs nothing a new class would also need (same constructor, same
`FlutterSecureStorage` instance, same JSON-encode-on-write pattern).

## R2 — Extending `CreateEntryUseCase`/`EntriesRepository.create` without touching existing callers

**Decision**: add two optional, named parameters — `chatMessageId` and `occurredAt`, both defaulting to
`null` — through all four layers already in the create path: `CreateEntryUseCase.call`,
`EntriesRepository.create`, `EntriesRepositoryImpl.create`, `EntriesRemoteDataSource.create`.
`EntriesRemoteDataSource.create`'s request body includes `chatMessageId`/`occurredAt` only when each is
non-null (the same optional-field-omission style `list`/`search` already use for their own optional query
parameters), exactly matching the OpenAPI schema (`entries-create`'s request body: `chatMessageId` —
`format: uuid`, optional; `occurredAt` — `format: date-time`, optional).

**Rationale**: `create_entry_usecase.dart`'s own doc comment has named this extension point since RF01 shipped
("RF10 will extend this signature, never bypass it"). Positional-with-named-optional-additions is the only
shape that leaves every existing call site (`SaveTextEntryUseCase`'s and `ConfirmEntrySaveUseCase`'s three
manual/audio/photo sites) byte-for-byte untouched — they already call `_createEntryUseCase(content, source)`
positionally, which remains valid with the new named parameters simply omitted.

**Alternatives considered**: a parallel `CreateChatEntryUseCase` class — rejected, FR-009 explicitly wants
*one* shared interface every feature creating an entry depends on, not a second, chat-specific one that would
duplicate `CreateEntryUseCase`'s single orchestration line for no behavioral difference; making the two new
fields positional — rejected, would force every existing call site to be edited for no reason.

## R3 — `occurredAt`'s value

**Decision**: the bookmark flow always passes the originating `ChatMessage.createdAt` (the message's own send
time) as `occurredAt`, exactly as spec.md's Assumptions state ("the chat message's own `createdAt` timestamp...
not the moment the user taps the bookmark"). Every other existing caller continues to omit `occurredAt`
entirely, leaving the backend's own default (creation time = now) exactly as it behaves today for manual/
audio/photo entries — confirmed no regression, since the parameter is optional and no current caller passes
it.

**Rationale**: a bookmark can be tapped well after the message was sent (the user keeps chatting, then later
taps an earlier message's bookmark) — using "now" instead of the message's own `createdAt` would place the
resulting entry at the wrong point in the user's timeline, the exact failure mode the Assumption calls out.

## R4 — Where the bookmark's orchestration logic lives

**Decision**: `ChatBloc` gains exactly one new constructor dependency, `CreateEntryUseCase` — the sanctioned
shared seam FR-009 names directly, never `EntriesRepository`/`EntriesRemoteDataSource` — and handles the whole
bookmark flow inline via one new event (`BookmarkTapped(messageId)`) and one new private handler
(`_onBookmarkTapped`). No dedicated `SaveChatMessageUseCase`/`BookmarkRepository` class is introduced.

**Rationale**: this is the identical judgment RF04's own research.md R13 already made for every other
`ChatBloc` handler ("no extra use-case layer... every event it handles belongs to the one conversation
screen's one flow"). The bookmark handler needs exactly two calls — `CreateEntryUseCase(...)` and, on success,
`ChatRepository.recordMessageSaved(...)` — neither of which has any behavior of its own beyond what the
handler already needs inline (resolve the message by id, guard its current status, emit `saving`, await the
result, emit `saved`/`error`). A separate `BookmarkBloc` was also considered and rejected: it would either need
to duplicate `ChatBloc`'s own `messages` list (to resolve a `messageId` to its `content`/`createdAt`) or import
`ChatBloc` directly, which this codebase's established "no BLoC imports another BLoC directly" convention
(RF07's own acceptance criterion, reinforced by RF04's research.md R7) forbids.

**Alternatives considered**: a `SaveChatMessageUseCase` wrapping both calls for symmetry with `capture/`'s
use-case classes — rejected, `capture/`'s use cases exist because `InsertionModalBloc` fans out across several
structurally different tabs each needing an independently-testable "what does Save do here" unit; `ChatBloc`'s
bookmark flow has no such fan-out, so the wrapper would add a file and a DI registration with zero
testability gain over mocking `CreateEntryUseCase`/`ChatRepository` directly, the same level every other
`ChatBloc` test already mocks at.

## R5 — Per-message bookmark state representation

**Decision**: `ChatReady` gains one new field, `Map<String, BookmarkStatus> bookmarks` (default `const {}`,
keyed by `ChatMessage.id`; an absent key means `idle`), plus a helper
`BookmarkStatus bookmarkStatusFor(String messageId) => bookmarks[messageId] ?? BookmarkStatus.idle`.
`BookmarkStatus` is a new, plain 4-value enum (`idle`, `saving`, `saved`, `error`) in
`lib/features/chat/domain/entities/bookmark_status.dart`, matching prototype-extract.md's own four named
sub-states one-to-one — `ChatMessageBubble`/`BookmarkButton` render directly off it with no translation layer.
Whenever `_loadSession` (re)loads a conversation's messages — on `ChatStarted` or `ConversationSelected`, both
the cache-fallback and the online-success branch — a new private helper, `_seedBookmarks(messages)`, rebuilds
the `bookmarks` map from scratch: for every `role == user` message, it calls
`_chatRepository.savedEntryIdFor(m.id)`; a non-null result seeds that message's entry as `saved`, otherwise it
is left absent (i.e. `idle`). This is the whole mechanism behind FR-008 — no separate "restore bookmarks" step,
no polling.

**Rationale**: spec.md's own Key Entities section is explicit that "Bookmark" is "per-message, per-viewer UI
state... [that] never itself becomes a persisted record" — a plain side-table keyed by message id, parallel to
(not merged into) `messages`, matches that description directly. Folding a `bookmarkStatus` field onto
`ChatMessage` itself was the other option and was rejected: `ChatMessage` already matches `chat-messages-list`'s
response schema field-for-field (data-model.md's own stated precedent from RF04) and the backend schema has no
such field; adding one would blur a transport-shaped entity with a client-only UI concern, and would force
every one of `ChatBloc`'s existing `_withId`/`_withContent`/`_withStatus` copy-helpers to additionally thread a
field they have no reason to touch today.

**Alternatives considered**: as above (field on `ChatMessage`) — rejected for the reasons given; computing
`bookmarkStatusFor` by scanning `EntriesRepository.cachedEntries` every time it's called, instead of seeding a
map once at load time — rejected as both slower (an O(n) scan per message per rebuild) and reintroducing the
exact cross-feature-cache-timing coupling R1 already rejected.

## R6 — Guarding the one race the prototype's own simulation doesn't model: an optimistic message id

**Decision**: `_onBookmarkTapped` resolves the target message by id and, before doing anything else, returns
(a silent no-op) if that message's `isOptimistic` getter is `true` (the existing `id.startsWith('local-')`
check `ChatMessage` already defines) — i.e., the backend has not yet assigned this message its real id via
`message_created`. The bookmark remains visible and visually `idle`/tappable; the tap is simply swallowed, the
same way a tap on an already-`saving` bookmark is (FR-007's own "ignored" language).

**Rationale**: a user message is appended to `ChatReady.messages` the instant it's typed (RNF01's optimistic
placeholder, RF04's research.md R5), with a client-generated `'local-<timestamp>'` id, before the backend's
`message_created` SSE event assigns the real one. The bookmark control is rendered for every user message
regardless of status (FR-001 has no exception for "message not yet acknowledged by the server"), so a tap
during that narrow window is reachable in principle. Sending a `'local-...'` string as `chatMessageId` would
violate the OpenAPI field's own `format: uuid` constraint and either get rejected outright or (worse) write an
entry with a `chatMessageId` that resolves to nothing once reconciliation happens. Neither `requirements.md`
nor the prototype (whose own simulated bookmark has no server-roundtrip concept at all — every message id is
assigned client-side, synchronously, forever) describes this race, so Principle I's "reasonable technical
decision" applies directly.

**Alternatives considered**: hiding/disabling the bookmark visually while a message is optimistic — rejected,
FR-001 requires the control present on every user message "with no exceptions," and a new, narrower
disabled-look state is unneeded complexity when a silent no-op (identical in spirit to the already-specified
"ignore a tap while `saving`" behavior) is simpler and satisfies both FR-001 and correctness at once; queuing
the tap to fire automatically once the real id arrives — rejected as speculative scope nothing in spec.md asks
for, for a window typically sub-second long in practice.

## R7 — Icon/token mapping (visual fidelity, RNF08)

**Decision**: transcribed directly from the prototype's own inline bookmark markup
(`docs/input/prototype/cerne-prototype.html`): a 16 dp icon, bottom-aligned in the same row as the user bubble
(not inside it), with a 6 dp gap between bubble and icon; colors `#6B6255` (`DesignTokens.colorTextSecondary`,
`idle`/`saving`), `#C98A3E` (`DesignTokens.colorAccent`, `saved`), `#B3402A` (`DesignTokens.colorError`,
`error`); a continuous 1 s linear spin only in `saving`. Two new `DesignTokens` constants are added for the two
values with no existing match on the 4 dp spacing/size scale — `sizeBookmarkIcon = 16` and
`spacingBookmarkGap = 6` — following the exact precedent `sizeAudioRecordIcon`/`sizePhotoTileIcon`/
`borderWidthFocused` (RF01–RF03) already set for off-grid, element-specific values read straight off the
prototype rather than rounded to the nearest 4 dp step. Every color is reused verbatim — zero new color
tokens.

Icon glyphs: this codebase has no Phosphor dependency (every prior unit already substitutes a
semantically-equivalent Material glyph — e.g. `capture_status_views.dart` already maps the prototype's
`warning-circle` to `Icons.error_outline`). Mapping used here: `idle` → `Icons.bookmark_border`; `saving` → the
same rotating-arc technique `CaptureLoadingIndicator` already establishes (`RotationTransition` over a
fixed-sweep `CircularProgressIndicator`), reused at the new 16 dp size; `saved` → `Icons.check` (the
prototype's own choice is a plain checkmark, `ph-check`, not a circled one); `error` → `Icons.error_outline`
(the exact glyph/color pairing `RecognitionErrorView` already uses for the same "red warning" semantic).

**Rationale**: Principle IV requires every visual value to trace to the prototype through `design_tokens.dart`
with zero hardcoding elsewhere; reading the actual rendered pixel values out of the prototype's own source
(rather than approximating with the nearest existing 4 dp token) is the only way to satisfy RNF08's "spacing
matches the prototype" for a value that genuinely isn't a multiple of 4.

**Alternatives considered**: rounding 6 dp up to the existing `spacingSm` (8 dp) to avoid adding a token —
rejected, a visible, measurable deviation from the prototype for no reason stronger than "avoid one constant";
adding the `phosphor_flutter` package to render the prototype's exact glyphs — rejected, new dependency for
icons every prior unit already substitutes with Material equivalents without it.

## R8 — Widget composition and placement

**Decision**: a new, small `BookmarkButton` widget (`lib/features/chat/presentation/widgets/bookmark_button.dart`),
taking `(BookmarkStatus status, VoidCallback? onTap)`. Its own `GestureDetector` is **omitted entirely** (not
merely disabled) whenever `status` is `saving` or `saved` — matching FR-003's literal wording ("carries no tap
handler") rather than only its visual appearance. `ChatMessageBubble`'s existing `_isUser` branch is extended:
the bubble `Container` and a `BookmarkButton` are wrapped in a `Row` (`crossAxisAlignment: CrossAxisAlignment.end`,
a `spacingBookmarkGap`-wide gap between them), replacing the bare bubble, matching the prototype's own
row-wrapped markup (bubble + bookmark bottom-aligned, gap 6 dp, timestamp below the whole row — unchanged).
The assistant branch is untouched; `BookmarkButton` is never instantiated there, so FR-001's "no exceptions" —
including insight cards and streaming/failed assistant bubbles, none of which are rendered by the `_isUser`
branch at all — holds by construction, not by an extra conditional.

**Rationale**: matches the prototype's own markup structure exactly (a `flex` row containing the bubble and
the bookmark icon, bottom-aligned, the timestamp below) rather than approximating a different layout.
Omitting the `GestureDetector`/tap region entirely for `saving`/`saved` (rather than wrapping it and setting
`onTap: null`, which Flutter's own `GestureDetector` already treats as inert, but would still carry a widget
whose *name* suggests interactivity) keeps the implementation legible against FR-003's specific wording.

**Alternatives considered**: a single `AnimatedSwitcher`-driven icon swap with an always-present
`GestureDetector` guarded only by a `null` callback — rejected as functionally equivalent but less literal
against FR-003's "carries no tap handler," and not meaningfully simpler to write.

## R9 — Session-expiry handling during a bookmark save (Edge Cases)

**Decision**: `_onBookmarkTapped`'s failure branch checks `if (failure is AuthExpiredFailure)
_reauthController.add(null);` before setting the bookmark to `error` — the exact same one-line pattern
`_consumeTurn`'s `_applyFailure` branch and `_loadSession`'s failure branch already use for every other
`AuthExpiredFailure` this bloc can see. The bookmark itself still ends in `error` (retryable) either way; no
silent-refresh-and-retry is added to `EntriesRepositoryImpl.create()` itself.

**Rationale**: spec.md's Edge Cases explicitly names this path ("the existing overlay takes over as it already
does for the rest of the screen; once re-authenticated, the bookmark reflects the save's actual outcome rather
than being stuck mid-attempt"). Firing `reauthRequired` raises the same "Sessão expirada" overlay every other
auth-expiry path in this screen already raises; leaving the bookmark in `error` (rather than inventing an
auto-retry) satisfies "reflects the save's actual outcome" (a failed attempt did, in fact, fail) while staying
tappable once the user re-authenticates and taps again — no new state, no new retry machinery.

**Alternatives considered**: adding a silent-refresh-and-retry to `EntriesRepositoryImpl.create()` (mirroring
`list()`/`search()`'s own `_retryAfterSilentRefresh`) — rejected as out of this unit's scope: `create()`'s
retry behavior is RF01-owned, shared by every other caller (manual/audio/photo), and spec.md never asks RF10
to change it; the overlay-plus-retryable-error path already satisfies the stated Edge Case without touching
RF01's existing, shipped behavior.

## R10 — No connectivity pre-check gate before a bookmark save

**Decision**: unlike `ChatBloc`'s message-send path (which blocks client-side on `ConnectivityChecker.
hasConnection()` before even attempting a send, per FR-012 of RF04), the bookmark flow performs **no**
pre-check — it always calls `CreateEntryUseCase` and lets a genuine offline condition surface as the ordinary
`NetworkOfflineFailure` `Either.Left`, mapped to the same `error` bookmark state as any other failure.

**Rationale**: spec.md's own Acceptance Scenario (US3 Scenario 1) describes tapping while offline as
transitioning through `saving` and landing on `error` ("the control shows a saving indicator... and, instead
of getting stuck, moves to the error state") — not as a blocked, never-attempted tap the way RF04's composer
behaves. The Edge Cases section reinforces this by listing "no connection" as just one interchangeable cause
among several ("timeout," "PII check fails," "embedding step fails") that all produce the identical `error`
outcome, with the explicit note that "the user is not expected to distinguish the underlying cause." Adding a
pre-check here would special-case connectivity failures differently from every other failure cause the spec
treats uniformly, for no stated benefit.

**Alternatives considered**: reusing RF04's pre-check pattern for consistency across the screen — rejected, it
would contradict the Acceptance Scenario's own described sequence (`saving` → `error`, not "nothing happens"),
and the two flows have a genuinely different failure-isolation requirement to begin with (RF04 must prevent an
entire conversation turn from starting; RF10 only ever affects one message's own bookmark, so there is nothing
broader to protect by blocking early).
