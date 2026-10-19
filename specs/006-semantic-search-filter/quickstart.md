# Quickstart: P-RF06 — Semantic search / filter

How to validate this unit end-to-end once implemented, mapped to spec.md's four user stories. A run guide —
interfaces are in `contracts/`, state/entities in `data-model.md`.

## Prerequisites

- RF07 (`specs/005-multi-source-timeline/`) already implemented and passing — "Meus Registros" already
  renders a timeline with a (previously inert) search bar and funnel button.
- The three fixtures in `docs/input/backend/fixtures/seeded-search-entries.md` seeded on the signed-in test
  account, none containing the literal search terms `ansiedade`/`cansaço`/`gratidão`.
- An account with entries spanning multiple `source` values (`manual`/`audio`/`photo`/`chat`) and multiple
  calendar dates/weeks/months, to exercise the entry-type and date-range filters together.
- A second scenario: an account with entries, where a search/filter combination is known to match zero of
  them (e.g., a date range before any entry's `occurredAt`), to exercise FR-009.

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html    # RNF07 gate — now covering date_range_filter.dart,
                                                         # active_filter_chip.dart, EntryMerger.mergeMany(),
                                                         # plus EntriesRepositoryImpl.search()
dart test/architecture/no_bloc_imports_bloc_test.dart   # RF07's own acceptance criterion — unaffected by this unit
```

`contracts/entries-repository-search-extension.md`, `contracts/records-bloc-extension.md`, and
`contracts/filter-sheet-widget.md` each carry the full scenario table this unit's coverage depends on.

## Manual verification (device/Simulator)

### Story 1 — Finding an entry by what it means, not what it says (P1)

1. Open "Meus Registros", type `ansiedade` into the search bar. **Expect**: exactly one network call fires
   300 ms after the last keystroke (watch the debug `LogInterceptor` output — no request per keystroke), and
   the seeded "racing thoughts before a presentation" entry appears even though it never contains the word
   "ansiedade".
2. Repeat with `cansaço` and `gratidão` against their respective seeded entries (SC-001).
3. Clear the search text completely (backspace to empty). **Expect**: no new search request is sent for the
   empty string; the list immediately returns to showing whatever filters are still active (or the full list,
   if none).
4. Type a few characters, then delete them all again before pausing. **Expect**: no request is ever sent for
   the abandoned partial text (Edge Cases).

### Story 2 — Narrowing the list with filters (P1)

1. Tap the funnel button. **Expect**: the filter sheet opens with "INTERVALO DE DATA"
   (Todo o período/Esta semana/Este mês), "CATEGORIA" (trabalho/rotina/descanso/relações), and
   "TIPO DE ENTRADA" (manual/áudio/foto/chat) groups, matching the prototype.
2. Select "Esta semana" + "áudio" + "foto", tap "Aplicar". **Expect**: the sheet closes; the list narrows to
   entries from the current week that are either audio- or photo-sourced (AND between date range and the
   type set; OR within the type set — SC-003).
3. Re-open the sheet, select a "CATEGORIA" chip (e.g., "trabalho"), tap "Aplicar". **Expect**: the result list
   is completely unaffected by that selection (Acceptance Scenario 2).
4. Re-open the sheet, select several chips, tap "Limpar" (inside the sheet, not "Limpar filtros"). **Expect**:
   every chip inside the sheet visually deselects; the sheet stays open and the screen's actual applied
   filters are unchanged until "Aplicar" is tapped.

### Story 3 — Seeing and clearing what's currently applied (P2)

1. With the Story 2 filters applied, look under the search bar. **Expect**: a removable chip for "Esta
   semana", a removable chip for "áudio", a removable chip for "foto", a "Limpar filtros" link, and the
   funnel button rendered in its filled/active style (SC-004).
2. Tap the "foto" chip's remove control. **Expect**: only that criterion drops — the list now shows audio
   entries from this week only; the screen does not reload or lose scroll position.
3. Tap "Limpar filtros". **Expect**: every chip disappears, the funnel button returns to its neutral style,
   any active search text is also cleared, and the screen shows the same full, unfiltered list RF07 already
   renders — without navigating away (SC-005).
4. With a search term active (no filters), confirm no chip appears for the search term itself — only the
   Filter Set (date range/entry types) gets chips; "Limpar filtros" still clears the search text too.

### Story 4 — Cached results stay trustworthy through a connectivity blip (P3)

1. Apply a search term or filter, confirm results load, then enable airplane mode.
2. Scroll within the already-loaded results. **Expect**: they remain visible and scrollable from memory; no
   blank/error screen appears just from toggling connectivity.
3. Trigger a refetch while offline (e.g., change a filter chip). **Expect**: a clear, retryable inline error
   appears; the previously-shown entries stay on screen (never discarded).
4. Disable airplane mode, tap the retry affordance. **Expect**: the list reconciles with the server's current
   results for the same criteria, with no entry appearing twice (SC-006).

### Edge cases worth exercising manually at least once

- Apply a date range with 2+ entry types selected together, scroll to the bottom of the result list.
  **Expect**: no further fetch is triggered — this was already the complete, bounded merge (research.md R1).
- With a search term active, scroll to the bottom of the results. **Expect**: no further fetch (FR-005b) —
  clearing the search term is what resumes RF07's cursor-based infinite scroll.
- Rapidly change filters twice in a row (e.g., tap "Aplicar" on one combination, then immediately apply a
  different one before the first finishes). **Expect**: only the second combination's results ever render —
  confirm via the debug log that the first request's response, if it arrives later, never changes the screen
  (FR-005a).
- Apply a search/filter combination known to match zero entries on a non-empty account. **Expect**: a
  distinct "no results for this search/filter" message — never RF07's account-wide "Nenhum registro ainda"
  empty state — with a way to adjust/clear the criteria (FR-009).
- Force a `search()`/`list()` call to return `AUTH_EXPIRED` while a search/filter is active. **Expect**: the
  existing "Sessão expirada" overlay (RF07) appears; once resolved, the same search text and filters are still
  applied — they are not silently cleared by the session event (Edge Cases).
