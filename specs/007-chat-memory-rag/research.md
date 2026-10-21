# Research: P-RF04 — Interactive chat with memory (RAG)

Phase 0 output. Each item is a reasonable technical decision made under Constitution Principle I ("where these
documents are silent, implementers MUST make a reasonable technical decision rather than block on
clarification"). None reopens one of spec.md's own three already-resolved Clarifications (title derivation,
side-menu ordering/pagination, offline cache scope) — each item below fills in a mechanical detail those
Clarifications, the OpenAPI contract, or the prototype extract leave open.

## R1 — How is the SSE response (`chat-messages-send`/`chat-messages-retry`) consumed without a new dependency?

**Decision**: `ApiClient` (core/network) gains one new method, `sseStream(...)`, built on `dio`'s own
`ResponseType.stream` — the same `Dio` instance every other call already goes through, just configured to
return a raw byte stream (`ResponseBody.stream`) instead of buffering/decoding a JSON body. It:
1. Issues the request with `Options(method: 'POST', responseType: ResponseType.stream, headers: {...})` —
   same `apikey`/`Authorization` headers every other call already sends.
2. Decodes the byte stream as UTF-8 and buffers it into lines, splitting on the blank-line (`\n\n`) SSE frame
   delimiter — a frame is one or more `field: value` lines; this unit only ever needs `event:` and `data:`.
3. Yields `Right(SseFrame(event: ..., data: ...))` for each parsed frame, in arrival order.
4. Catches `DioException` the same way `call()`'s own `_mapException` already does (timeout → retryable
   `NetworkTimeoutFailure`; no response at all → `NetworkOfflineFailure`; a response body that *is* JSON and
   carries `{code, message, retryable}` → `ErrorMapper.fromResponse`), yielding exactly one `Left(failure)` as
   the stream's last item, then closes the stream normally (never a Dart-level `Stream.error`/exception).

**Rationale**: `docs/input/backend/api/openapi.yaml`'s own schema for both SSE operations is `content:
text/event-stream` / `schema: {type: string}` — i.e., "a stream of bytes," with no generated Dart client
possible for it the way `call()`'s JSON responses already have. Every other HTTP primitive this app needs
(headers, auth mode, the exact mapped `Failure` taxonomy) already lives in `ApiClient`; duplicating that logic
in a second, chat-specific HTTP client would violate Principle II's "single, non-negotiable stack" spirit for
no benefit. A hand-rolled SSE line-parser is ~30 lines over a byte stream `dio` already exposes — simpler than
adding a transitive dependency (e.g., `flutter_client_sse`, which also assumes `http`/its own client stack,
not `dio`) for a 5-field-type protocol this app will only ever speak to one backend.

**Alternatives considered**: a third-party SSE package — rejected, new dependency, and every such package
assumes it owns the HTTP call itself, which would mean either a second client stack alongside `dio` or
fighting the package's API to reuse `ApiClient`'s existing auth/header logic; `package:http`'s
`Client.send()` + manual stream handling — rejected for the same "two HTTP stacks" reason, since `dio` can do
the identical byte-stream thing `ApiClient` already needs.

## R2 — What does each SSE event's `data` payload contain?

**Decision**: the five event types the sequence names (`message_created -> context -> token* -> done|error`)
carry JSON payloads inferred as follows, each parsed by `ChatRemoteDataSource` (never by the generic
`ApiClient.sseStream`, which only hands back `{event, data}` string pairs):

| Event | Assumed `data` shape | Used for |
|---|---|---|
| `message_created` | `{"userMessageId": "<uuid>", "assistantMessageId": "<uuid>"}` | Reconciling the two optimistic local placeholders (R5) with their real backend ids — `userMessageId` is also the exact value later needed as `POST .../retry`'s path parameter. |
| `context` | opaque/ignorable (spec.md's own Assumptions: "an internal signal the client may use to drive its own progress indicator, not a citation list") | Nothing beyond confirming the stream is progressing — no field is read. |
| `token` | `{"delta": "<string>"}` | Appended to the assistant placeholder's `content`, in arrival order. |
| `done` | `{"assistantMessageId": "<uuid>", "content": "<full final text>", "createdAt": "<ISO-8601>"}` | Finalizing the assistant message: status → `complete`, content replaced with the server's own authoritative final text (not just the locally-concatenated tokens, in case of any drift), timestamp set. |
| `error` (backend-named SSE event, business-level failure — distinct from a transport-level `DioException`) | the same `{code, message, retryable}` envelope every other endpoint's error body already uses | Mapped through the *same* `ErrorMapper.fromResponse` every other failure path uses, so `AI_GENERATION_TIMEOUT`/`RATE_LIMITED`/etc. all resolve to the one shared `Failure` taxonomy. |

**Rationale**: the OpenAPI schema is silent on field names (`schema: {type: string}` for the whole stream),
so this is squarely "where these documents are silent." The chosen field names follow this codebase's own
established conventions verbatim — every REST response already uses `userMessageId`/`assistantMessageId`-style
camelCase ids (e.g., `entries`'s `chatMessageId`), every error already uses `{code, message, retryable}`
(`error-taxonomy.md`), and `createdAt` is the exact field name `chat-messages-list`'s own response schema uses
for a message's timestamp. Re-using the identical error envelope for the backend-named `error` SSE event means
`ChatRemoteDataSource` needs exactly one error-parsing code path (`ErrorMapper.fromResponse`) for every
failure source in this unit — transport-level, business-level, and every other endpoint already built.

**Alternatives considered**: guessing a flatter shape (e.g., `token`'s data being the raw delta string, not
JSON) — rejected because every other endpoint in this contract wraps its payload in JSON, and an un-keyed raw
string would be the only exception; treating `done`'s `content` as redundant with the locally-concatenated
tokens and skipping it — rejected, since trusting the server's own final text over a client-side concatenation
guards against any dropped/reordered-token edge case with no added cost.

## R3 — Mid-stream `AUTH_EXPIRED` handling

**Decision**: `ChatRepository.sendMessage()`/`.retryMessage()` retries the *entire call* exactly once via
`SessionRepository.refresh()` — mirroring `EntriesRepositoryImpl._retryAfterSilentRefresh` — **only** when the
very first item the stream produces is `Left(AuthExpiredFailure)` (i.e., the stream failed before any
`ChatStreamEvent` was ever successfully emitted). If `AuthExpiredFailure` arrives after at least one
`ChatStreamEvent` has already been emitted (the turn is already visibly in progress), it is treated like any
other failure: `ChatBloc` marks that message's status as `failed` (the ordinary "Falha ao gerar resposta" path,
retryable by the user via the existing retry button) *and* separately fires `reauthRequired`, so the
app-wide "Sessão expirada" overlay still appears over the chat — it just does not auto-retry the
already-partially-generated response, which would otherwise risk silently regenerating/duplicating a response
the user never asked to retry.

**Rationale**: the "retry once if the very first attempt is `AuthExpiredFailure`" shape is this codebase's own
existing pattern for every other repository method; extending it unconditionally into "re-run a whole
streaming generation transparently after the user has already seen several tokens" is a materially different,
riskier behavior the spec never describes (FR-006 scopes retry explicitly to the "Falha ao gerar resposta"
tap, a user-initiated action). Keeping the two cases visually distinguishable (transparent retry only
pre-stream vs. surfaced failure + overlay once any token arrived) satisfies FR-005/FR-006 without inventing
mid-stream reconnection logic the OpenAPI contract gives no shape for.

**Alternatives considered**: always surfacing `AUTH_EXPIRED` as a plain failed-message state, never
transparently retrying it even pre-stream — rejected, it would make a session-boundary coincidence (the
access token expiring the instant `chat-messages-send` is called) indistinguishable from a real generation
failure, when every other read path in this app already recovers from that specific case silently.

## R4 — Local cache shape (`ChatLocalCache`)

**Decision**: one new Keychain-backed class, `lib/features/chat/data/chat_local_cache.dart`, mirroring
`EntriesLocalCache`'s pattern (`flutter_secure_storage`, JSON-encoded) but covering three independent pieces of
state, each under its own storage key so one write never clobbers another:
- `chatSessionsLocalCache` → `List<ChatSession>` — every session ever returned by any successful
  `chat-sessions-list` page fetch (merged by id, same `_mergeEntries`-style upsert `EntriesLocalCache` already
  does), satisfying Clarification 3's "the side menu's own session list... remain[s] browsable" while offline.
- `chatMessagesLocalCache` → `Map<String, List<ChatMessage>>` keyed by `sessionId` — written only when that
  specific session's `chat-messages-list` call succeeds, satisfying Clarification 3's "every chat session the
  user has opened at least once while online" (a session never individually fetched never gets a map entry, so
  selecting it offline has nothing to fall back to — the exact "standard no-connection state" Edge Case).
- `chatLastActiveSessionId` → `String?` — which conversation to resume on next app open (spec.md's own
  Assumptions: "Re-opening the app resumes whichever conversation the user was last in"), written every time
  `ChatBloc` successfully switches to or creates a session.

**Rationale**: journal/chat content is exactly the same class of personal data `EntriesLocalCache`'s own
rationale already covers ("personal data, so it stays encrypted at rest like the PIN it already sits behind")
— reusing the identical storage mechanism (not a plain file, not `shared_preferences`, which isn't a project
dependency and isn't encrypted) keeps one consistent at-rest-encryption story for every category of personal
content this app persists locally. Three separate keys (rather than one combined blob) mean a failed/partial
write to one never corrupts or need to recompute the other two, and each is independently simple to merge
(sessions: upsert-by-id like `EntriesLocalCache`; messages: replace-whole-list-for-this-session-id, since
`chat-messages-list` always returns the complete ordered history, never a page).

**Alternatives considered**: a single combined JSON blob (`{sessions: [...], messagesBySession: {...},
lastActiveSessionId: ...}`) under one key — rejected, since it would force rewriting the entire cache (all
sessions' full message histories) on every single page-list fetch, a much larger and slower encrypted write
for no benefit over three independent keys; `sqflite`/a real local database — rejected as a new dependency for
a cache whose total size (a handful of sessions, each a bounded message history) never approaches a scale
that benefits from indexed queries over simple JSON (de)serialization.

## R5 — Optimistic local ids for an in-flight message pair

**Decision**: the moment `MessageSubmitted`/`MessageRetryRequested` fires, `ChatBloc` immediately appends (for
a fresh send) a `ChatMessage(role: user, status: complete, id: 'local-<timestamp>', ...)` and a
`ChatMessage(role: assistant, status: streaming, id: 'local-<timestamp>-response', content: '', ...)` to the
in-memory list — satisfying RNF01's "<100 ms local reflection" before any network round-trip completes. Once
the stream's `message_created` event arrives, both placeholder ids are replaced in place with the real
`userMessageId`/`assistantMessageId` the backend assigned (same list position, same displayed content) — a
pure id swap, invisible to the user. A retry reuses the *existing*, already-real `userMessageId` (it is never
optimistic — retry only ever targets an already-persisted message from a prior turn) and appends only a new
optimistic assistant placeholder for the regenerated response.

**Rationale**: `Entry`/`EntriesRepositoryImpl.create()` already shows this app's established shape for "show
it instantly, reconcile with the server's real id once the call resolves" is not used there (that call isn't
streamed, so the UI simply waits for the single `Either`) — chat is the first flow where a network round-trip
is slow enough, and visibly multi-staged enough (RNF01's instant-local-reflection + the user-visible streaming
state, both before any id exists), that an optimistic placeholder is the only way to satisfy both at once. A
timestamp-prefixed string id needs no new dependency (no `uuid` package) and only ever needs to be
locally-unique for the lifetime of one `ChatBloc` instance, which `DateTime.now().microsecondsSinceEpoch` already
guarantees in practice.

**Alternatives considered**: adding the `uuid` package for a "real" UUID-shaped placeholder — rejected, the
id's only two jobs (equality-based list lookup during the swap, and being visibly distinct from every
server-issued id to avoid ever being sent to the backend by mistake) don't need UUID's collision guarantees at
this scale; waiting for `message_created` before showing anything — rejected, directly violates RNF01.

## R6 — Title-derivation algorithm (FR-010)

**Decision**: `ChatTitleDeriver.derive(String firstMessageText)` — a pure function in
`lib/features/chat/domain/entities/chat_title_deriver.dart` — collapses internal whitespace/newlines to single
spaces, trims, and caps the result at 48 characters, appending `'…'` when truncated. The result is always
non-empty by construction, because the composer already blocks sending empty/whitespace-only text (Edge
Cases) before `ChatBloc` ever calls this function.

**Rationale**: spec.md's own Assumptions explicitly leave "the exact wording of... the derived-title preview
length... a presentation detail left to implementation." 48 characters is chosen to comfortably fit the side
menu's "CONVERSAS" row (prototype-extract.md §2.2: "title + timestamp" on one line) without needing per-device
text-measurement logic — a fixed character cap, not a fixed pixel width, keeps the function pure and testable
(RNF07) with zero `package:flutter` dependency (Principle V). Collapsing whitespace/newlines avoids a
multi-line first message producing a title that visually breaks the single-line list row.

**Alternatives considered**: truncating by word boundary instead of a hard character cut — rejected as
unnecessary complexity for a preview whose only consumer is one list row with its own ellipsis-safe text
widget (`overflow: TextOverflow.ellipsis` already handles any remaining visual overflow regardless); no cap at
all (send the full first message as `title`) — rejected, defeats the point of a "preview."

## R7 — Two blocs, no new route; how "Novo Chat" and conversation-switching reach the chat screen

**Decision**: two blocs, both under `lib/features/chat/presentation/bloc/`: `ChatBloc` (the Home/Chat screen's
own conversation — messages, streaming, retry, composer gating, offline banner) and `ChatSessionsBloc` (the
side menu's "CONVERSAS" list — paginated, offline-cached, mirroring `RecordsBloc`'s own shape exactly). Both
are provided once, together, above `HomeChatShellPage`'s `Scaffold` (a `MultiBlocProvider`, replacing today's
bare `const HomeChatShellPage()` route builder in `app_router.dart`) — so `AppDrawer` (rebuilt as a
`StatefulWidget`) and the chat screen's own body share the *same* `ChatBloc` instance for the lifetime of one
visit to `/home`. "Novo Chat" and tapping a past conversation each dispatch directly to that shared `ChatBloc`
(`NewConversationRequested`/`ConversationSelected(sessionId)`) from inside `AppDrawer` — no new `go_router`
route, no `sessionId` path parameter; `AppRoutes.home` stays the single, unparameterized route it already is.
`ChatSessionsBloc` never imports or is imported by `ChatBloc` — `AppDrawer` is the one mediating widget (the
same sanctioned "cross-bloc touch point lives in `presentation/`, never inside a bloc" shape
`records_page.dart` already establishes for `RecordsBloc`/`SessionBloc`), and the drawer's own
`Scaffold.onDrawerChanged` callback dispatches `SessionsRefreshRequested` to `ChatSessionsBloc` every time the
drawer transitions from closed to open — so a session created moments earlier (by sending a first message) is
picked up the next time the user opens the drawer, with no cross-bloc event bus needed.

**Rationale**: `RecordsBloc` already proves "one bloc per screen-level concern, mediated by the widget layer
when two blocs' worlds touch" is this codebase's established shape; duplicating it for the side menu (instead
of cramming pagination/offline-list state into `ChatBloc` itself, which already owns a materially different
concern — one conversation's live streaming turn) keeps each bloc's test surface focused, exactly like
`RecordsBloc` staying independent of `SessionBloc`/`VaultBloc`. Treating Home/Chat as one persistent,
unparameterized screen that swaps its *content* in place (rather than navigating to a new route per
conversation) matches how the prototype itself describes it ("Tela 1" is one screen with internal states, not
N screens) and avoids inventing a routing concept (a `sessionId`-parameterized chat route) nothing in
`app_router.dart`'s existing five static routes needs elsewhere.

**Alternatives considered**: one combined `ChatBloc` owning both the live conversation and the side-menu list
— rejected, conflates two independently-paginated/independently-failing concerns into one state class, making
every `ChatReady`-consuming test also need to reason about session-list pagination; a bloc-to-bloc import
(`ChatSessionsBloc` emitting an event `ChatBloc` listens to directly) — rejected, same "no BLoC imports another
BLoC directly" shape RF07's own acceptance criterion already establishes as this codebase's convention, even
though the architecture test (`no_bloc_imports_bloc_test.dart`) only mechanically enforces it *across*
features; a new `/home/:sessionId` route — rejected, forces `go_router` to own "which conversation is open,"
duplicating state the bloc already needs to track for the composer-gating/streaming logic regardless.

## R8 — Live offline reactivity vs. the write-path pre-check

**Decision**: two complementary mechanisms, not one:
1. `ConnectivityChecker` (core/network, already used read-only via `hasConnection()`) gains
   `Stream<bool> get onConnectivityChanged`, wrapping `connectivity_plus`'s own `Connectivity
   ().onConnectivityChanged` broadcast stream (mapping "any non-`none` result" → `true`, same predicate
   `hasConnection()` already uses). `ChatBloc` subscribes to it once in its constructor, updating
   `ChatReady.isOffline` live — this is what drives the offline banner and the composer's disabled look
   appearing/disappearing with **zero** user interaction, satisfying SC-006's "re-enabling within one
   interaction of connectivity returning" trivially (zero still satisfies "within one").
2. Independently, every write path (`MessageSubmitted`, `MessageRetryRequested`, and the lazy session-create
   they trigger) still calls `ConnectivityChecker.hasConnection()` synchronously before attempting anything —
   the exact pre-check `SaveTextEntryUseCase` (RF01) already established for every write — so FR-012's "MUST
   be blocked client-side rather than attempted and failed" holds even in the (rare, platform-dependent) case
   where the live stream hasn't yet delivered a transition event.

**Rationale**: every existing write path in this app (`capture/`'s three use cases) already uses the
synchronous pre-check alone, because none of them needed to react to a connectivity change *while the screen
sits idle* — a modal is either opened online or not. Chat's own FR-011 is different: the banner and the
composer's disabled state must track connectivity *continuously* while the screen is simply sitting open, not
only at the moment of an attempted action, so a live stream is a new, genuinely necessary addition (not
duplicated effort) layered on top of the pre-check this app already trusts for the actual gating decision.

**Alternatives considered**: a periodic `Timer.periodic` poll of `hasConnection()` instead of
`connectivity_plus`'s own change stream — rejected, strictly worse (polling delay vs. an OS-level push
notification the package already wraps) for no benefit, and `connectivity_plus` is already a project
dependency; relying on the live stream alone, dropping the synchronous pre-check — rejected, FR-012 asks for a
guarantee ("MUST NOT attempt"), and a stream subscription racing against a fast tap is a weaker guarantee than
a synchronous check immediately before the call.

## R9 — Single-flight-per-conversation gating (FR-007)

**Decision**: `ChatReady` carries one `bool awaitingResponse` (true from the moment a send/retry is dispatched
until that turn's stream reaches `done`/`error`). The composer widget disables itself whenever
`awaitingResponse || isOffline`. No generation counter is needed (unlike `RecordsBloc`'s `_fetchGeneration`):
`RecordsBloc` needs one because *reads* can be superseded by a newer, unrelated read firing before the old one
resolves; here, the composer being disabled while `awaitingResponse` is true means a second
`MessageSubmitted`/`MessageRetryRequested` physically cannot fire for the same conversation until the first
one resolves — there is never a second in-flight write to supersede.

**Rationale**: FR-007 itself states the goal as "a single conversation never has two responses in flight at
once," which disabling the one entry point that could start a second one already guarantees by construction,
simpler than tracking and discarding a superseded response that this design never allows to start.

**Alternatives considered**: reusing a `RecordsBloc`-style generation counter defensively, in case some future
code path bypasses the composer's disabled state — rejected as unneeded defensive complexity; the one
dispatch site for each event lives entirely inside this unit's own two widgets, both of which already read
`awaitingResponse` to decide whether to even allow the tap.

## R10 — Matching a retry's result back to the right message by position, not by assuming id-reuse

**Decision**: `ChatBloc` tracks, per in-flight or just-failed turn, the **index** of the assistant message in
its `messages` list (not just its id) when dispatching `MessageRetryRequested(userMessageId)`. The retry's
eventual `done`/`error` outcome replaces whatever is at that same index with a freshly-constructed
`ChatMessage` — regardless of whether the backend's `message_created` event for the retry returns a brand-new
`assistantMessageId` or (hypothetically) reuses the original failed message's id, since neither OpenAPI nor
`error-taxonomy.md` states which.

**Rationale**: the contract is silent on this specific detail (`chat.messages.retry`'s summary only says "the
original question... rather than a new message pair" — about the *question* not duplicating, not about the
*response*'s id semantics). Matching by list position rather than by asserting a specific id-reuse behavior
means this unit's own logic doesn't accidentally depend on an assumption the backend's actual implementation
might not share; Acceptance Scenario 2 ("the user's original question appears exactly once") is satisfied
regardless, since the question itself is never re-appended on a retry — only the one response slot is ever
replaced.

**Alternatives considered**: asserting the retry's `assistantMessageId` always equals a previous attempt's —
rejected, an unverifiable assumption about backend internals; appending a brand-new response message after the
failed one instead of replacing it in place — rejected, directly contradicts FR-006 ("MUST NOT duplicate the
user's original question... only replaces the failed answer with a new attempt") and Acceptance Scenario 2.

## R11 — A `GET`-sourced `status == 'streaming'` row (Edge Cases: navigating away mid-stream)

**Decision**: when `chat-messages-list` is fetched (on first opening a conversation, or re-opening one after
navigating away) and a returned message's `status` is `streaming` even though this `ChatBloc` instance has no
active SSE subscription for it, it is rendered as a static, non-interactive variant of the streaming bubble —
pulsing-cursor visual, but no token updates ever arrive and it is **not** tappable (it is neither `complete`
nor `failed`, so none of FR-004's two end-state renderings nor FR-006's retry affordance apply to it). No
polling, no reconnect-to-stream attempt is built for this case.

**Rationale**: the Edge Case itself only requires that *returning* to the conversation shows "whatever the
backend ultimately recorded for it (complete or failed)" — by the time a user navigates away and back (even
quickly), the backend-side generation has almost always already finished, since nothing in this unit's design
cancels the backend's own generation just because the app stopped reading its SSE response (closing the local
`dio` stream subscription does not and cannot command the backend to stop). A literal `status: 'streaming'`
read from a fresh `GET` is therefore an exceptionally narrow race (returning within the same second generation
started) that the spec's own wording ("the message reflects whatever the backend ultimately recorded") doesn't
actually require resolving instantly — the next time that conversation is opened or refreshed, the status will
have settled. Building a reconnect/poll mechanism for a transient race nothing in spec.md, the OpenAPI
contract, or the prototype describes would be speculative scope the spec doesn't ask for.

**Alternatives considered**: polling `chat-messages-list` every N seconds while any message shows `streaming`
— rejected as unspecified scope/complexity (no interval is defined anywhere, and it would need its own
start/stop lifecycle tied to screen visibility); treating a `streaming`-status row from `GET` as `failed` —
rejected, actively misleading (it may well complete successfully a moment later, and nothing failed).

## R12 — Client-side message-length handling (Edge Cases: near/at the backend's maximum)

**Decision**: the composer enforces `maxLength: 8000` directly on its `TextField` (the exact value
`chat.messages.send`'s request schema already declares), via Flutter's own `maxLength` property — the OS
keyboard/field simply stops accepting further input past that point, so a `VALIDATION_ERROR` for "too long" is
structurally unreachable from this screen, and no text the user already typed is ever lost (there's nothing to
lose — input beyond the cap was never accepted into the field to begin with).

**Rationale**: Edge Cases' own wording offers two acceptable shapes ("prevents exceeding that maximum before
sending" **or** "surfaces the backend's resulting validation error clearly") — preventing is strictly simpler
than building a distinct inline-error presentation for one specific, fully-avoidable `VALIDATION_ERROR` case,
and `TextField.maxLength` is a built-in Flutter mechanism, not a new dependency or hand-rolled validator.

**Alternatives considered**: no client-side cap, relying on the backend's `VALIDATION_ERROR` response and
showing it as a send-failure banner — rejected as strictly more implementation (a new error-presentation path)
for a worse user experience (typing 8000+ characters only to have the send rejected) than simply not accepting
the 8001st character.

## R13 — Why no extra use-case classes beyond `ChatTitleDeriver`

**Decision**: `ChatBloc`/`ChatSessionsBloc` call `ChatRepository`'s methods directly and own all orchestration
themselves (lazy session creation before the first send, optimistic placeholders, title derivation, retry
position-matching) — the same shape `RecordsBloc` already uses (it depends only on `EntriesRepository`, with
no intervening use-case layer). The one pure, non-trivial piece of logic genuinely independent of any bloc —
`ChatTitleDeriver.derive()` — is pulled out as its own domain entity/function specifically because RNF07
(≥80% domain coverage) needs something directly unit-testable with zero bloc/repository scaffolding, exactly
like `date_range_filter.dart`/`active_filter_chip.dart` (RF06) and `entry_merger.dart` (RF07) already are.

**Rationale**: `capture/`'s use-case classes (`SaveTextEntryUseCase`, etc.) exist because `InsertionModalBloc`
is shared across several structurally different tabs/flows, each needing its own small, independently-testable
"what does Save actually do here" unit; `ChatBloc` has no such multi-flow fan-out — every event it handles
belongs to the one conversation screen's one flow. Introducing a use-case class per event here (e.g.,
`SendChatMessageUseCase`) would wrap a single repository call in an extra indirection layer with no behavior
of its own beyond what the bloc's handler already needs to do inline (append the optimistic placeholder,
subscribe to the stream, update state per event) — exactly the "don't design for hypothetical future
requirements" judgment `RecordsBloc` already made for RF06/RF07's own orchestration.

**Alternatives considered**: a `SendChatMessageUseCase` wrapping `ChatRepository.sendMessage()` purely for
symmetry with `capture/`'s pattern — rejected as an abstraction with no distinct responsibility of its own,
adding a file and a DI registration for no testability gain `ChatBloc`'s own tests don't already get by
mocking `ChatRepository` directly (the same level `RecordsBlocTest` already mocks `EntriesRepository` at).
