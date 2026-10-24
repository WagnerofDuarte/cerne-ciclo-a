# Feature Specification: P-RF05 — Personal summary export

**Feature Branch**: `010-personal-summary-export` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-24

**Status**: Draft

## Clarifications

### Session 2026-10-24

- Q: What should the export sheet show when the job fails entirely (FR-007 — no data produced at all, not just the AI narrative), given the prototype only defines an "Erro" state for the narrative-only failure and has no visual for this harder case? → A: Generic failure message (reusing the error color/icon family, with copy distinct from FR-006's narrative-only explanation), no PDF/raw buttons, and only the existing "Fechar" link — no dedicated in-sheet retry control, and the same text is shown regardless of the backend's specific errorCode. Retrying means closing the sheet and tapping the download icon again (FR-011's existing path) (resolved by technical judgment per user direction, applying Constitution Principle I).

**Input**: User description: "P-RF05 — Personal summary export: Let the user export a narrative summary of their entries as PDF, and always be able to download the raw data. Requirement and acceptance criteria: docs/input/requirements.md, section 1, RF05. Prototype states: the export sheet — 'Pendente', 'Processando', 'Concluído', 'Erro', 'Período vazio' (prototype extract, section 2.5); opened by the download icon of Meus Registros. Screen ↔ job status mapping: docs/input/backend/export-screen-states.md. Backend: POST /export/summary, GET /export/:jobId/status, GET /export/:jobId/download. Depends on: RF07. Do not implement features of later units, extension features (requirements, section 2), or change the backend."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Getting a narrative PDF of your entries (Priority: P1)

From My Records, the user taps the download icon and asks to export a summary of their entries. They watch the export prepare and then generate an AI narrative, and end up with a PDF they can download that tells the story of that period, alongside their original entries.

**Why this priority**: This is the entire premise of RF05 — a narrative export is the feature's main value. Without it reaching a downloadable PDF, the feature does not exist.

**Independent Test**: Can be fully tested by opening the export sheet for a period that has at least one entry, letting the job run to completion, and confirming a PDF download succeeds and contains a narrative summary.

**Acceptance Scenarios**:

1. **Given** the user is on My Records with at least one entry in the exported period, **When** they tap the download icon, **Then** the export sheet opens and shows "Pendente" (spinner, "Preparando exportação...").
2. **Given** the export sheet is showing "Pendente", **When** the backend starts generating the AI narrative, **Then** the sheet shows "Processando" ("Gerando resumo com IA...", progress bar) without the user doing anything further.
3. **Given** the job finishes with both the data and the narrative ready, **When** the sheet updates, **Then** it shows "Concluído" (green check, "Resumo pronto") with two enabled buttons — "Baixar PDF" (primary) and "Baixar dados brutos" (outline).
4. **Given** the sheet is showing "Concluído", **When** the user taps "Baixar PDF", **Then** the app downloads a PDF file containing the generated narrative summary for that period.

---

### User Story 2 - Your raw data is never held hostage by the AI narrative (Priority: P1)

Generating the narrative summary can fail — the AI call can time out or error out. When that happens, the user can still get their own data out: the export sheet explains that only the narrative failed and lets them download their raw entries anyway.

**Why this priority**: Called out explicitly as its own acceptance criterion ("a failure generating the narrative text still allows downloading the raw data without the narrative — the export is not blocked by an AI failure"). Without this, a flaky AI call would make a user's own data unreachable, which is a trust-breaking failure for a personal-data feature.

**Independent Test**: Can be fully tested by forcing the narrative generation to fail (e.g., simulating an AI timeout) for a period that does have entries, and confirming the sheet still offers — and completes — a raw-data download.

**Acceptance Scenarios**:

1. **Given** the export job's data finished successfully but the narrative generation failed or was skipped, **When** the sheet updates, **Then** it shows "Erro" (red warning) with text explaining that the AI summary failed but the data remains available, and exactly one enabled button — "Baixar dados brutos" (no "Baixar PDF" option is shown).
2. **Given** the sheet is showing this "Erro" state, **When** the user taps "Baixar dados brutos", **Then** the download succeeds with the user's raw entry data, with no dependency on the narrative ever having completed.
3. **Given** the export job fails entirely (not only the narrative — no data was produced either), **When** the sheet updates, **Then** it shows a failure state with no download option at all, which is visibly a harder failure than the narrative-only case in Scenario 1 (nothing is available to download because nothing was produced).

---

### User Story 3 - Exporting a period with nothing in it is handled gracefully (Priority: P2)

The user requests an export for a period that turns out to have zero entries. Instead of an empty or broken PDF, or the app hanging, they get a clear message telling them there is nothing to export.

**Why this priority**: Called out explicitly as an acceptance criterion ("an export job with zero entries in the period returns a handled error state — not an empty PDF, not a crash"). It is a correctness guarantee as much as a UX one.

**Independent Test**: Can be fully tested by requesting an export for a period known to contain zero entries and confirming the sheet shows the dedicated empty-period state immediately, with no job ever appearing to run and no file ever offered for download.

**Acceptance Scenarios**:

1. **Given** the user selects a period with zero entries, **When** they request the export, **Then** the sheet shows "Período vazio" ("Nenhum registro nesse período." plus a suggestion to adjust the filter) directly — never "Pendente" or "Processando" first — and offers no download button.
2. **Given** the sheet is showing "Período vazio", **When** the user taps "Fechar", **Then** the sheet dismisses without having created any downloadable file and without affecting My Records' own list or filters.

---

### Edge Cases

- The user taps "Fechar" while the job is still "Pendente" or "Processando": the sheet dismisses and the in-flight job is left alone server-side; the app does not keep polling it in the background once the sheet is gone, and it is not treated as the "current" export if the sheet is reopened.
- The user taps the download icon again while an export sheet/job from a previous tap is still in flight for the same period: this does not create a second concurrent export job — the tap is treated as a no-op (or reopens the same in-flight sheet) rather than firing a second `POST /export/summary`.
- The session expires while the export sheet is open: the existing expired-session overlay (RF07) takes over exactly as it does for the rest of the screen; once re-authenticated, the sheet resumes reflecting the export job's real status rather than being stuck mid-attempt.
- The download itself (PDF or raw data) fails after the job reached a downloadable state (e.g., the signed URL expired or the connection drops mid-download): the corresponding button returns to a retryable state rather than leaving the sheet stuck or silently failing.
- Opening the export sheet, polling its job, or downloading a file does not alter My Records' list, its active filters, its sync badges, or its scroll position in any way.
- Opening My Records itself, its filters, its tags, the chat, the dashboard, or any other screen or action not named in this feature: unaffected by this unit and not touched by it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A download icon in My Records' header MUST open the export bottom sheet.
- **FR-002**: Opening the export sheet MUST request an export for the period currently represented by My Records' active date filter (or the full history if no date filter is applied), including the narrative by default.
- **FR-003**: If the requested period contains zero entries, the sheet MUST show the "Período vazio" state immediately — never "Pendente" or "Processando" first — with no download control offered and no job left running.
- **FR-004**: For a period with at least one entry, the sheet MUST show "Pendente" (spinner, "Preparando exportação...") immediately after the request, then transition to "Processando" ("Gerando resumo com IA...", progress bar) while the job is still working toward a result, without requiring any user action to advance between these states.
- **FR-005**: When the job's data and narrative both complete successfully, the sheet MUST show "Concluído" with two enabled controls — "Baixar PDF" (primary) and "Baixar dados brutos" (outline).
- **FR-006**: When the job's data completes but the narrative generation fails or is skipped, the sheet MUST show "Erro" with text explaining that the AI summary failed while the data remains available, and exactly one enabled control — "Baixar dados brutos" — with no PDF option offered.
- **FR-007**: When the job fails entirely (no data produced, not only the narrative), the sheet MUST show a failure state with a generic message explaining the export itself could not be generated — text distinct from FR-006's narrative-only explanation, shown the same way regardless of the backend's specific error code — no download control at all, and only the "Fechar" link available (no dedicated in-sheet retry control; retrying means closing the sheet and tapping the download icon again, per FR-011). This state MUST be visually and functionally distinct from FR-006's narrative-only failure.
- **FR-008**: "Baixar PDF" MUST only ever be offered when FR-005's conditions hold, and tapping it MUST download a PDF containing the generated narrative for the exported period.
- **FR-009**: "Baixar dados brutos" MUST be offered in both the FR-005 and FR-006 outcomes, and tapping it MUST download the user's raw entry data for the exported period, independent of whether the narrative ever succeeded.
- **FR-010**: A "Fechar" link MUST be present and functional in every one of the six sheet states ("Pendente", "Processando", "Concluído", "Erro" [FR-006's narrative-only failure], the full-failure state [FR-007], and "Período vazio"), dismissing the sheet without cancelling any in-flight backend job and without affecting My Records' own list, filters, or scroll position.
- **FR-011**: Repeated taps on the download icon, or on a download button that already has a request in flight, MUST NOT create multiple concurrent export jobs or fire duplicate download requests for the same action.
- **FR-012**: If the session expires while the export sheet is open, the existing session-expiration handling (RF07) MUST take over exactly as it does elsewhere on the screen, and the sheet MUST resume reflecting the export job's actual status once re-authenticated rather than remaining stuck.
- **FR-013**: This unit MUST NOT implement manual-tag or category filtering, or any other extension feature (requirements, section 2); MUST NOT implement functionality belonging to units later than RF05 in the build order; and MUST NOT modify the backend, its API contract, or its configuration.

### Key Entities

- **Export Job**: An ephemeral, user-scoped job created by one export request, covering one period of entries. Carries an overall status (preparing / generating / data-ready-without-narrative / fully done / failed) and a narrative status that advances independently of it (pending / generating / done / failed / skipped), since the raw data and the AI narrative can finish — or fail — on different timelines. Produces, at most, two downloadable artifacts (a PDF narrative and the raw data) once it reaches a state where either is available. It is not a journal entry and is never shown anywhere outside the export sheet.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user exporting a period that has at least one entry can reach a downloaded, readable narrative PDF end-to-end, with zero crashes and zero empty or malformed files, across all tested periods.
- **SC-002**: In 100% of forced narrative-failure cases (for a period with entries), the user still completes a raw-data download from the same sheet, with a clear explanation of what happened.
- **SC-003**: Exporting a period with zero entries is communicated through a single, clear sheet state in 100% of tested cases, with zero downloadable files ever produced and zero crashes.
- **SC-004**: Closing the export sheet, from any of its five states, leaves My Records' list, active filters, and scroll position completely unchanged in 100% of tested cases.
- **SC-005**: No export attempt — successful, narrative-failed, fully failed, or empty-period — ever leaves the sheet showing a "preparing" or "generating" indicator indefinitely; every attempt reaches one of its defined terminal states within the system's normal response time.

## Assumptions

- **Period selection**: The export sheet exports whatever period My Records' own active date filter currently represents (or the entire history, if no date filter is applied) rather than offering a separate period picker inside the sheet itself — the prototype's export sheet shows no period-selection control of its own, and My Records already owns date filtering (RF06/RF07).
- **Narrative inclusion**: Every export request includes the narrative by default (there is no prototype control to opt out of it upfront) — a request only ends up "without narrative" when generation fails or is skipped, never by the user's deliberate choice.
- **When downloads become available**: The two download buttons appear only once the job reaches one of the sheet's defined terminal states — "Concluído" or "Erro" — matching the prototype's literal five-state catalog. The backend can report an intermediate state where the raw data is ready but the narrative is still generating; this unit treats that intermediate state as still part of "Processando" visually (no early download link appears mid-generation), since the prototype defines no sixth state for it and the acceptance criteria ("the export is not blocked by an AI failure") are fully satisfied once "Erro" exposes the raw-data download — nothing in the source material requires exposing it earlier than that.
- **Full job failure vs. narrative-only failure**: These are treated as two distinct outcomes (see FR-006 vs. FR-007) because the backend distinguishes them (an overall failed job produces no data at all, so there is nothing to download) — the prototype's single "Erro" state is understood to describe the narrative-only failure specifically, since its own text says the data remains available.
- **Resuming an export after leaving the sheet**: Closing "Fechar" does not cancel the underlying job, but this unit does not add a job-history or notification feature for jobs left running in the background — the prototype has no such affordance. Reopening the export sheet afterward is a fresh request; it does not need to return to a leftover job.
- **File handling on download**: "Baixar PDF" and "Baixar dados brutos" trigger the platform's standard way of saving or sharing a downloaded file; this unit is not responsible for building a custom in-app file viewer.
- **Status polling**: The exact interval at which the sheet checks `GET /export/:jobId/status` while "Pendente"/"Processando" is an implementation detail, not a product requirement, as long as it is frequent enough that the user does not perceive the sheet as stuck.
