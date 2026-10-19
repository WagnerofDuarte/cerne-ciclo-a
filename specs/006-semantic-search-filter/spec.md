# Feature Specification: P-RF06 — Semantic search / filter

**Feature Branch**: `006-semantic-search-filter` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "P-RF06 — Semantic search / filter over journal entries: Let the user find entries by meaning and narrow them with filters, on the My Records screen, per docs/input/requirements.md section 1 (RF06) and its acceptance criteria; parameter in section 10. Prototype states: the search bar of 'Tela 4 — Meus Registros', 'Tela 4 — Sheet de filtro', and 'Tela 4 — Filtros ativos' (prototype extract, section 2.4, including the note that the backend has no category filter). Backend: GET /entries/search, GET /entries. Test material: docs/input/backend/fixtures/seeded-search-entries.md. Depends on RF07. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## Clarifications

### Session 2026-10-17

- Q: The filter sheet's "TIPO DE ENTRADA" chips allow selecting more than one entry type at once, but both `GET /entries` and `GET /entries/search` accept only a single `source` value per request, and every entry has exactly one `source` — so an entry can never match "every" selected type simultaneously. How should multiple selected entry-type chips be combined, and how should the request(s) be built? → A: Entries having ANY of the selected types are included (OR among the entry-type chips themselves), while that combined set is still ANDed with the active date range and search term. To build it, the app fires one request per selected entry type (each carrying the same `q`/`dateFrom`/`dateTo`), merges the responses, de-duplicates by entry ID, and re-sorts the combined set (by relevance when a search term is active, otherwise reverse-chronological, matching RF07) before rendering — preserving the prototype's multi-select affordance without requiring a backend change. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: When the user is scrolled through a search result list (an active `q`) and nears the bottom, should the app try to load a further page, given `GET /entries/search` has no `cursor` parameter and caps results at `limit` (max 50)? → A: No — while a search term is active, the single fetch (up to `limit`) is the complete result set for that query; "scrollable" means scrolling within what is already loaded, not triggering a further fetch. Clearing the search text returns to `GET /entries`'s existing cursor-based infinite scroll (RF07) for filter-only or unfiltered browsing. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: With a 300 ms debounce and no server-side throttle on `GET /entries/search` (per its own API summary), could a slow, older response arrive after a newer request's response and overwrite it with stale results? → A: Yes, so the app MUST treat only the most recently fired request (per debounce fire, filter change, chip removal, or "Limpar filtros") as authoritative — discarding the response of any earlier, now-superseded request for the same screen state, never applying a late-arriving stale response over a newer one. (Resolved by technical judgment per user direction, applying Constitution Principle I.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Finding an entry by what it means, not what it says (Priority: P1)

A user wants to find something they wrote about even though they can't remember the exact words they used. They type a term into the search bar on "Meus Registros" and get back entries that are about that topic, including ones that never use the literal word they typed.

**Why this priority**: This is the entire premise of RF06 and the capability that sets this screen apart from a plain keyword filter — without it, the feature delivers no value beyond what RF07's list already provides.

**Independent Test**: Can be fully tested by seeding the three entries from `docs/input/backend/fixtures/seeded-search-entries.md` (none of which contains the literal search term) and confirming each documented search term (`ansiedade`, `cansaço`, `gratidão`) returns its matching entry.

**Acceptance Scenarios**:

1. **Given** the seeded entry that describes racing thoughts and a tight chest the night before a presentation (no occurrence of the word "ansiedade"), **When** the user searches "ansiedade", **Then** that entry appears in the results.
2. **Given** the user is typing a search term, **When** they type several characters in quick succession, **Then** exactly one search request is sent, 300 ms after they stop typing — not one request per keystroke.
3. **Given** the user clears the search text completely, **When** the field becomes empty, **Then** the screen returns to showing results based only on whatever filters are still active (or the full list, if none are active), without sending a search for an empty term.

---

### User Story 2 - Narrowing the list with filters (Priority: P1)

A user wants to see only entries from a particular date range and/or a particular capture method (text, audio, photo, chat), without necessarily typing any search term. They open the filter sheet, choose criteria, apply them, and see a narrowed list.

**Why this priority**: Equally core to RF06 as semantic search — the requirement explicitly treats "semantic similarity combined with metadata filters" as a single capability, and filtering alone (with no search text) must work correctly on its own.

**Independent Test**: Can be fully tested by opening the filter sheet on an account with entries of mixed dates and sources, applying a date range and an entry-type selection together, and confirming the result list contains only entries that satisfy both.

**Acceptance Scenarios**:

1. **Given** the filter sheet is open, **When** the user picks a date-range option (Todo o período / Esta semana / Este mês) and one or more entry-type chips (manual, áudio, foto, chat) and taps "Aplicar", **Then** the list narrows to entries that fall within the chosen date range AND have one of the chosen entry types — the date range and the entry-type selection are ANDed with each other, while multiple selected entry types are ORed among themselves (an entry has exactly one type, so it can never match more than one at a time).
2. **Given** the filter sheet's "CATEGORIA" chip group (trabalho, rotina, descanso, relações), **When** the user taps one of those chips and applies the sheet, **Then** the result list is unaffected by that selection, because the backend has no category filter — the chips exist for visual fidelity to the prototype only.
3. **Given** the filter sheet is open, **When** the user taps "Limpar" inside the sheet, **Then** every selection in the sheet resets before it is applied.

---

### User Story 3 - Seeing and clearing what's currently applied (Priority: P2)

A user who has applied one or more filters, with or without a search term, wants to glance at the screen and immediately understand what is currently narrowing their results, and be able to remove any single criterion or all of them at once.

**Why this priority**: A usability layer on top of Stories 1 and 2 — the underlying narrowing already works without it, but the requirement's own acceptance criteria call out that filters must be clearable without restarting the screen, and the prototype dedicates a distinct state to this.

**Independent Test**: Can be fully tested by applying two filters, confirming a chip appears for each with the funnel button shown filled, removing one chip and confirming only that criterion drops out, then using "Limpar filtros" and confirming the screen returns to its unfiltered list without reloading.

**Acceptance Scenarios**:

1. **Given** one or more filters are applied, **When** the screen re-renders, **Then** a removable chip appears under the search bar for each active filter, a "Limpar filtros" link is shown, and the funnel button displays its filled/active state.
2. **Given** active-filter chips are showing, **When** the user taps the removable control on a single chip, **Then** only that criterion is removed and the result list updates to reflect the remaining active criteria (or the full list, if none remain) — the screen is not reloaded or reset.
3. **Given** active-filter chips are showing, **When** the user taps "Limpar filtros", **Then** every applied filter and any active search text is cleared and the screen returns to the same full, unfiltered list RF07 already shows, without navigating away from or restarting the screen.

---

### User Story 4 - Cached results stay trustworthy through a connectivity blip (Priority: P3)

A user is viewing search or filter results when the connection drops and later comes back. What they see while offline comes from the local cache, and once reconnected, the list reconciles with the server without showing the same entry twice or leaving stale results behind unnoticed.

**Why this priority**: A correctness property layered on top of Stories 1–3 rather than a feature of its own; it depends on search and filtering already producing a result list to keep consistent, and it protects against a subtle trust-eroding bug rather than blocking the core flow.

**Independent Test**: Can be fully tested by loading a search/filter result list, simulating a loss and restoration of connectivity, and confirming the list shown offline matches the cache, with no duplicated entries once the server is reachable again.

**Acceptance Scenarios**:

1. **Given** a search or filter result list is already loaded, **When** the device goes offline, **Then** the previously loaded results remain visible and scrollable from the local cache.
2. **Given** results were shown from cache while offline, **When** the connection is restored, **Then** the list reconciles with what the server currently returns for the same search/filter criteria, with every entry appearing exactly once (no duplicates).

---

### Edge Cases

- A search and/or filter combination matches zero entries on an account that does have entries: the screen shows a distinct "no results for this search/filter" message, not RF07's account-wide "Nenhum registro ainda" empty state, and offers a way to adjust or clear the applied criteria from there.
- The user types a term, then deletes it entirely before the 300 ms debounce fires: no request is ever sent for the abandoned partial text.
- A search request or a filtered fetch fails outright (timeout, malformed response, or the device is offline when the request would be sent): the screen shows a clear, retryable error without discarding whatever cached results are already displayed, and without attempting any write.
- The session expires while a search or a filtered view is active: the existing "Sessão expirada" overlay (RF07) handles it, and once resolved, the active search text and filters are still applied — they are not silently cleared by the session event.
- A filter is applied together with an active search term at the same time (not shown explicitly acting together anywhere in the prototype): both narrow the same result set together under AND logic, consistent with the requirement's general rule that "two or more filters applied at the same time narrow results with AND logic."
- A new search, filter change, or clear action fires while an earlier request for the same screen is still in flight: only the most recently fired request's response is ever applied to the screen; any earlier, now-superseded response is discarded so a slow stale response can never overwrite newer results.
- An active search term's result list already shows every entry the backend returned for that query (up to its `limit`): scrolling to the bottom of that list does not trigger a further fetch, since `GET /entries/search` has no pagination cursor; only clearing the search term resumes RF07's existing cursor-based infinite scroll for filter-only or unfiltered browsing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST wire the search bar already present on "Meus Registros" to `GET /entries/search`'s `q` parameter, returning entries ranked by semantic similarity to the typed term rather than by exact keyword matching.
- **FR-002**: Text entered in the search bar MUST be debounced at the fixed 300 ms parameter (requirements section 10), so that a burst of fast typing results in exactly one search request fired after the user pauses, never one request per keystroke; clearing the search text to empty MUST NOT itself trigger a search-for-nothing request.
- **FR-003**: The system MUST provide a filter sheet, reachable via the existing funnel button, offering a single-choice date-range selector (Todo o período / Esta semana / Este mês, mapped to `dateFrom`/`dateTo`) and a multi-select entry-type selector (manual, áudio, foto, chat, mapped to `source`), with "Aplicar" committing the current selections and "Limpar" resetting the sheet's own selections before they are applied. Because `source` accepts only a single value per request, selecting more than one entry-type chip MUST be implemented as one request per selected type, with the responses merged, de-duplicated by entry ID, and re-sorted before being rendered (see Clarifications).
- **FR-004**: The filter sheet's "CATEGORIA" chip group (trabalho, rotina, descanso, relações) MUST be rendered for visual fidelity to the prototype but MUST NOT filter the result list or send any category-related parameter to the backend, since neither `GET /entries` nor `GET /entries/search` implements a category or tag filter.
- **FR-005**: Any combination of currently active criteria — date range, the set of selected entry types, and an active search term — MUST narrow the result list using AND logic across those three axes at once, never OR logic between them. Within the entry-type axis itself, selecting more than one type MUST include an entry if it matches ANY of the selected types (OR among types), since each entry has exactly one `source` value and could otherwise never satisfy more than one type at a time.
- **FR-005a**: A new search, filter change, or clear action MUST be treated as superseding any still-in-flight earlier request for the same screen: the response of an earlier, now-superseded request MUST be discarded rather than applied, so a slower stale response can never overwrite the results of a more recent request.
- **FR-005b**: While an active search term (`q`) is in effect, the result list MUST consist of the single bounded response already returned by `GET /entries/search` (up to its `limit`); scrolling within that list MUST NOT trigger a further fetch. Clearing the search term MUST resume `GET /entries`'s existing cursor-based infinite scroll (RF07) for filter-only or unfiltered browsing.
- **FR-006**: Whenever one or more filters are applied, the screen MUST show a removable chip for each active filter under the search bar, a "Limpar filtros" link, and the funnel button in its filled/active visual state.
- **FR-007**: Removing a single active-filter chip MUST drop only that criterion and refresh the result list accordingly; activating "Limpar filtros" MUST drop every active filter and any active search text at once; neither action MUST reload or restart the screen.
- **FR-008**: Clearing every active filter and search term MUST return the screen to the same full, unfiltered entry list RF07 already renders, without navigating away from or restarting "Meus Registros".
- **FR-009**: When an active search and/or filter combination matches zero entries on an account that has entries, the screen MUST show a distinct "no results" state separate from RF07's account-wide zero-entries empty state, with a way to adjust or clear the applied criteria.
- **FR-010**: Whenever a search or filtered fetch fails outright — whether because the device is offline, the request times out, or the response is malformed — the screen MUST continue showing whatever search/filter results are already present in the local cache rather than discarding them, and MUST present a clear, retryable error. Specifically for the offline case, upon reconnection the system MUST reconcile the displayed results with what the server currently returns for the same criteria without duplicating any entry.
- **FR-011**: This unit MUST NOT implement entry tag or category creation, editing, or filtering (extension feature, requirements section 2), export (RF05), chat (RF04), or any other later-unit behavior; and MUST NOT modify the backend, its API contract, or its configuration in any way.

### Key Entities

- **Search Query**: The free-text term the user has typed into the search bar, debounced before being sent as the `q` parameter to `GET /entries/search`; empty when the user has typed nothing or has cleared it.
- **Filter Set**: The combination of date-range choice and selected entry types the user has applied via the filter sheet, sent as `dateFrom`/`dateTo`/`source` parameters. The date range and the entry-type selection are combined with AND logic with each other and with any active Search Query; when more than one entry type is selected, the resulting requests (one per type) are combined with OR logic among themselves, since `source` is single-valued and each entry has exactly one type.
- **Active Filter Chip**: A removable, on-screen representation of one currently applied Filter Set criterion, shown under the search bar whenever that criterion is active.
- **Search Result Entry**: A Journal Entry (as already defined by RF07) as returned by `GET /entries/search` or `GET /entries` under the current Search Query and Filter Set, ordered by relevance to an active query rather than strictly by recency when a query is present. When more than one entry type is selected, this is the merged, de-duplicated (by entry ID) combination of each per-type request's results, re-sorted into that same ordering.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For each of the three documented seed-data search terms, searching finds its matching entry even though the entry's text never contains that literal word, 100% of the time.
- **SC-002**: A burst of fast typing produces exactly one search request per pause in typing, never one request per keystroke, across all tested typing sequences.
- **SC-003**: Applying filter criteria across different axes (date range, entry type, search term) together always narrows results to entries matching every active axis at once (AND), with zero observed cases of an axis being ignored; applying two or more entry-type chips together always returns the union of entries matching any of them (OR within that one axis), with zero observed cases of an entry type's matches being excluded because another type was also selected.
- **SC-004**: 100% of currently applied filters are visible on screen as a chip, with the funnel button shown in its active state whenever at least one filter is applied.
- **SC-005**: Clearing filters, whether by removing every chip individually or by using "Limpar filtros", always restores the full, unfiltered list without the user leaving or reloading the screen.
- **SC-006**: After a period offline followed by reconnection, a search/filter result list never shows a duplicated entry and matches what the server currently returns for the same criteria.

## Assumptions

- This unit makes live the search bar and funnel button that RF07 already renders as visual-fidelity placeholders on "Meus Registros" (per RF07's own FR-008 and its Assumptions), rather than building new UI chrome for them.
- Combining an active search term with the filter sheet at the same time is governed by the same AND-logic rule the requirement states for multiple filters, even though the prototype does not show the two interacting explicitly (prototype extract, implementation note 7) — a reasonable extension of an explicitly stated rule, not an invented behavior.
- A distinct "no results for this search/filter" message is shown when an active search/filter combination narrows an otherwise non-empty account down to zero entries, kept separate from RF07's account-wide "Nenhum registro ainda" empty state, since the two represent different situations (a true empty account vs. an empty result of the user's own narrowing).
- Search and filter errors (timeout, malformed response, offline) are surfaced using the same retryable error-handling pattern already established for this screen's other network calls (RNF09), without inventing a new error presentation specific to search.
- Active search text and filters are not persisted beyond the current viewing of "Meus Registros" — leaving and later returning to the screen starts from its default, unfiltered state — since neither the requirements nor the prototype describe any persistence for them.
- The "sincronizado / sincronizando / erro de sync" per-entry badge, tag chips, and date-group headings on each result card behave exactly as RF07 already defined; this unit changes which entries are shown and in what order, not how an individual result card renders.
