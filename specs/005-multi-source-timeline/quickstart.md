# Quickstart: P-RF07 — Multi-source history (timeline)

How to validate this unit end-to-end once implemented, mapped to spec.md's four user stories. A run guide —
interfaces are in `contracts/`, state/entities in `data-model.md`.

## Prerequisites

- F000, RF01, RF03 already implemented and passing (this unit depends on all three per spec.md's header).
  `EntriesRepository`/`Entry`/`CreateEntryUseCase` (RF01) and `SessionRepository`/`SessionBloc`/the "Sessão
  expirada" overlay (F000) are extended, not replaced.
- A signed-in test account with entries spanning at least 3 different calendar days, created across at least
  `manual`, `audio`, and `photo` origins (reuse RF01/RF02's own fixtures to create them), and — since no
  capture flow can produce one — a `chat`-sourced entry seeded directly in the backend/fixtures to exercise
  Edge Cases' "renders a `chat` entry without erroring" scenario.
- A second, brand-new test account with zero entries, for Story 2.
- Enough entries (more than one backend page — the default page size is 20) to exercise pagination for
  Story 1's Acceptance Scenario 3.

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html    # RNF07 gate — now covering entry_merger.dart,
                                                         # date_group.dart, sync_badge_state.dart, plus
                                                         # EntriesRepositoryImpl.list()/getById()
dart test/architecture/no_bloc_imports_bloc_test.dart   # requirements.md RF07's own acceptance criterion
```

`contracts/entries-repository-extension.md` and `contracts/records-bloc.md` each carry the full scenario
table this unit's coverage depends on.

## Manual verification (device/Simulator)

### Story 1 — Seeing every entry in one place, regardless of origin (P1)

1. Open the side menu (☰) → "Meus Registros" from Home/Chat. **Expect**: records grouped under "Hoje" /
   "Ontem" / explicit older dates (newest group first), each card showing the right spine color + icon for
   its origin (manual = dark green/pencil, audio = olive green/mic, photo = gray/image, chat =
   ochre/chat-bubble), a time, a sync badge, a text excerpt, and tag chips only on entries that actually have
   tags.
2. Confirm the seeded `chat`-origin entry renders like any other card (ochre spine, chat-bubble icon) — no
   crash, no "unrecognized" placeholder.
3. Scroll to the bottom. **Expect**: further entries load and append automatically, with no "load more"
   button, no disturbance to the cards already on screen, and no visible scroll jump.
4. Scroll to the true end of history. **Expect**: loading simply stops — no error banner, no "end of list"
   message.

### Story 2 — Starting from nothing (P1)

1. Sign in on the zero-entries account, open "Meus Registros". **Expect**: the notebook icon, "Nenhum
   registro ainda", and the "Criar primeiro registro" button — never a blank or perpetually-loading screen.
2. Tap "Criar primeiro registro". **Expect**: the same Insertion Modal RF01/RF02 already built opens over
   this screen.
3. Save a text entry. **Expect**: the modal closes back onto "Meus Registros" (not Home/Chat), and the new
   entry now appears in its correct date group ("Hoje"), replacing the empty state.

### Story 3 — The session expires while browsing (P2)

1. Load "Meus Registros" with several entries visible, scroll to a specific, identifiable position.
2. Force the next `GET /entries` call to return `AUTH_EXPIRED` (e.g., via a debug toggle/expired test token)
   and either scroll further or wait for a background refresh attempt to trigger it. **Expect**: the "Sessão
   expirada" overlay appears over the screen; the entries and scroll position underneath are completely
   unchanged (confirm by dismissing-and-checking before re-authenticating, if your test harness allows it).
3. Tap "Entrar novamente" and re-authenticate successfully. **Expect**: the overlay dismisses; the screen is
   exactly as it was (same entries, same scroll position) — no reload, no reordering.
4. Scroll further again. **Expect**: pagination now resumes normally (the next page is fetched successfully
   with the fresh session).

### Story 4 — The sync badge tells the truth, even during session trouble (P3)

1. With entries visible, force a silent session renewal in the background (a renewable `AUTH_EXPIRED` the
   refresh call recovers from transparently). **Expect**: no visible change to any card — no badge flicker,
   no overlay, no reload (silent renewal never surfaces to the UI).
2. Repeat Story 3's forced-expiry-and-overlay flow. **Expect**: once the overlay is dismissed, every badge on
   every card underneath shows exactly the same state (color + label) it showed before the overlay appeared.
3. Since every entry this unit can display is already server-confirmed by construction (research.md R6),
   every badge observed in steps 1–2 should read "sincronizado" (green) — this is expected, not a bug; it is
   not possible to observe "sincronizando"/"erro de sync" through this unit's own flows alone (spec.md
   Assumptions).

### Edge cases worth exercising manually at least once

- Turn on airplane mode after the first page has loaded, then scroll to trigger another page. **Expect**: a
  clear, retryable inline error at the bottom of the list; the entries already shown stay visible and
  scrollable; no write of any kind is attempted.
- Turn airplane mode back on, tap the retry affordance from that error. **Expect**: it fails again cleanly
  (no crash); turn airplane mode off and retry again. **Expect**: pagination resumes normally.
- Force the very first `GET /entries` call (on screen open) to fail outright (not just offline). **Expect**:
  a full-screen retryable error — never the "Nenhum registro ainda" empty state.
- Tap the header's download icon and the search bar/funnel button. **Expect**: both render exactly per the
  prototype but do nothing (FR-008 — inert placeholders; no export, no filter sheet, no search).
- With a known seeded account (more than one page of entries where the newest page happens to be empty, e.g.
  nothing created "today" or "yesterday" but older entries exist), open "Meus Registros". **Expect**: paging
  continues directly to the older groups — the empty state must **not** appear.
