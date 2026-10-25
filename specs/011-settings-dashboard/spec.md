# Feature Specification: P-RF09 — Temporal summaries / dashboard

**Feature Branch**: `011-settings-dashboard` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-24

**Status**: Draft

**Input**: User description: "P-RF09 — Temporal summaries / dashboard: Build the Settings screen with the evolution dashboard, and the profile and account actions that live on it. Requirement and acceptance criteria: docs/input/requirements.md, section 1, RF09; RNF05 (section 4) for account deletion. Prototype states: 'Tela 6 — Configurações' in its four dashboard variations and 'Tela 6 — Confirmar exclusão de conta' (prototype extract, section 2.6); profile name editing, 'Sair' and 'Apagar conta'. Backend: GET /dashboard/aggregate, GET /dashboard/narrative, PATCH /account/settings, DELETE /account, POST /auth/logout. Depends on: F000, RF01. Do not implement features of later units, extension features (requirements, section 2), or change the backend."

## Clarifications

### Session 2026-10-24

- Q: What should the dashboard show for an account with more than one entry but not yet enough to fill the chart's full set of bars (e.g. 5 or 15 entries) — a state the spec's three enumerated scenarios (zero / exactly one / more than thirty) never covered? → A: Render the multi-bar chart using whatever of the ten bars the aggregate's buckets actually populate — naturally partial for a small count — and request the narrative for any count of two or more; "more than thirty" is the seed count chosen to reliably exercise a fully-populated demo chart, not a distinct functional threshold.
- Q: For the fixed `all` period, which can span anywhere from a few days to years of history, how should the backend's date-bucketed aggregate be mapped onto the chart's fixed ten bars? → A: Client-side, divide the account's full date range (date of the first entry through today) into ten roughly-equal time slices and sum the backend's per-date counts that fall within each slice to produce each bar's value.
- Q: Should the Face ID/Touch ID toggle be hidden entirely or shown-but-disabled on a device with no usable biometric capability? → A: Hidden entirely — the toggle row is omitted from Settings rather than shown in a disabled state.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Seeing your evolution dashboard (Priority: P1)

The user opens the Settings screen and sees, at a glance, a chart of how their recorded entries have built up over time, plus a short AI-written paragraph that puts that pattern into words. Whether they have no entries yet, just one, or a long history, the screen always shows something coherent rather than breaking or looking empty by accident.

**Why this priority**: This is the entire premise of RF09 — without a correctly rendering chart and narrative, the feature does not exist. **Scope: aggregation and rendering only — the quality of the AI-written narrative text is never evaluated.**

**Independent Test**: Can be fully tested by opening Settings for accounts seeded with zero, one, and more than thirty entries respectively, and confirming each renders its own distinct, non-crashing state with the correct chart and text.

**Acceptance Scenarios**:

1. **Given** the user has zero entries, **When** they open Settings, **Then** the dashboard shows a light-gray placeholder chart icon (no chart) and the text "Comece a registrar para ver sua evolução aqui", with no AI narrative paragraph shown or requested.
2. **Given** the user has exactly one entry, **When** they open Settings, **Then** the dashboard shows a single small bar and the text "Ainda é cedo pra ver um padrão — volte em alguns dias.", with no AI narrative paragraph attempted.
3. **Given** the user has more than thirty entries, **When** they open Settings, **Then** the dashboard shows a multi-bar ochre chart (aggregated into the chart's fixed number of buckets) and, once it loads, an AI-written summary paragraph describing the pattern.
4. **Given** the chart has loaded successfully for an account with data, **When** the AI narrative call fails or times out, **Then** the chart remains visible and correct, and the narrative area shows a distinct "narrativa indisponível" message rather than staying blank or showing the empty-history copy.
5. **Given** the user created a new entry in another screen since Settings was last open, **When** they open Settings again, **Then** the dashboard reflects the new entry in its aggregate — recomputed fresh, not read from a stale result of the previous visit.
6. **Given** the user has more than one entry but not enough to populate every one of the chart's ten bars (e.g. 5 or 15 entries), **When** they open Settings, **Then** the dashboard shows the same multi-bar chart and narrative behavior as the "more than thirty entries" case, just with fewer of the ten bars populated — not the single-bar "Ainda é cedo..." message and not a separate, undefined state.

---

### User Story 2 - Deleting your account for good (Priority: P1)

A user who wants to leave can permanently erase their account and every piece of data tied to it, with a clear, hard-to-misclick warning first, and no way to undo it afterward.

**Why this priority**: Required by RNF05 (LGPD hard delete) — a legal and trust-critical capability, not a convenience feature. Getting this wrong (deleting too little, deleting by accident, or appearing to delete without really doing so) is a compliance and trust failure, not just a bug.

**Independent Test**: Can be fully tested by tapping "Apagar conta", confirming through the destructive dialog, and verifying the account can no longer log in and the Settings screen is left entirely (no residual session), independent of any other screen.

**Acceptance Scenarios**:

1. **Given** the user is on Settings, **When** they tap "Apagar conta", **Then** a centered confirmation dialog appears with a red title ("Apagar sua conta?"), explanatory text that the action is permanent and irreversible, a red "Apagar tudo" button, and an outline "Cancelar" button.
2. **Given** the confirmation dialog is open, **When** the user taps "Cancelar", **Then** the dialog closes, no backend call is made, and Settings is otherwise unaffected.
3. **Given** the confirmation dialog is open, **When** the user taps "Apagar tudo", **Then** the app requests the account's permanent deletion, and on success clears all local session and account state and leaves the user at the app's authentication entry point, with no "account deleted" success screen of its own.
4. **Given** the deletion request fails (timeout, no connection, malformed response), **When** the failure is reported, **Then** the account is left intact, the user sees a clear error, and can retry — the dialog does not falsely report success.

---

### User Story 3 - Signing out and managing your profile (Priority: P2)

From the same screen, the user can see their profile, rename themselves, flip the Face ID/Touch ID unlock preference on or off, and sign out — all lower-stakes, everyday actions compared to Stories 1 and 2.

**Why this priority**: Explicitly named in the feature's scope ("the profile and account actions that live on it") but individually lower risk and lower complexity than the dashboard or account deletion.

**Independent Test**: Can be fully tested by editing the display name and confirming it persists after reopening the app, flipping the biometric toggle and confirming it is saved, and tapping "Sair" and confirming the session ends.

**Acceptance Scenarios**:

1. **Given** the user is on Settings, **When** the screen loads, **Then** it shows an initials avatar (52px), the current display name and email, and the editable-name control as a pencil icon.
2. **Given** the user taps the pencil icon next to their name, **When** the name field becomes editable, **Then** the pencil icon becomes a check icon and the email remains read-only (not editable) throughout.
3. **Given** the user edits their name to a valid value (1–80 characters) and taps the check icon, **When** the save request succeeds, **Then** the field returns to display mode showing the new name, and the new name is still shown after the app is restarted.
4. **Given** the save request fails (timeout, no connection, malformed response), **When** the failure is reported, **Then** the field stays in edit mode with the user's typed text intact, a clear error is shown, and the user can retry without re-typing.
5. **Given** the device supports biometrics, **When** the user flips the "Face ID/Touch ID" toggle on Settings, **Then** the app saves the new preference, and the toggle reflects the saved state (or reverts with an error if the save fails).
6. **Given** the user taps "Sair", **When** the sign-out request completes (or fails), **Then** the local session is cleared either way, and the user lands at the app's authentication entry point with no residual access to their data.

---

### Edge Cases

- The GET /dashboard/aggregate call itself fails (timeout, no connection, malformed response), independent of the narrative call: the dashboard shows a clear, non-crashing error state for the chart area (distinct from the "zero entries" empty state) with a way to retry, and no narrative is requested until the aggregate succeeds.
- The session expires while Settings is open (dashboard loading, name being edited, or a confirmation dialog open): the existing expired-session handling (established by F000, continued by RF07) takes over exactly as it does elsewhere; re-authenticating returns the user to Settings with the dashboard, profile, and any in-progress edit reasonably re-requested, not silently lost.
- The user double-taps "Apagar tudo" or "Sair" before the first request resolves: this does not fire a second concurrent delete/logout request.
- The device has no biometric hardware or nothing enrolled: the toggle row is hidden entirely (not shown in a disabled state), rather than letting the user "turn on" something the device cannot perform.
- The user submits an empty name or one over 80 characters: the save is blocked client-side with a clear validation message, no request is sent, and the field stays in edit mode.
- Opening Settings, viewing the dashboard, editing the profile, or opening (and cancelling) the delete-confirmation dialog does not alter any other screen's state — My Records' list/filters, chat sessions, or action plans are untouched by this unit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Opening Settings MUST request `GET /dashboard/aggregate` and `GET /dashboard/narrative` as two independent calls, so that a narrative failure or delay never blocks the chart from rendering with the aggregate data it already has.
- **FR-002**: The dashboard MUST request and render a single, fixed period and MUST NOT present a user-facing control to switch between periods in this unit — the prototype shows no such control, and only the fixed period's acceptance scenarios (zero / one / more than thirty entries) are in scope.
- **FR-003**: When the aggregate for the active period contains zero entries, the dashboard MUST show the light-gray placeholder chart icon and "Comece a registrar para ver sua evolução aqui", and MUST NOT request or show the narrative.
- **FR-004**: When the aggregate contains exactly one entry, the dashboard MUST show a single small bar and "Ainda é cedo pra ver um padrão — volte em alguns dias.", and MUST NOT request or show the narrative.
- **FR-005**: When the aggregate contains two or more entries, the dashboard MUST render the multi-bar chart using whatever of the chart's ten bars the aggregate's buckets populate — naturally partial for a small count, fully populated once an account has enough history (the "more than thirty entries" scenario is the seed count chosen to reliably exercise a fully-populated chart, not a distinct functional threshold) — and MUST request the narrative, showing it once it resolves.
- **FR-006**: If the narrative call fails, times out, or returns an error after the chart has already rendered successfully, the dashboard MUST show a distinct "narrativa indisponível" message in the narrative's place, without affecting the already-rendered chart and without being confused with the zero-entries empty state.
- **FR-007**: If the aggregate call itself fails, the dashboard MUST show a clear, non-crashing, retryable error state for the chart area, distinct from the zero-entries state, and MUST NOT request the narrative until the aggregate succeeds.
- **FR-008**: The dashboard MUST be recomputed from a fresh backend call every time Settings is opened, never served from a result cached from a previous visit, so that an entry created elsewhere is reflected the next time Settings is opened.
- **FR-009**: Settings MUST display the account's initials avatar, current display name, and current email (read-only) — email MUST NOT be editable in this unit, since `PATCH /account/settings` accepts no email field and rejects attempts to change it.
- **FR-010**: Settings MUST let the user edit their display name through an inline pencil-to-check control; saving MUST call `PATCH /account/settings` with the new `displayName` (1–80 characters) and MUST update the locally displayed/cached name on success.
- **FR-011**: A client-side validation MUST block submitting an empty name or one longer than 80 characters, with no backend call made and the field left in edit mode with an inline error.
- **FR-012**: If the name save fails (timeout, no connection, malformed response), the field MUST remain in edit mode with the user's typed value intact, show a clear retryable error, and MUST NOT silently revert or discard the typed text.
- **FR-013**: On a device where biometrics are available, Settings MUST offer a toggle reflecting the account's current `biometricEnabled` preference and MUST let the user change it; changing it MUST call `PATCH /account/settings` with the new `biometricEnabled` value, continuing the account-settings read/write path RF03 already established for this same flag. On a device with no biometric hardware or nothing enrolled, the toggle row MUST be hidden entirely rather than shown in a disabled state.
- **FR-014**: If the biometric toggle save fails, the toggle MUST revert to its last-confirmed state and show a clear, retryable error, rather than appearing to succeed.
- **FR-015**: This unit MUST NOT build the AI persona selector ("Analítico"/"Empático"/"Socrático") or any other extension feature (requirements, section 2), even though `PATCH /account/settings` also carries a `persona` field for that extension.
- **FR-016**: Settings MUST offer a "Sair" action that calls `POST /auth/logout` and, regardless of whether that call succeeds or fails, MUST clear the local session and any cached account/profile state and return the user to the app's authentication entry point, with no dedicated "signed out" success screen.
- **FR-017**: Settings MUST offer an "Apagar conta" action (styled as destructive/red) that opens a confirmation dialog matching the prototype — red title "Apagar sua conta?", text stating the action is permanent and irreversible, a red "Apagar tudo" button, and an outline "Cancelar" button — and MUST NOT call the delete endpoint before this dialog is explicitly confirmed.
- **FR-018**: Confirming the dialog MUST call `DELETE /account` with the backend-required `confirmation: "DELETE"` value supplied by the app itself (the user is not asked to type the word "DELETE"; the dialog's own destructive button tap is the explicit confirmation, matching the prototype's two-button dialog with no text field).
- **FR-019**: On a successful account deletion, the app MUST clear all local session, cached account/profile, and any other locally held user data, and return the user to the app's authentication entry point, with no "account deleted" success screen of its own — mirroring FR-016's logout behavior.
- **FR-020**: If the deletion request fails (timeout, no connection, malformed response), the account MUST remain intact, the dialog MUST show a clear retryable error, and MUST NOT report success.
- **FR-021**: Cancelling the delete-confirmation dialog MUST dismiss it without any backend call and without altering any Settings state (dashboard, profile fields, or toggle values).
- **FR-022**: Repeated taps on "Sair" or "Apagar tudo" before a prior request for the same action resolves MUST NOT fire a second concurrent request.
- **FR-023**: If the session expires while Settings is open, the existing expired-session handling (F000, continued by RF07) MUST take over exactly as elsewhere, and re-authenticating MUST return the user to a Settings screen that re-requests the dashboard and profile data rather than showing stale or broken state.
- **FR-024**: This unit MUST NOT implement functionality belonging to units later than RF09 in the build order; MUST NOT implement any extension feature (requirements, section 2) beyond what FR-015 already excludes; and MUST NOT modify the backend, its API contract, or its configuration.

### Key Entities

- **Dashboard Aggregate**: The chart data for one period — a set of date-bucketed counts (split by entry source: manual/audio/photo/chat) plus totals. Always returns a well-formed (possibly all-zero) result rather than an error for an account with no entries; recomputed fresh on every Settings visit, never persisted locally across visits.
- **Dashboard Narrative**: An independently-fetched, AI-generated paragraph describing the aggregate's pattern for the same period. Can succeed, fail, or be skipped (zero/one-entry scenarios) independently of whether the aggregate itself loaded successfully.
- **Account Profile**: The user's editable identity on this screen — display name (editable), email (read-only), and the biometric-unlock preference (editable, shared with RF03). Since the backend only ever returns this profile as the response of a successful `PATCH /account/settings` call — there is no endpoint to read it standalone — the app treats the most recent successful write (from this unit or from RF03's first-time setup) as the locally held source of truth for what this screen displays, defaulting sensibly (e.g., name derived from email) for an account that has never had a successful write.
- **Account Deletion**: A one-way, irreversible action with no corresponding entity afterward — it ends the account and every row tied to it (RNF05), including the signed-in session itself.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across accounts seeded with zero, one, and more than thirty entries, the dashboard renders the correct dedicated state in 100% of cases with zero crashes and zero mixed-up states (e.g., the empty-history message never appears alongside chart data).
- **SC-002**: In 100% of forced narrative-failure cases where the chart data itself loaded successfully, the chart remains fully visible and correct, with a distinct, clear explanation shown only in the narrative's place.
- **SC-003**: 100% of confirmed account-deletion attempts that succeed on the backend leave the device with no retained local session, cached profile, or other user data, and no path back into the account without creating a new one.
- **SC-004**: Zero account deletions occur without the user explicitly reaching and confirming the destructive dialog — cancelling or dismissing it never results in a deleted account.
- **SC-005**: A display-name edit that succeeds is still showing the new value after the app is fully restarted, in 100% of tested cases.
- **SC-006**: Signing out, from any state the screen can be in, always results in the user reaching the authentication entry point with no residual access, in 100% of tested cases.

## Assumptions

- **Dashboard period**: The dashboard requests a single, fixed period rather than exposing a period-switching control, since neither the prototype's four Settings states nor its component library describes any period selector, tab, or chip for this screen — only the entry-count-driven states (zero / one / more-than-thirty) are depicted. The backend's `period` enum (`7d`/`30d`/`90d`/`all`) exists independently of this UI decision; this unit sends one fixed value (`all`, so the "more than thirty entries" scenario and the cache-invalidation acceptance criterion are both naturally satisfiable from the user's full history) and does not expose the other three values as a feature of this unit.
- **No endpoint to read the current profile**: `GET /auth/session` returns only `id` and `email`; the only way to learn `displayName`, `persona`, or `biometricEnabled` is the response body of a successful `PATCH /account/settings` call. This unit treats the most recent such response (including ones written by RF03's first-time biometric setup) as the locally cached source of truth for what Settings displays, with a sensible default (e.g., a name derived from the email's local part) for an account whose profile has never been successfully written.
- **Email is read-only despite the prototype's pencil icon**: The prototype extract describes "editable name/e-mail" with a shared pencil-to-check control, but the frozen API contract's `PATCH /account/settings` accepts no `email` field and explicitly rejects email changes. Per the requirements document's own rule ("where this differs from the API contract, the contract prevails"), this unit treats only the display name as editable and shows the email as plain, read-only text.
- **No typed "DELETE" confirmation text field**: The backend requires the literal request field `confirmation: "DELETE"`, but the prototype's confirmation dialog shows only a title, explanatory text, and two buttons — no text input. This unit treats the destructive button tap itself as the required explicit confirmation and supplies the literal value in the request automatically, without asking the user to type anything.
- **Where "Sair" and "Apagar tudo" land**: The prototype extract states both actions return to the "Biometria" screen with no dedicated success screen of their own. Since both actions end with no stored session, and F000 already routes a device with no stored session to the login/sign-up screen on next launch, this unit treats "the app's authentication entry point" as whatever F000/RF03 already resolve that case to (the vault screen if a device-level PIN/biometric flow applies with no session, falling through to login otherwise) rather than building a separate destination.
- **Biometric toggle is in scope, persona is not**: RF03's own specification explicitly defers the biometric on/off toggle (outside of first-time setup) to "the Settings screen built by the RF09 unit." The persona selector, by contrast, is explicitly listed as a non-implemented extension feature (requirements, section 2) even though both preferences share the same `PATCH /account/settings` endpoint.
- **Chart's fixed bucket count and bucketing algorithm**: The chart always has ten bars (the prototype's reference mock). For the fixed `all` period — which can span anywhere from a few days to years of account history — this unit divides the account's full date range (date of the first entry through today) into ten roughly-equal time slices and sums the aggregate's per-date `count` values falling within each slice to produce each bar's value. An account whose history is short or clustered naturally produces a chart with some empty bars rather than this being treated as a defect; this unit does not need to support an arbitrary, unbounded number of visible bars.
- **Multi-bar chart applies to any count above one, not only "more than thirty"**: FR-005's chart-and-narrative state is not gated on a literal minimum entry count beyond "two or more" — an account with, say, 5 or 15 entries gets the same multi-bar chart (naturally sparser) and narrative request as a 30+ entry account. The "more than thirty entries" acceptance scenario exists only to guarantee a chart where every one of the ten bars is populated, for a clean, unambiguous test case — not because counts between two and thirty are a separate, unspecified state.
