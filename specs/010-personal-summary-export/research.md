# Research: P-RF05 — Personal summary export

Phase 0 output. Each item is a reasonable technical decision made under Constitution Principle I ("where
these documents are silent, implementers MUST make a reasonable technical decision rather than block on
clarification"). None reopens spec.md's own already-resolved Clarification (the FR-007 full-failure state) —
each item below fills in a mechanical detail that Clarification, the OpenAPI contract, `export-screen-
states.md`, or the prototype extract leaves open.

## R1 — How the download endpoint's 302-redirect-to-signed-URL is fetched without leaking auth headers

**Decision**: `ApiClient` (core/network) gains one new method, `downloadFile(...)`, built the same way
`sseStream()` (RF04) added a second transport shape on top of the existing `call()` — a two-step fetch, never
a single `Dio.request<Map>()` (which expects JSON and would fail to parse PDF/raw bytes):
1. Request `GET /export/{jobId}/download?format=pdf|raw` with `followRedirects: false` and
   `validateStatus: (status) => status != null && status < 400` (so a 302 is accepted, not thrown as a
   `DioException`), sending the same `apikey`/`Authorization` headers every other call already sends — this
   leg talks to *our* backend function, so it goes through the exact same auth story as `call()`.
2. Read the `Location` response header. If the status was not 302 or the header is missing, treat it as a
   malformed response (`ValidationFailure`) — the backend's own contract only documents a 302 success shape.
3. Issue a **second**, header-less `Dio.request<List<int>>()` straight to that signed Storage URL, with
   `responseType: ResponseType.bytes` and no `apikey`/`Authorization` headers at all.
4. Return `Either<Failure, Uint8List>` — `Right(bytes)` on a 2xx from step 3; any failure from either leg maps
   through `_mapException` (step 1: identical to `call()`'s existing JSON-error path, so `AUTH_EXPIRED`/
   `NOT_FOUND`/etc. all resolve through the normal `ErrorMapper`) or a new, generic retryable
   `NetworkTimeoutFailure` (step 2/3: the storage leg never speaks this app's `{code, message, retryable}`
   error envelope, so there is nothing for `ErrorMapper` to parse — Edge Cases only asks that "the
   corresponding button returns to a retryable state", not that the exact backend error code survive a
   fetch that never reached the backend).

**Rationale**: the signed URL already encodes its own short-lived auth via query parameters (that is the
entire point of a signed URL); forwarding this app's `apikey`/`SUPABASE_ANON_KEY`/user bearer token to a
third-party Storage host it was never intended for is an unnecessary credential-exposure surface Principle
III's spirit ("narrowly-accessed contract... prevents... credential leakage") argues against, and `dio`'s
default redirect-following would do exactly that by keeping the original request's headers across the
redirect. Disabling auto-redirect and manually re-issuing a clean request is the only way to control which
headers reach which host. This mirrors `sseStream()`'s own precedent of adding a second, download-agnostic
transport primitive to `ApiClient` rather than growing a parallel HTTP stack per feature.

**Alternatives considered**: letting `dio` auto-follow the redirect — rejected for the header-leak reason
above; a dedicated plain `http`/`http_client` package call for the storage leg — rejected, `dio` already does
a header-less byte-stream GET with no new dependency; parsing the Storage response as JSON first — rejected,
both `format=pdf` and `format=raw` are binary/text payloads to save to disk, not API responses with a
`{data: ...}` envelope.

## R2 — Saving/sharing the downloaded bytes (no download/file package exists yet)

**Decision**: add `share_plus: ^13.3.1` (new dependency; `path_provider` is already in `pubspec.yaml`, added
for the audio pipeline). A new data-layer class, `ExportFileRepositoryImpl` (behind a domain interface,
`ExportFileRepository`, so `ExportBloc` depends on it through the same mockable-repository shape every other
bloc already uses — never a bare plugin wrapper), writes the downloaded bytes to
`(await getTemporaryDirectory()).path` under a derived filename, then calls `Share.shareXFiles([XFile(path)])`
— the OS share sheet, satisfying the Assumption "trigger[s] the platform's standard way of saving or sharing a
downloaded file." The extension is taken from the response's own `content-type`/`content-disposition` header
when present, falling back to `.pdf` for `format=pdf` and `.json` for `format=raw` (every other endpoint in
this backend's contract speaks JSON; nothing in the OpenAPI spec names a different shape for the raw export).

**Rationale**: Constitution Principle II explicitly leaves "local cache... secure storage" (and, by the same
"choices not fixed here" logic, a file-share mechanism — no fixed package is named for this anywhere in
`docs/input/`) as an open implementation decision, the same category `image_picker`/`record`/`whisper_ggml`
were already added under in earlier units. `share_plus` is the de-facto standard Flutter package for exactly
this job (iOS `UIActivityViewController`), needs no new permission beyond what sharing already implies, and
composes with the already-present `path_provider` rather than introducing a second temp-file mechanism.

**Alternatives considered**: `open_file`/`open_filex` (opens a file in another app directly rather than
offering the OS share sheet) — rejected, narrower than "save or share" and typically requires a file-
association/viewer app to exist, which this PDF-generating unit cannot assume; writing to a permanent
app-documents path and leaving the user to find it in Files.app — rejected, no in-app file browser exists or
is in scope (Assumptions: "not responsible for building a custom in-app file viewer"), so a silent write with
no share/save prompt would be a dead end for the user.

## R3 — Status-polling mechanism and interval

**Decision**: `ExportBloc` polls `GET /export/{jobId}/status` through a self-rescheduling chain of internal
events, not `Timer.periodic` — the exact shape `RecordsBloc`'s own search debounce already establishes
(`Timer(duration, () => add(Event()))`, re-armed from inside the handler, cancelled in `close()`). The instant
`ExportRequested` is handled, the bloc emits `ExportPending()` synchronously (FR-004's "immediately after the
request"), awaits the `POST /export/summary` call, and on success immediately dispatches one
`ExportStatusPollTicked()` (no initial delay — the POST round-trip has already elapsed). Each tick's handler
calls `GET status` once; if the resulting job is not yet in a terminal state (`sheetState` below), it arms
`Timer(const Duration(seconds: 2), () => add(const ExportStatusPollTicked()))` for the next tick. Sequential,
never overlapping — a slow response is fully awaited before the next tick is even scheduled.

**Rationale**: spec.md's own Assumptions state this interval is "an implementation detail, not a product
requirement, as long as it is frequent enough that the user does not perceive the sheet as stuck" — 2 seconds
comfortably satisfies that for an AI-narrative job (seconds-to-tens-of-seconds scale) without hammering the
backend. Routing every tick through the bloc's own event pipeline (rather than a bare `Timer` mutating state
directly) keeps `ExportBloc` testable with `bloc_test` the same way `RecordsBloc`'s debounce already is —
`add()` from a `Timer` callback is this codebase's own established pattern, not a new one.

**Alternatives considered**: `Timer.periodic` — rejected, risks overlapping requests if a status call ever
takes longer than the interval (the sequential self-reschedule shape cannot overlap by construction); a
shorter interval (e.g. 500 ms) — rejected as needless backend load for a job whose fastest realistic path
(empty-period) never reaches polling at all (R6) and whose slowest path is bounded by an AI call, not network
latency.

## R4 — `ExportJob`'s pure sheet-state derivation, and the sixth, Clarification-resolved state

**Decision**: a pure domain extension, `ExportJob.sheetState`, mirrors the already-established
`DateRangeBounds.boundsAt`/`SyncBadge.derive` pattern (a total function over an enum, zero I/O, directly
unit-testable for RNF07) and implements `export-screen-states.md`'s table verbatim:

| `status` | `narrativeStatus` | `sheetState` |
|---|---|---|
| `pending` | (any) | `pendente` |
| `processing` | (any) | `processando` |
| `dataReady` | `processing` | `processando` (Assumption: no early download link; still visually "Processando") |
| `done` | `done` | `concluido` |
| `done` | `failed` or `skipped` | `erroNarrativa` (FR-006 — the prototype's single "Erro" state) |
| `error` | — | `erroCompleto` (FR-007 — the Clarification-resolved sixth state) |

`erroCompleto` is a distinct enum value from `erroNarrativa` even though the prototype's own catalog names
only one "Erro" state — this directly encodes spec.md's resolved Clarification ("reusing the error color/icon
family, with copy distinct from FR-006's... no PDF/raw buttons, and only... Fechar"). `ExportBloc` additionally
reaches `erroCompleto` from two paths `ExportJob.sheetState` never sees at all, because no job/jobId exists
yet at that point: an `EXPORT_EMPTY_PERIOD`-shaped `POST` failure instead maps to a seventh, job-independent
bloc state, `periodoVazio` (R6), and any *other* `POST /export/summary` failure (timeout, offline, rate-
limited, ...) maps directly to the bloc's `erroCompleto` state without ever creating a job (R6).

**Rationale**: putting the five-row mapping in the domain layer as a pure getter (not duplicated inline in
`ExportBloc` or a widget's `switch`) is the same choice `RecordsBloc` already made for `SyncBadge.derive` and
`DateRangeBounds` — directly testable, and the one place this mapping's correctness is asserted. Keeping
`erroCompleto`/`periodoVazio` as *bloc*-level states rather than trying to force them into `ExportJob` is
necessary because both can occur with no `ExportJob` ever existing (a job is never created for an empty
period, and a POST that never got as far as `202 Accepted` never produced a `jobId` to poll).

**Alternatives considered**: reusing one single `erro` state for both FR-006 and FR-007 with a boolean flag —
rejected, directly contradicts the resolved Clarification's explicit "this state MUST be visually and
functionally distinct from FR-006's narrative-only failure" (FR-007); modeling `periodoVazio` as a sentinel
`ExportJob` (e.g. a fake job with no id) — rejected, forces every `ExportJob` consumer to special-case a
value that was never a real job, when the bloc's own sealed `ExportState` already has a natural home for it.

## R5 — Routing every `POST /export/summary` failure other than `EXPORT_EMPTY_PERIOD` to FR-007

**Decision**: if the initial `POST /export/summary` call itself fails with `ExportEmptyPeriodFailure`, the
bloc emits `ExportEmptyPeriod()` (FR-003) and polls nothing. If it fails with `AuthExpiredFailure` after the
repository's one silent-refresh retry already failed, the bloc fires `reauthRequired` (R7) same as every other
failure path in this app, *and* also emits `ExportFailed()` — the session overlay takes over visually (FR-012)
regardless of what state sits underneath it. For every other failure shape (`NetworkTimeoutFailure`,
`NetworkOfflineFailure`, `RateLimitedFailure`, `ValidationFailure`, ...), the bloc emits `ExportFailed()`
(FR-007's generic, job-independent failure state) directly — no job/jobId exists, so "no data was produced" is
true by construction, matching FR-007's own wording precisely.

**Rationale**: spec.md's FRs/Assumptions describe FR-007 only in terms of a job that "fails entirely," which
textually presumes a job exists — but the spec is silent on what happens if the export is never even accepted
in the first place (e.g. the device goes offline the instant the download icon is tapped). Reasonable
technical judgment under Principle I: a request that never produced a job has, definitionally, produced no
data and no narrative — the exact condition FR-007 itself describes — so reusing that same terminal state
(rather than inventing an eighth, undocumented sheet state) is the simplest construction that satisfies FR-010
("Fechar... present... in every one of the five sheet states") without adding a state the prototype's own
five-state catalog, plus the one Clarification-resolved addition, doesn't already cover.

**Alternatives considered**: a distinct "could not even start" state — rejected, no product input describes
one, and FR-007's own generic, errorCode-agnostic copy ("shown the same way regardless of the backend's
specific error code") already reads naturally for this case too; silently retrying the POST — rejected, not
asked for anywhere, and would hide a real failure (e.g. persistent offline) behind an indefinite "Pendente",
directly risking SC-005's "never... indefinitely" guarantee.

## R6 — Why `ExportBloc` is sheet-scoped (one new instance per `showModalBottomSheet` call), not a singleton

**Decision**: `ExportBloc` is `get_it`-registered with `registerFactory` (a fresh instance per
`getIt<ExportBloc>()` call) — the same registration shape `InsertionModalBloc`/`VaultBloc` already use for
their own modal/one-shot screens — and is provided directly above the bottom sheet's content
(`BlocProvider<ExportBloc>(create: (_) => getIt<ExportBloc>()..add(ExportRequested(...)))`, mirroring
`FilterSheet`'s own self-contained-sheet shape). Its polling `Timer` is cancelled in `close()` (same pattern
`RecordsBloc` already uses for its debounce timer); `close()` fires the moment the sheet's `BlocProvider` is
removed from the tree (i.e. the sheet is dismissed), so no poll ever fires for a sheet the user has already
closed — directly satisfying the Edge Case "the app does not keep polling it in background once the sheet is
gone... not treated as the 'current' export if the sheet is reopened." FR-011's "repeated taps... MUST NOT
create multiple concurrent export jobs" is satisfied one layer up, in `_RecordsPageState`: a simple
`bool _isOpeningExportSheet` guard (set before `await showModalBottomSheet(...)`, cleared after) around the
download icon's `onPressed`, identical in spirit to the guard every `IconButton`-triggered async action in
this codebase already needs against a double-tap racing a single `await`.

**Rationale**: the Edge Case's own wording offers two acceptable shapes ("treated as a no-op (or reopens the
same in-flight sheet)"); the no-op-via-guarded-tap shape is simpler and needs no new cross-sheet state
(reusing a leftover job id across sheet instances would directly contradict the Assumptions' own "Reopening the
export sheet afterward is a fresh request; it does not need to return to a leftover job" — the two Edge
Cases/Assumptions together only make sense together if "in flight" here means "the sheet currently on screen,"
not "any job the backend still happens to be processing"). A page-level singleton bloc (reused across sheet
opens, like `EntriesRepositoryImpl`'s `cachedEntries`) was considered and rejected because the ephemeral,
one-shot-per-open shape of the export sheet (Key Entities: "ephemeral... never shown anywhere outside the
export sheet") has no state worth surviving a dismiss — unlike `EntriesRepositoryImpl`'s cache, which exists
specifically to survive across many screen visits.

**Alternatives considered**: a `RecordsBloc`-owned export sub-state (folding export into the existing bloc
entirely) — rejected, conflates two independently-failing, independently-lifetimed concerns into one state
class, the same reasoning RF04's research.md R7 already used to keep `ChatBloc`/`ChatSessionsBloc` apart; a
page-level singleton `ExportBloc` surviving sheet dismissal — rejected per the Assumptions conflict above.

## R7 — Reusing the exact `reauthRequired`/silent-refresh-retry shape, start to finish

**Decision**: `ExportRepositoryImpl` wraps every one of its three calls (`create`/`status`/`download`) in the
identical `_retryAfterSilentRefresh` shape `EntriesRepositoryImpl` already established (exactly one retry via
`SessionRepository.refresh()` on a first-attempt `AuthExpiredFailure`; a second `AuthExpiredFailure` after that
retry is returned as-is, no loop). `ExportBloc` owns its own one-shot `_reauthController`/`reauthRequired`
stream (`StreamController<void>.broadcast()`, closed in `close()`), fired with `if (failure is
AuthExpiredFailure) _reauthController.add(null);` at every call site that can produce one — the exact line
`RecordsBloc` already uses three times over. The sheet widget (`ExportSheet`, a `StatefulWidget`) subscribes
to it in `initState()` exactly as `RecordsPage` already does for `RecordsBloc`, dispatching
`SessionBloc.add(const AuthExpiredDetected())` — `SessionBloc` is provided above `MaterialApp.router` in
`main.dart`, so it is reachable from a bottom sheet's `BuildContext` exactly as it is from any full-screen
route, and the resulting "Sessão expirada" overlay (pushed via the root `NavigatorKey`) renders above the
sheet automatically, needing no export-specific wiring.

**Rationale**: FR-012 asks for exactly this — the existing RF07 mechanism "tak[ing] over exactly as it does
elsewhere on the screen" — so the correct implementation is to reuse the identical mechanism verbatim, not to
build a parallel one. "Resume reflecting the export job's actual status once re-authenticated" falls out of
this construction for free: `ExportRepositoryImpl`'s own retry-after-refresh means a mid-poll `AUTH_EXPIRED`
that the silent refresh *can* recover from is invisible to `ExportBloc` entirely (the very next poll tick
simply succeeds with fresh credentials); only a refresh that itself fails surfaces the overlay, and once the
user re-authenticates through it, the next scheduled poll tick (already armed before the failure, since the
`Timer` from the prior successful tick is independent of this one failing) picks the real status back up with
no bespoke "resume" code needed.

**Alternatives considered**: having `ExportBloc` itself call `SessionRepository.refresh()` — rejected, 
duplicates logic `EntriesRepositoryImpl`/`ChatRepositoryImpl` already centralize at the repository layer,
and would be the first bloc in this codebase to depend on `SessionRepository` directly, contradicting the
established "blocs never touch `SessionRepository`" shape (research.md precedent, `RecordsBloc`'s own
docstring).

## R8 — How the download icon learns the current period, and why no new `go_router` route is added

**Decision**: the export sheet is opened from `RecordsPage`'s existing header `IconButton` (currently an inert
placeholder, `records_page.dart`'s `_Header`), not via a new route. `_RecordsPageState` reads
`context.read<RecordsBloc>().state`'s `dateRange` (a `DateRangeOption`, already RF06's own filter model) at
the moment the icon is tapped, converts it with the already-existing, pure `DateRangeBounds.boundsAt(DateTime.
now())` extension (RF06) into `(from: DateTime?, to: DateTime?)`, and passes those two nullable values straight
through to `ExportSheet(periodStart: ..., periodEnd: ...)` as `showModalBottomSheet`'s builder argument — the
sheet's own `ExportBloc` dispatches `ExportRequested(periodStart, periodEnd)` from its `initState`.

**Rationale**: spec.md's own Assumptions state the export "exports whatever period My Records' own active
date filter currently represents... rather than offering a separate period picker inside the sheet itself" —
`RecordsBloc`'s `dateRange` is already the single source of truth for that filter (FR-002's own wording,
RF06), and `DateRangeBounds` already converts it to concrete bounds for every other consumer that needs them.
Reusing it here needs zero new domain logic. A bottom sheet (not a route) matches both the prototype
("bottom sheet over Tela 4") and this codebase's own precedent for `FilterSheet` — no `go_router` route exists
for RF06's filter sheet either, for the same reason.

**Alternatives considered**: giving `ExportSheet` its own `SessionRepository`-free copy of date-bounds logic
— rejected, duplicates `DateRangeBounds` for no benefit; a new parameterized route (e.g. `/records/export`) —
rejected, same reasoning RF04's research.md R7 already used against a `/home/:sessionId` route: it would force
`go_router` to own state (the active period) a bottom sheet's constructor argument already carries perfectly
well, for a screen that is visually and functionally a modal, not a navigable destination.
