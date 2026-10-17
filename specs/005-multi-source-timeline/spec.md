# Feature Specification: P-RF07 — Multi-source history (timeline)

**Feature Branch**: `005-multi-source-timeline` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "P-RF07 — Multi-source history (timeline): Show all of the user's entries in a timeline, whatever their origin, with a per-entry synchronization badge, per docs/input/requirements.md section 1 (RF07) and its acceptance criteria. Prototype states: 'Tela 4 — Meus Registros' (default) and 'Tela 4 — Vazio' (prototype extract, section 2.4); the 'Sessão expirada' overlay (section 4). Badge semantics: docs/input/backend/sync-badge.md. Backend: GET /entries, GET /entries/:id, GET /auth/session, POST /auth/refresh. Depends on F000, RF01. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## Clarifications

### Session 2026-10-17

- Q: RF01 (already delivered) opens the Insertion Modal only from Home/Chat's "+" button and, on a successful save, always returns the user to Home/Chat. This unit adds a second entry point — the "Criar primeiro registro" action on this screen's empty state — so where should a save started from there return the user to, and must the newly created entry appear here immediately? → A: It returns to this screen (Meus Registros), not to Home/Chat, and the newly created entry appears immediately in its correct date group. The entire purpose of the empty-state action is to take the user from zero entries to seeing their first one; returning them to Home/Chat instead would leave the empty state looking unresolved even though the entry was created. This reuses the same in-memory entries store RF01 already appends to on a successful save (and that it documented as existing "for later units ... to read"), merged with whatever this screen has already loaded from the backend. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: `GET /entries/:id` is listed under this requirement, but no entry-detail or full-text screen appears anywhere in the prototype's navigation map or navigable-state catalog for "Meus Registros" — only a card with a truncated text excerpt. What is this endpoint actually for in this unit? → A: It is not used to open a detail view (none is drawn anywhere, and inventing one would conflict with this unit's visual-fidelity obligation to the frozen prototype). Instead, this unit uses it to re-confirm the state of one specific, already-loaded entry during reconciliation — for example, after the "Sessão expirada" overlay is dismissed and the session is renewed — rather than re-fetching the entire paginated list, which is what keeps already-rendered cards and the scroll position from being disturbed, in line with this requirement's own acceptance criterion about not losing scroll position. This unit's own scope never actually produces a locally-pending or unreconciled entry (every entry rendered here is already server-confirmed, per the Assumption on badge states below), so no reconciliation trigger exists to wire `GET /entries/:id` into — it is implemented and tested as a documented repository capability for a future unit's use, not called from anywhere in this unit's own code. See plan.md's Post-Design Constitution Check (research.md R7) for the design-time confirmation of this. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: When this screen merges the entry RF01's save flow already placed in the app's local in-memory entries store with the entries this screen fetches from the backend, how should it avoid showing that same entry twice? → A: Dedupe by entry ID. RF01's save flow only adds an entry to the local store after the backend has confirmed the write, so every locally-held entry already carries a real, server-issued ID; when a fetched backend page returns an entry whose ID already exists in the local store, the two are recognized as the same entry and shown once (preferring the freshly-fetched copy's confirmation data — `updatedAt`/`serverRevision` — since it is at least as current as the local one). This is the simplest reliable key available and is what keeps SC-001's "100% of entries appear exactly once" true once a locally-created entry's page is later re-fetched from the backend. (Resolved by technical judgment per user direction, applying Constitution Principle I.)
- Q: Within each date group (and across date groups), in what order are entries displayed — and does that order match the order newer pages get appended to older ones while scrolling? → A: Reverse-chronological throughout: date groups run newest-to-oldest ("Hoje" at the very top), and within each group entries run newest-to-oldest by their occurrence time. This matches the backend's cursor-based pagination (each further page is strictly older than what's already loaded) and the prototype's own "Hoje"/"Ontem"/older-dates ordering, and it is the only ordering under which "scrolling down loads older entries, appended at the bottom" (FR-003, Edge Cases) is coherent without resorting already-rendered cards. Neither the prototype extract nor `requirements.md` states this explicitly, so this is a reasonable technical decision per Constitution Principle I rather than an invented behavior with no basis in the frozen inputs. (Resolved by technical judgment per user direction, applying Constitution Principle I.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Seeing every entry in one place, regardless of how it was created (Priority: P1)

A user who has written notes, recorded audio, and captured photos over several days opens "Meus Registros" from the side menu and sees all of those entries together, in a single timeline, grouped by the day they happened ("Hoje", "Ontem", then calendar dates), each one visually marked with where it came from.

**Why this priority**: This is the entire reason the screen exists — a user's journal is split across capture methods, and without this unified view there is no way to look back at everything they've recorded.

**Independent Test**: Can be fully tested by seeding a user with entries of different origins across different days, opening "Meus Registros", and confirming every entry appears exactly once, grouped under the correct date heading, with an origin-appropriate visual marker on each.

**Acceptance Scenarios**:

1. **Given** a user with entries created as text, audio, and photo on different days, **When** they open "Meus Registros", **Then** every one of those entries appears in the list, grouped under date headings ("Hoje" for today's entries, "Ontem" for yesterday's, an explicit date for anything older), each showing a time, an origin-colored marker and icon, a text excerpt, and a synchronization badge.
2. **Given** an entry that has tags attached (from existing account data), **When** its card is rendered, **Then** those tags appear as read-only chips on the card; **given** an entry with no tags, **When** its card is rendered, **Then** no tag chips appear for it.
3. **Given** the list of entries is longer than fits on screen, **When** the user scrolls down, **Then** older entries load automatically and are appended to the list without disturbing the entries already shown or losing the user's scroll position.

---

### User Story 2 - Starting from nothing (Priority: P1)

A brand-new user, or one who has not yet created any entry, opens "Meus Registros" and sees a clear empty state instead of a blank or broken screen, with a direct path to creating their first entry.

**Why this priority**: Equally fundamental to Story 1 — this screen must handle the zero-entries case correctly from day one, since it is the state every account starts in.

**Independent Test**: Can be fully tested by opening "Meus Registros" on an account with zero entries, confirming the empty-state illustration, message, and call-to-action appear, and confirming that action leads to creating an entry that then populates the screen.

**Acceptance Scenarios**:

1. **Given** an account with no entries at all, **When** the user opens "Meus Registros", **Then** they see the empty state — a notebook illustration, the message "Nenhum registro ainda", and a "Criar primeiro registro" action — instead of an empty list.
2. **Given** the empty state is showing, **When** the user taps "Criar primeiro registro", **Then** the existing entry-creation flow opens; **when** they complete a save, **Then** they return to "Meus Registros" and see that new entry now populating the list in place of the empty state.

---

### User Story 3 - The session expires while browsing (Priority: P2)

A user is scrolled partway through their history when their backend session expires. A clear prompt to log in again appears over the screen, and once they do, they land back exactly where they were — same entries loaded, same scroll position.

**Why this priority**: An edge condition of Story 1 that protects against data loss and disorientation; it cannot be exercised until the timeline itself exists, but it is important enough to this requirement's own acceptance criteria to rank above cosmetic concerns.

**Independent Test**: Can be fully tested by loading the timeline, scrolling to a known position, forcing a session-expired response, confirming the overlay appears without resetting the list, and confirming re-authentication restores that exact scroll position and content.

**Acceptance Scenarios**:

1. **Given** the user is scrolled to a particular position in "Meus Registros", **When** the backend reports the session has expired, **Then** the "Sessão expirada" overlay appears on top of the screen without discarding the loaded entries or resetting the scroll position.
2. **Given** the overlay is visible, **When** the user re-authenticates successfully, **Then** the overlay dismisses and the screen is restored exactly as it was, without reloading or reordering the entries already on screen.

---

### User Story 4 - The synchronization badge tells the truth, even during session trouble (Priority: P3)

While a user is looking at their timeline — including while a session renewal is happening in the background, or while the "Sessão expirada" overlay is up — each entry's synchronization badge keeps showing an accurate state (synchronized, synchronizing, or sync error) and is never frozen, blanked, or delayed by whatever is happening with the session.

**Why this priority**: A correctness and trust property layered on top of Story 1's display rather than a feature of its own; it depends on the timeline and the session-expiry handling of Story 3 already existing.

**Independent Test**: Can be fully tested by putting entries in each of the three badge states, forcing a session expiration and renewal in the background, and confirming every badge's state is unaffected by that session activity throughout.

**Acceptance Scenarios**:

1. **Given** entries in each of the three synchronization states, **When** a session renewal happens silently in the background, **Then** every badge still reflects its correct, unchanged state throughout and after the renewal.
2. **Given** the "Sessão expirada" overlay is visible over the timeline, **When** the user inspects the cards underneath (e.g., once it is dismissed), **Then** every badge's state is exactly what it was before the overlay appeared, with no badge having changed, frozen, or disappeared because of the session event.

---

### Edge Cases

- The device is offline while viewing this screen: already-loaded entries remain visible and scrollable (per the product's offline behavior), but loading further pages fails with a clear, retryable message instead of hanging or crashing; no write of any kind happens from this screen.
- The backend returns an entry whose origin is `chat` — a source this app cannot yet produce (chat and "save to journal" are later units) but that `GET /entries` can still return (e.g., from seed/test data): the card renders with the origin's defined marker and icon like any other, without erroring or treating it as unrecognized.
- The most recent page of entries is itself empty (e.g., nothing happened today or yesterday) while the account has entries further back: paging continues to load those older groups rather than showing the empty state, which is reserved for a true zero-entries account.
- A page load fails outright (not just going offline mid-session): the user sees a clear, retryable loading error for that page without losing or corrupting the entries already shown above it.
- The user reaches the end of their history: the list simply stops loading further pages without an error, with no "end of list" case to treat as a failure.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a "Meus Registros" screen, reachable from the app's existing side-menu navigation, that fetches and displays all of the signed-in user's journal entries regardless of origin (manual, audio, photo, or chat).
- **FR-002**: Entries MUST be grouped under date headings by the calendar day they occurred ("Hoje" for today, "Ontem" for yesterday, an explicit date for anything older), with date groups ordered newest-to-oldest and, within each group, entries ordered newest-to-oldest by their occurrence time; each entry MUST be rendered as a card showing: a marker and icon distinguishing its origin, its time, a text excerpt, any attached tags as read-only chips (only when present), and a per-entry synchronization badge.
- **FR-003**: The system MUST support browsing the user's complete entry history beyond what fits in a single fetch, loading further entries automatically as the user scrolls, and appending them without disturbing already-rendered cards or the user's current scroll position.
- **FR-004**: When the signed-in user has zero entries, the screen MUST show an empty state (illustration, "Nenhum registro ainda", and a "Criar primeiro registro" action) instead of an empty list; completing a save from that action MUST return the user to this screen with the new entry visible in its correct date group.
- **FR-005**: The per-entry synchronization badge MUST independently reflect exactly one of three states — synchronized, synchronizing, or synchronization error — computed for each entry from its own server-confirmed data together with the device's own knowledge of any write still pending or unreconciled for that entry, following the sync-badge semantics; this computation and its on-screen state MUST NOT depend on, be blocked by, or be delayed by session or authentication handling (login, silent renewal, or the expired-session overlay).
- **FR-006**: Loading or refreshing this screen's data MUST check the session and silently renew it when merely expired-but-renewable, without interrupting the user, consistent with the app's existing session-renewal behavior.
- **FR-007**: If the session cannot be silently renewed while this screen is open, the existing "Sessão expirada" overlay MUST appear on top of it without discarding the entries already loaded or the current scroll position; once the user re-authenticates, the overlay MUST dismiss and the screen MUST be restored exactly as it was. Reconciling any single entry's state after such an event (or after any other interruption) MUST be done by re-confirming that specific entry rather than by reloading or reordering the whole list.
- **FR-008**: The screen's header download affordance and its search bar with funnel button MUST be rendered to match the prototype for visual fidelity, but MUST NOT perform export or search/filter behavior in this unit — those behaviors belong to later units and MUST NOT be implemented here.
- **FR-009**: While the device is offline, entries already loaded on this screen MUST remain visible and scrollable; attempting to load further pages MUST fail with a clear, retryable message rather than hanging or crashing, and no write of any kind MUST be attempted from this screen.
- **FR-010**: This unit MUST NOT implement entry search, text filtering, the category/date/type filter sheet, active-filter chips, export generation, or any other behavior reserved for a later unit (RF05, RF06, or any later RF) or for an extension feature (requirements section 2).
- **FR-011**: This unit MUST NOT modify the backend, its API contract, or its configuration in any way.

### Key Entities

- **Journal Entry**: The same persisted, immutable record introduced by RF01 — text content, a creation/occurrence time, and an origin — now also carrying the server-confirmation data (its last-confirmed-write time and the ever-increasing revision counter) and any read-only tags attached to it, and now rendered regardless of which of the four possible origins (`manual`, `audio`, `photo`, `chat`) produced it.
- **Synchronization Badge State**: A derived, per-entry value — synchronized, synchronizing, or synchronization error — computed entirely on the device from an entry's own confirmation data and the device's own record of any write for that entry still pending or unreconciled; never itself stored by or requested directly from the backend.
- **Entry Timeline Page**: The windowed view of the user's full entry history currently loaded on screen — the entries fetched so far and the position to continue from — preserved across scrolling, backgrounding, and a session expiration/renewal cycle so the user's place is never lost.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of a user's entries — across every origin they've used — appear exactly once in the timeline (including an entry created via this screen's own empty-state flow that a later backend fetch also returns, de-duplicated by entry ID), correctly grouped by the day they occurred, with no entry requiring the user to know or remember which capture method created it.
- **SC-002**: 100% of accounts with zero entries see the empty state with a working path into creating their first entry, never a blank, broken, or perpetually-loading screen.
- **SC-003**: Users can scroll through their entire entry history, however long, with additional entries loading automatically in every case, without ever needing a manual "load more" action or losing their scroll position.
- **SC-004**: When a session expires while a user is viewing this screen, 100% of the time their loaded entries and scroll position are unchanged after they re-authenticate.
- **SC-005**: Every entry visible on screen shows one of the three defined synchronization states at all times, unaffected by whatever is happening with the user's session at that moment.

## Assumptions

- The header's download icon and the search bar with its funnel button are rendered to match the prototype (visual fidelity) but are inert placeholders in this unit; their behavior belongs to RF05 (export) and RF06 (search/filter), both later in the delivery order.
- No entry can currently be created with origin `chat` (RF04's chat and RF10's "save to journal" are later units), but because `GET /entries` is origin-agnostic and the prototype's component library already defines a visual treatment for all four origins, this screen renders `chat`-origin entries correctly if the backend ever returns one (e.g., from seed data) rather than treating it as an error case.
- This unit introduces no new local database. It reuses the in-memory entries store RF01 already created and documented as available for later units to read, merging it with the entries this screen fetches and paginates from the backend, de-duplicated by entry ID (see the resolved Clarification on this merge) so an entry created via this screen's own empty-state flow is never shown twice once a later backend fetch also returns it.
- The "synchronizing" and "synchronization error" badge states are implemented completely and correctly per `docs/input/backend/sync-badge.md`, and must respond correctly to whatever pending or failed local write state exists for an entry. Because RF01's existing save flow only ever makes an entry visible anywhere after the backend has already confirmed it, these two states may rarely or never be observed through today's own capture flow alone — that does not make their correct implementation optional, since the requirement's acceptance criterion is about the badge's independence from the authentication stream, not about how often each state is exercised by this unit's own flows.
- Date-heading grouping ("Hoje", "Ontem", explicit dates) uses the device's local calendar day applied to each entry's occurrence timestamp, matching the prototype's labels.
- No entry-detail or full-text screen is introduced in this unit — see the resolved Clarification on `GET /entries/:id`'s purpose; a card's text excerpt is the only rendering of an entry's content here.
- "No BLoC imports another BLoC directly" (the requirement's own architecture-level acceptance criterion) is carried forward as an implementation-time constraint for the planning phase; at the specification level it is expressed through FR-005's and FR-007's independence requirements between the synchronization badge and session/authentication handling.
