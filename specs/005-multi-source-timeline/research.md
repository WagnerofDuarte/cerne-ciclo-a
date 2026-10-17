# Research: P-RF07 — Multi-source history (timeline)

All unknowns below are implementation judgment calls on top of an already-resolved spec (spec.md's four
Clarifications) and an already-built F000/RF01 foundation — there is no new external service to evaluate, and
only one small, well-known package decision (rejected, R9). Each entry either extends an existing RF01/F000
seam to a new, previously-unneeded shape, or fills a gap spec.md leaves to "reasonable technical decision"
(Constitution Principle I).

## R1 — `ApiClient` gains query-parameter support

- **Decision**: `ApiClient.call()` gets one new optional parameter, `Map<String, dynamic>? queryParameters`,
  passed straight through to `Dio.request()`'s own `queryParameters` argument. Every existing call site is
  unaffected (the parameter defaults to omitted/null).
- **Rationale**: `GET /entries` (`entries-list`) is this unit's first call whose OpenAPI contract defines
  `in: query` parameters (`cursor`, `limit`, plus `source`/`dateFrom`/`dateTo` this unit never sends). Every
  endpoint called before this unit (`entries-create`, `auth-session`, `auth-refresh`, `media-ocr`) needed only a
  body and/or `pathSegments`, so `ApiClient` never had a reason to carry query parameters. This is a change to
  the app's own HTTP wrapper, not to the backend or its contract (Constitution Principle III is about the
  backend's contract, not this client-side plumbing).
- **Alternatives considered**: Hand-building the query string and appending it to the URL — rejected: `dio`
  already does this correctly (encoding, `null`-param omission), and bypassing it would be duplicating
  something the dependency already does for free.

## R2 — `EntrySource` gains a fourth value, `chat`

- **Decision**: `enum EntrySource { manual, audio, photo, chat }` in `entries/domain/entities/entry.dart` —
  the one line RF01's own comment flagged as "`chat` is RF10's own addition" is now wrong in isolation and
  gets updated to explain *why* a fourth value exists here even though no capture flow produces it yet.
- **Rationale**: spec.md's Edge Cases and Assumptions are explicit: `GET /entries` is origin-agnostic and can
  return a `chat`-sourced entry (e.g., from seed/test data) even though RF04/RF10 (the only features that will
  ever *create* one) are both later units; this screen "renders the card with the origin's defined marker and
  icon like any other, without erroring or treating it as unrecognized." `EntriesRemoteDataSource._parseEntry`
  currently calls `EntrySource.values.byName(...)`, which throws `ArgumentError` — not caught by its existing
  `on TypeError`/`on FormatException` clauses — for any value outside the enum's current 3. Without this
  change, a `chat` entry from the backend would crash parsing instead of rendering, directly contradicting the
  Edge Case. No other `Entry` field changes; `serverRevision`/`updatedAt` are already present from RF01 and
  are exactly `sync-badge.md`'s two fields.
- **Alternatives considered**: Leaving the enum at 3 values and adding a defensive `on ArgumentError` catch
  that falls back to some generic/"unknown" rendering — rejected: the OpenAPI contract closes the `source`
  enum at exactly 4 values (`manual`/`audio`/`photo`/`chat`), so there is no fifth value to defend against;
  adding a catch-all for a case that cannot occur per the frozen contract would be exactly the kind of
  speculative error handling the project's own guidance says to avoid.

## R3 — Local-cache ∪ fetched-page merge lives in the `records` feature, not `EntriesRepositoryImpl`

- **Decision**: `EntriesRepositoryImpl` gains `list()`/`getById()` as plain fetch methods — neither one reads
  nor touches `cachedEntries`. The by-ID dedupe spec.md's Clarification 3 resolves (prefer the freshly-fetched
  copy's `updatedAt`/`serverRevision` when the same ID appears in both the local cache and a fetched page) is
  implemented once, as a small pure function (`EntryMerger`, data-model.md) inside the new `records/domain/`,
  and called by `RecordsBloc` every time it has a new batch of entries to show.
- **Rationale**: `cachedEntries`'s own doc comment already says it exists only "so RF07 has something to read
  from day one" — reading it is this unit's job, not something `EntriesRepositoryImpl.list()`'s *fetch*
  responsibility should also carry. Keeping the merge in `records/` keeps `EntriesRepositoryImpl` a simple,
  single-purpose data accessor (unchanged shape for `create()`/`cachedEntries`, two new fetch methods) and
  keeps the one genuinely screen-specific rule (how a locally-created entry and a later server page reconcile)
  local to the one screen that actually needs it.
- **Alternatives considered**: Merging inside `EntriesRepositoryImpl.list()` itself, returning an
  already-deduped `EntriesPage` — rejected: `list()` would then need to special-case "is this the first page"
  (merging the cache into every subsequent page would re-surface an old locally-created entry on whatever page
  its `occurredAt` now falls on, which is fine, but silently entangles a generic fetch method with one
  screen's presentation-level display-ordering concern) for no benefit, since `records/` is the only present
  or planned caller of `list()`.

## R4 — Silent `AUTH_EXPIRED` refresh-and-retry lives inside `EntriesRepositoryImpl`, reusing `SessionRepository.refresh()` directly

- **Decision**: `EntriesRepositoryImpl.list()` and `.getById()` each: call the remote method once; on
  `Left(AuthExpiredFailure)`, call the already-injected `SessionRepository.refresh()`; on `Right`, retry the
  original remote call exactly once and return *that* result; on `Left` (refresh itself did not succeed),
  return `Left(const AuthExpiredFailure(...))` (a fresh instance carrying this call's own `requestId`,
  regardless of what specific failure the refresh attempt itself produced). `create()` is untouched — this
  unit's scope is its two new read methods, not retrofitting RF01's existing write path.
- **Rationale**: This is not a new pattern — `specs/001-foundation/contracts/session-repository.md` already
  says, verbatim, "Every later unit that makes an authenticated call and receives `AuthExpiredFailure` calls
  `SessionRepository.refresh()` the same way, through this interface — never by re-implementing the refresh
  call." RF07 is simply the first unit to actually be that "later unit." Doing it inside `EntriesRepositoryImpl`
  (not a `records`-specific use case) means the silent-renewal behavior FR-006 requires is automatically
  available to RF06 (semantic search, also `bearerAuth` over `/entries` data) the moment it's built, with zero
  duplication. `EntriesRepositoryImpl` gains one new constructor dependency, `SessionRepository` — a
  cross-feature *domain*-interface dependency from one feature's data layer into another's, the same shape
  `SessionRepositoryImpl` itself already has on `auth`'s `Account` entity, so this introduces no new kind of
  coupling, only a new instance of an already-approved one.
- **Alternatives considered**: Dispatching an event to the global `SessionBloc` instead and awaiting its
  outcome — rejected outright: that would make a `data/`-layer repository depend on a `presentation/`-layer
  BLoC, a far more serious layering violation than anything RNF06 is written to catch, and the repository has
  no `BuildContext`/widget tree to dispatch through in the first place.

## R5 — Routing the "Sessão expirada" overlay trigger through the page, not bloc-to-bloc, via a one-shot stream

- **Decision**: `RecordsBloc` exposes `Stream<void> get reauthRequired` — a one-shot side-effect stream,
  fired exactly when R4's silent refresh-and-retry has already failed (i.e., whenever `list()`/`getById()`
  comes back `Left(AuthExpiredFailure)` after that retry). `RecordsPage` subscribes to it in `initState` and,
  on each event, calls `context.read<SessionBloc>().add(const AuthExpiredDetected())` — the exact event
  `SessionBloc` already defines for "Raised by any authenticated call elsewhere in the app that comes back
  AUTH_EXPIRED," unused by any unit until now. `RecordsBloc` itself never imports `SessionBloc`, its event, or
  its state — only `RecordsPage` (a `StatelessWidget`/`State`, not a BLoC) does, which is what makes
  `requirements.md`'s own acceptance criterion ("No BLoC imports another BLoC directly") literally true, not
  just avoided by indirection.
- **Rationale**: This mirrors an already-shipped precedent in this exact codebase almost exactly:
  `InsertionModalBloc.closeRequests` is documented as "a one-shot side effect, not a state... `InsertionModalPage`
  listens to this to pop the sheet. There is nothing to render for 'success,' so it never becomes a dedicated
  state." The same reasoning applies here: "the session could not be silently renewed" is a one-shot trigger
  for an app-wide overlay, not a `RecordsState` worth rendering in `RecordsPage` itself. Because the stream
  fire doesn't mutate `RecordsState.entries`/scroll bookkeeping at all, FR-007's "without discarding the
  entries already loaded or the current scroll position" is satisfied *by construction* — nothing about the
  screen's own state ever changes because of this event, exactly as "the screen MUST be restored exactly as it
  was" (there is nothing to restore; it was never altered). The existing `showSessionExpiredOverlay` mechanism
  already raises its dialog through the *root* `navigatorKey` (research.md R3 in specs/001), so it paints over
  `RecordsPage` without ever disposing its `State`/`ScrollController` underneath — the same reason this already
  works for Home/Chat today.
- **Alternatives considered**: Having `RecordsBloc` import `SessionRepository` and call `refresh()` a second
  time itself before firing the stream — rejected: R4 already performed exactly one silent-refresh attempt
  inside `EntriesRepositoryImpl`; a second attempt at the `RecordsBloc` layer would just repeat the same
  already-known-to-fail call. The one redundant `refresh()` call that *does* happen (inside `SessionBloc`'s own
  `AuthExpiredDetected` handler, which has no way to know R4 already tried) is accepted as a minor, bounded
  inefficiency — building a new cross-feature "don't refresh twice" signal just to shave one network round
  trip off an already-rare path (session expiring mid-browse) is not worth the added coupling.

## R6 — Sync badge derivation: a complete, correct, 3-state pure function this unit's own flows can only ever drive to one of them

- **Decision**: `SyncBadge.derive(LocalWriteOutcome? localWrite)` (data-model.md) is a pure, total function
  over `sync-badge.md`'s model: `null` → `synchronized`; `pending` → `synchronizing`; `failed` → `error`.
  `RecordsBloc` calls it with `localWrite: null` for every entry it ever renders — both branches of its data
  (`EntriesRepository.list()`'s results and `.cachedEntries`) are, by construction, already server-confirmed
  before `RecordsBloc` ever sees them (RF01's `create()` only appends to `cachedEntries` *after* the backend
  responds; a fetched `Entry` is by definition already persisted). No locally-pending or locally-failed write
  exists anywhere in this unit for any entry it can show.
- **Rationale**: spec.md's own Assumptions section says this plainly: "'synchronizing' and 'synchronization
  error' ... may rarely or never be observed through today's own capture flow alone — that does not make
  their correct implementation optional." The function above *is* that correct implementation — complete,
  exhaustive over the 3 states, computed from nothing but device-local state (never from the session/auth
  stream, trivially satisfying FR-005's independence requirement since the function takes no session-related
  input at all) — while being honest that, today, only one of its three branches is ever actually reached.
  Building a notional "pending-write tracker" with no real producer, just so the other two branches could be
  exercised by this unit, would be exactly the kind of speculative infrastructure the project's guidance says
  not to build for a hypothetical future need; the next unit that introduces a real pending/failed local write
  (most plausibly RF10's retryable save-as-entry) supplies a real `LocalWriteOutcome` into this same function
  without it needing to change at all.
- **Alternatives considered**: Hardcoding every badge to "synchronized" in `RecordsBloc` with a comment
  pointing at a future unit — rejected: that would leave the *computation* (not just its current inputs)
  incomplete, which is what the Assumptions bullet explicitly forbids.

## R7 — `GET /entries/:id` is implemented and tested on the repository, with no call site inside this unit's UI flow

- **Decision**: `EntriesRepository.getById(String id)` is implemented (`EntriesRemoteDataSource`/
  `EntriesRepositoryImpl`, same R4 silent-refresh-and-retry) and unit-tested on its own. No widget, bloc event,
  or usecase in this unit calls it.
- **Rationale**: spec.md's resolved Clarification 2 is explicit that this endpoint exists here "to re-confirm
  the state of one specific, already-loaded entry during reconciliation... rather than re-fetching the entire
  paginated list" — but `requirements.md` §9 states entries are immutable ("there is no `PATCH /entries/:id`
  or `DELETE /entries/:id` in the backend"), and R6 just established that no entry this unit can ever render
  has a pending/unreconciled local write to begin with. Put together: there is no server-side mutation an
  already-confirmed entry could ever need re-confirming *against* in this unit, and no locally-unreconciled
  entry to trigger a reconciliation in the first place — so a reconciliation call that genuinely needs to fire
  cannot arise from any flow this unit implements. Implementing and testing the method keeps the explicit
  backend dependency this unit's own spec header lists (`GET /entries/:id`) real and ready, exactly as R6 keeps
  the badge computation ready for a producer that doesn't exist yet, without inventing a call site that would
  just be dead weight dressed up as a feature.
- **Alternatives considered**: Wiring a call to `getById()` immediately after the "Sessão expirada" overlay
  dismisses, "just in case" — rejected: there is nothing for it to reconcile (immutable entries, no pending
  local writes), so the call would always return data already identical to what's on screen; adding a network
  round trip with no possible observable effect is not a real feature, just unnecessary traffic.

## R8 — Reusing `records/` as the feature folder, not introducing a new `timeline/` feature

- **Decision**: This unit's presentation/domain code lives in the already-existing
  `lib/features/records/` folder (today holding only `RecordsPlaceholderPage`, F000's navigable stub),
  not a new `lib/features/timeline/`. `records_placeholder_page.dart` is deleted outright, replaced by
  `records_page.dart` plus the new `domain/`/`presentation/bloc/`/`presentation/widgets/` content documented
  in data-model.md. `records/` has no `data/` folder — it introduces no data source or repository of its own,
  fully delegating to `entries/`'s existing one, the same partial-layer shape `home/` already has today
  (`lib/features/home/` is `presentation/`-only).
- **Rationale**: Every product-facing name for this screen — the spec's own title ("Tela 4 — Meus Registros"),
  the route (`AppRoutes.records`), the drawer item ("Meus Registros"), and the folder F000 already created —
  is "records," not "timeline." "Multi-source timeline" is `requirements.md`'s RF07 section title and this
  spec folder's own name, describing what the screen *shows* (every source, chronologically), not a second
  in-code identity to maintain alongside the one that already exists. Introducing `timeline/` would split one
  screen's code across two feature folders with no actual boundary between them.
- **Alternatives considered**: Renaming `records/` to `timeline/` for closer alignment with this spec's own
  folder name — rejected: it would touch the route constant, the drawer, and every existing reference to
  `RecordsPlaceholderPage` for a purely cosmetic rename with no architectural benefit.

## R9 — Date-group labels are a small hand-written lookup, not a new `intl` dependency

- **Decision**: `DateGrouper` (data-model.md) computes "Hoje"/"Ontem"/an explicit date itself, comparing each
  entry's `occurredAt.toLocal()` calendar day against `DateTime.now().toLocal()`'s. The explicit-date case is
  formatted as `'{day} de {monthName}'` (e.g., "14 de outubro") from a 12-entry `const` Portuguese month-name
  list local to this file — no year shown, matching the prototype's own plain "dates" wording with no sample
  format shown. `pubspec.yaml` gains no new dependency.
- **Rationale**: This app has never needed locale-aware date formatting before (every existing timestamp —
  the audio recorder's `00:12`, `expected-transcription.md`'s fixtures — is either monospace-counter or raw)
  and needs only 12 fixed Portuguese month names here, a one-time, never-changing lookup table far smaller
  than what pulling in `intl` (locale data, `DateFormat`, ICU plural rules) would justify for a single call
  site.
- **Alternatives considered**: Adding `intl` — rejected per the above; a `dd/MM/yyyy` numeric format instead
  of a written-out month name — rejected as a visual-fidelity concern: `prototype-extract.md`'s "Ontem" /
  "Hoje" labels read as prose, not as a numeric field, so an explicit older date is written the same way for
  consistency within the same date-heading row.

## R10 — Extracting `openInsertionModal()` once, shared by Home/Chat and "Meus Registros"'s empty state

- **Decision**: The existing private `_openInsertionModal()` in `home_chat_shell_page.dart` is promoted to a
  single public function in `capture/presentation/widgets/open_insertion_modal.dart` — identical body (the
  same `showModalBottomSheet`/`BlocProvider<InsertionModalBloc>`/`InsertionModalPage` it already is), called
  from both `home_chat_shell_page.dart`'s "+" button and `records_page.dart`'s empty-state "Criar primeiro
  registro" CTA (spec.md FR-004, Clarification 1). `RecordsPage` awaits the `Future` `showModalBottomSheet`
  returns and, once it resolves (the sheet popped itself on a successful save — unchanged RF01/RF02 behavior,
  `insertion_modal_page.dart`'s `closeRequests` listener), dispatches a `RecordsLocalCacheRefreshed` event so
  the newly created entry (already appended to `EntriesRepository.cachedEntries` by the time the sheet closes)
  is merged into view (R3) without any network call.
- **Rationale**: Clarification 1 already settles *where* a save from here returns to — "this screen, not
  Home/Chat" — and the mechanism for that is simply "don't navigate away to open it": `showModalBottomSheet`
  always pops back onto whichever screen presented it, so calling the exact same opening function from
  `RecordsPage` already produces the required return-to-this-screen behavior with zero new routing. Once there
  are 2 call sites for an identical 4-line function, extracting it is the same bar RF02's research.md R7 used
  for consolidating two near-duplicate usecases — not a premature abstraction, since both call sites really are
  identical.
- **Alternatives considered**: Duplicating the 4-line `showModalBottomSheet` call in `records_page.dart`
  instead — rejected once there are genuinely two identical call sites; three similar-but-different lines
  would be fine, but these would be the same lines twice.

## R11 — No pre-emptive connectivity gate before fetching a page

- **Decision**: Neither `EntriesRepositoryImpl.list()` nor `RecordsBloc`'s page-fetch handling calls
  `ConnectivityChecker` before attempting the network call. Offline is detected the same way it already is for
  every other call through `ApiClient`: a `DioException` with no response at all is already synthesized into
  `NetworkOfflineFailure` by `ApiClient._mapException` (existing code, unchanged).
- **Rationale**: RF01/RF02's pre-write connectivity checks (`SaveTextEntryUseCase`, `ConfirmEntrySaveUseCase`)
  exist specifically to avoid burning an expensive *local* operation (on-device transcription, OCR) ahead of a
  write that would fail anyway — there is no equivalent local cost to protect before a plain `GET`. Attempting
  the call and letting the existing offline-failure path handle it is simpler and reuses infrastructure that
  already satisfies FR-009 ("fails with a clear, retryable message rather than hanging or crashing") with zero
  new code.
- **Alternatives considered**: Adding the same `ConnectivityChecker` pre-check "for consistency with
  capture" — rejected: it would add a dependency and a code path that exists purely to skip a call that costs
  nothing to attempt and already fails cleanly on its own.
