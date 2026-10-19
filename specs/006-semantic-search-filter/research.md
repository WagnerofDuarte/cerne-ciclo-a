# Research: P-RF06 — Semantic search / filter

Phase 0 output. Each item below is a reasonable technical decision made under Constitution Principle I
("where these documents are silent, implementers MUST make a reasonable technical decision rather than block
on clarification") — none reopens a spec.md Clarification; each extends one by filling in a mechanical detail
the Clarification's own wording left open.

## R1 — Does a multi-select entry-type, no-query (filter-only) combination keep RF07's cursor pagination?

**Decision**: No. Whenever more than one entry-type chip is selected, the result set — whether or not a
search term is also active — is a bounded, one-shot merge of one request per selected type (each capped at
`limit: 50`), exactly like FR-005b already mandates for an active search term. `NextPageRequested` becomes a
no-op in this case (`hasReachedEnd` reads `true` because the bloc stores `nextCursor: null` for any bounded
fetch). RF07's real cursor-based infinite scroll (`GET /entries`'s `cursor`/`meta.nextCursor`) continues to
work exactly as before only when **zero or one** entry-type chip is selected and no search term is active.

**Rationale**: spec.md's Clarification 1 resolves *how* multi-type selection is combined ("one request per
selected entry type... merges... de-duplicates... re-sorts... before rendering") but is silent on whether that
merged set itself keeps paginating. Clarification 2 resolves the search-active case explicitly ("no `cursor`
parameter... the single fetch... is the complete result set") and explicitly names `GET /entries`'s *existing*
cursor-based scroll as what resumes for "filter-only or unfiltered browsing" — singular, i.e. the one-call-one-
cursor shape RF07 already built. Reproducing a correct merge-sorted infinite scroll across N independently-
paginated per-type cursor streams (keeping every stream's cursor, re-merging on every page, handling one
stream reaching its end before another) is a materially different and more complex mechanism that neither
the spec nor the prototype describes or tests for. Treating "2+ types selected" as bounded — the same shape
already resolved for search — is the smaller, already-proven extension; a real account is unlikely to need
more than 50 of a given type merged before adjusting filters further.

**Alternatives considered**: (a) maintaining N parallel cursors and merge-sorting every further page — rejected
as unspecified complexity with no test material backing it; (b) silently capping multi-type selection to the
first type only — rejected as a visible product regression from the prototype's own multi-select affordance,
which Clarification 1 explicitly preserves.

## R2 — How are `DateRangeOption`'s `dateFrom`/`dateTo` bounds computed?

**Decision**:
```dart
enum DateRangeOption { allTime, thisWeek, thisMonth }
```
- `allTime` → `(from: null, to: null)` — no parameter sent.
- `thisWeek` → `from` = the most recent Monday at local 00:00:00, `to` = `null`.
- `thisMonth` → `from` = the 1st of the current local calendar month at local 00:00:00, `to` = `null`.

Both non-`null` bounds are converted with `.toUtc().toIso8601String()` before being sent as `dateFrom`
(matching the `date-time` format every other date field in `docs/input/backend/api/openapi.yaml` already
uses, and the same `DateTime.parse`/`.toLocal()` round-trip `entries_remote_data_source.dart`/`record_card.dart`
already establish for `occurredAt`).

**Rationale**: the prototype only names the three options ("Todo o período / Esta semana / Este mês") without
defining their exact boundaries — this is squarely "where these documents are silent." Leaving `dateTo` open
(`null`, meaning "through now") is simpler and avoids an off-by-one risk at the exact current instant; nothing
created in the future exists to accidentally include. The function takes `now` as a parameter
(`boundsAt(DateTime now)`), mirroring RF07's `DateGrouper.group(..., {DateTime? now})` precedent, purely so
tests can fix "today" deterministically.

**Alternatives considered**: `thisWeek` as "the last rolling 7 days" instead of "since Monday" — rejected
because a calendar-week boundary reads more naturally against the prototype's Portuguese label ("Esta semana")
and matches how `DateGrouper` already buckets by calendar day, not by a rolling window.

## R3 — Why does `Entry` gain a nullable `similarity` field instead of a parallel "search result" entity?

**Decision**: add one nullable field, `final double? similarity`, to the existing `Entry` entity (defaults to
`null`; only `entries_remote_data_source.dart`'s parsing for the `entries-search` response ever sets it to a
non-null value). `EntriesRepository.search()` returns `List<Entry>`, the same type `list()`'s page already
carries — not a new `SearchResultEntry` wrapper type.

**Rationale**: spec.md's own Key Entities section defines "Search Result Entry" as "**a Journal Entry (as
already defined by RF07)**... ordered by relevance" — explicitly the same entity, not a new one. The only
thing `GET /entries/search`'s response adds over `GET /entries`'s is one extra, optional field
(`similarity`, 0–1), needed solely to re-sort a multi-type merge by relevance (R1). Every other field in the
`entries-search` response schema is identical to `entries-list`/`entries-create`'s. Modeling it as a sibling
optional field keeps `record_card.dart` and every other `Entry` consumer unchanged (nothing reads
`similarity` outside `EntryMerger.mergeMany()`'s relevance-sort branch) and keeps `EntryMerger.mergeMany()`
able to merge `list()`'s and `search()`'s results through one shared type, which per-type fan-out (R1) needs
when some types are fetched via `list()` and others — never, actually, since a given fetch round is either
all-`list()` or all-`search()` depending on whether a query is active, but a single shared return type still
avoids two near-identical merge functions.

**Alternatives considered**: a parallel `SearchResultEntry extends Entry { final double similarity; }` —
rejected: it would need its own `mergeMany` overload (or a cast back to `Entry` anyway to interoperate with
`DateGrouper`/`RecordCard`, which expect `List<Entry>`), without buying any type safety spec.md's own wording
asks for.

## R4 — Why no new dependency for the 300 ms debounce?

**Decision**: a single `dart:async` `Timer`, owned by `RecordsBloc`, reset on every `SearchTextChanged` event;
when it fires, it calls `add(const SearchDebounceElapsed(text))` to re-enter the bloc's own event loop. The
`Timer`'s `Duration` is an injectable constructor parameter (default `Duration(milliseconds: 300)`) so tests
can pass `Duration.zero`.

**Rationale**: this is the exact mechanism `login_signup_page.dart` already uses for its own 300 ms RNF01
delay (`_loadingIndicatorTimer = Timer(const Duration(milliseconds: 300), ...)`) — an established,
zero-dependency pattern in this codebase. `flutter_bloc`'s built-in `EventTransformer` mechanism (e.g. a
`debounce()` transformer from `bloc_concurrency`/`stream_transform`) would do the same job but requires adding
a package neither RF07 nor any earlier unit needed (Principle II favors the fixed, already-adopted stack; a
one-field `Timer` is simpler than a new transitive dependency for one call site).

**Alternatives considered**: `bloc_concurrency`'s `restartable()`/`debounceTime` combinator — rejected, new
dependency for no behavioral gain over a `Timer`; a widget-level `Timer` inside `RecordsPage` instead of inside
`RecordsBloc` — rejected because the bloc, not the widget, is what also owns the generation counter (R6) and
the currently-applied criteria fields; splitting debounce-timing into the widget and supersession-tracking
into the bloc would spread one cohesive concern across two files for no benefit.

## R5 — What happens to `RecordsLocalCacheRefreshed` once search/filter criteria exist?

**Decision**: `RecordsLocalCacheRefreshed` (fired by `RecordsPage` once the insertion-modal's
`showModalBottomSheet` future resolves, re-merging `EntriesRepository.cachedEntries` — RF07's own mechanism)
becomes a no-op whenever any search/filter criteria is currently active (`isSearchActive ||
hasActiveFilters`). When no criteria is active, it behaves exactly as RF07 built it.

**Rationale**: `cachedEntries` holds every locally-created entry regardless of its `source`/`occurredAt` —
RF07 could merge it in unconditionally because nothing on that screen ever filtered. Under an active search
term or filter, a just-created entry might not satisfy the current criteria (wrong `source`, outside the
chosen date range, or — for an active search term — a semantic match nothing on-device can evaluate), so
merging it in unconditionally would violate FR-005's AND-across-axes guarantee by showing an entry that
doesn't actually match. Skipping the merge while criteria are active is the smaller, correctness-preserving
choice; the next explicit criteria change (or clearing filters) naturally re-fetches and would include it if
it matches.

**Alternatives considered**: re-running the full criteria fetch instead of a local-only merge whenever the
modal closes with an active criteria — rejected as an extra network call for an edge case (creating an entry
from "Meus Registros" while already mid-search) spec.md's own User Stories never describe as a flow to
support; the no-op keeps behavior correct without inventing new traffic.

## R6 — Request-supersession mechanics for FR-005a

**Decision**: a single private `int _fetchGeneration = 0` field on `RecordsBloc`. Every fetch-initiating
method (`_loadFirstPage`, `_fetchNextPage`, the new `_fetchForCriteria`) does
`final generation = ++_fetchGeneration;` *before* its `await`, and checks `if (generation !=
_fetchGeneration) return;` immediately *after* the `await`, before calling `emit(...)`. Any event that starts
a new fetch (a debounce firing, a filter applied, a chip removed, "Limpar filtros", a next-page request, a
retry) bumps the counter, so a slower, now-superseded earlier call's result is silently discarded exactly
once it resolves.

**Rationale**: spec.md's Clarification 3 states this requirement in exactly these terms ("only the most
recently fired request... is ever authoritative... discarding the response of any earlier, now-superseded
request"). A monotonic counter checked before every `emit` is the simplest mechanism that satisfies this for
every trigger listed (debounce fire, filter change, chip removal, clear) without needing per-request
cancellation tokens or a `CancelableOperation` wrapper — `Either<Failure, T>`-returning repository calls
can't be cancelled mid-flight anyway (no abort signal in `ApiClient`), so discarding the *result* is the only
lever available, and it is sufficient: a discarded response simply never reaches `emit`.

**Alternatives considered**: `dio`'s `CancelToken` to actually abort the superseded HTTP request — rejected
as unnecessary for correctness (the response is discarded either way) and as a change to `ApiClient`'s shared
contract that every other feature's call sites would need to opt into or ignore, for a benefit (saving one
in-flight request) the spec never asks for.

## R7 — Why "offline shows cached results" needs no new code

**Decision**: no `ConnectivityChecker` pre-check is added before `search()`/`list()` calls, and no new "is
this fetch's failure due to being offline" branch is added beyond the generic failure-preserving pattern
`_fetchNextPage` already established (keep `entries` as they were, surface the failure in a retryable, inline
banner — here, `criteriaLoadFailure` for a criteria-change fetch, mirroring `pageLoadFailure` for a next-page
fetch).

**Rationale**: FR-010 ("while offline, continue showing results already present in the local cache") is
satisfied by construction the same way RF07 already satisfies its own equivalent Edge Case — `RecordsLoaded`
is simply never replaced by a blank/loading state on a failed fetch; whatever was last successfully rendered
stays on screen. `ApiClient` already synthesizes `NetworkOfflineFailure` for a `DioException` with no response
(a real offline device), so the offline case reaches the exact same failure-preserving branch every other
network failure does — no special-casing needed. "Reconciles without duplicating any entry" (FR-010's second
half) is `EntryMerger`'s existing dedupe-by-ID behavior (`merge`/`mergeMany`), already guaranteed for any
successful refetch regardless of what triggered it.

**Alternatives considered**: proactively checking `ConnectivityChecker.hasConnection()` before firing a
search/filter request (as `capture/`'s write-path use cases do) — rejected: those checks exist because a
*write* must never be attempted offline (RNF03/capture's own FR); a *read* has no such constraint, and RF07's
own `list()`/`getById()` never pre-check connectivity either — they let the HTTP client fail naturally and
handle the resulting `Either`. Introducing the check only for RF06's reads would be an inconsistency with
RF07's already-shipped, unmodified pattern for no stated benefit.
