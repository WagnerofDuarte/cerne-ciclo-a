# Feature Specification: P-RF01 — Multimodal capture

**Feature Branch**: `003-multimodal-capture` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-12

**Status**: Draft

**Input**: User description: "P-RF01 — Multimodal capture: Let the user create a journal entry by text, audio recording or photo, from the Insertion Modal, per docs/input/requirements.md section 1 (RF01) and its acceptance criteria. Prototype states: Insertion modal — 'Texto', 'Áudio — Gravando', 'Foto — Captura' (prototype extract, section 2.3), opened by the '+' button of Home/Chat. Backend: POST /entries with source manual/audio/photo. Depends on F000, RF03. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## Clarifications

### Session 2026-10-12

- Q: When a user stops recording audio or captures a photo in this unit, how should Save behave, given RF02 (speech-to-text/OCR) is an explicitly later unit and the prototype states listed for this unit stop at "Gravando" and "Captura"? → A: RF01 performs the minimal on-device transcription (audio) or backend OCR call (photo) needed to produce text content inline, as part of confirming Save, shown with only a plain/generic loading indicator — not RF02's dedicated "Processando / Transcrito / Reconhecido / Erro" screens, their editable-text review step, or their specific retry affordances ("Tentar novamente", "Salvar só a foto"). This is the only reading under which RF01 alone satisfies its own stated acceptance criterion that all three modalities "result in the same persisted-entry format," since entries are immutable (no `PATCH`/`DELETE /entries/:id`) and therefore cannot be corrected after creation — recognition must happen before the entry exists. (Resolved by technical judgment per user direction, applying Constitution Principle I, where the input docs are silent on this exact boundary.)
- Q: After a successful Save, the modal closes back to Home/Chat — but Home/Chat never renders journal entries (those appear only in the later "Meus Registros" unit, RF07). What should FR-011's "reflected in the app's state" actually look like on Home/Chat itself? → A: Nothing new is shown on Home/Chat. The prototype documents no confirmation screen, toast, or any other on-screen change for this flow, and inventing one would conflict with Principle IV's visual-fidelity constraint (faithfulness to a frozen prototype that defines no such state) as well as SC-003's "no required intermediate screens." "Reflected in the app's state" means only that the newly created entry is added to the app's local entries store/cache — the same store later units (e.g., RF07) will read from — not that Home/Chat's UI changes in any visible way. (Resolved by technical judgment per user direction, applying Constitution Principles I and IV, where the input docs are silent on this exact boundary.)
- Q: The backend's `POST /media/ocr` response carries a `confidence: "high"|"low"` field alongside the recognized text — does a `low`-confidence recognition get treated any differently from `high`-confidence before Save completes? → A: No. This unit's scope (FR-007) stops at automatically producing recognized text before Save; any quality gating, warning, or review step keyed to confidence is exactly the kind of recognition-quality handling RF02 owns (its "Transcrito"/"Reconhecido" review states, deliberately deferred here). Confidence is therefore ignored in this unit: any non-empty recognized text, regardless of confidence, proceeds to Save normally; only the already-specified zero-usable-text case (Edge Cases) is treated as a failure. (Resolved by technical judgment per user direction, applying Constitution Principle I, where the input docs are silent on this exact boundary.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Writing a journal entry as text (Priority: P1)

A user wants to quickly note something in words. They tap "+" on Home/Chat, the Insertion Modal opens on its "Texto" tab, they write freely in the text field, and tap "Salvar". The modal closes and the note now exists as one of their journal entries.

**Why this priority**: The simplest and fully self-contained of the three capture paths — it has no dependency on recognition of any kind, so it is the first thing that must work end to end.

**Independent Test**: Can be fully tested by tapping "+", typing text into the Texto tab, tapping "Salvar", and confirming a new entry with that exact text and origin "manual" now exists, and the modal has closed back to Home/Chat.

**Acceptance Scenarios**:

1. **Given** Home/Chat is open, **When** the user taps "+", **Then** the Insertion Modal opens as an overlay on top of Home/Chat (which stays in place underneath), defaulted to the "Texto" tab with an empty field.
2. **Given** the Texto tab with text typed into the field, **When** the user taps "Salvar", **Then** a new journal entry is created with that text as its content and origin "manual", and the modal closes, returning to Home/Chat.
3. **Given** the Texto tab with an empty field, **When** the user looks at "Salvar", **Then** the action is unavailable (disabled), so an empty entry can never be created.

---

### User Story 2 - Recording a journal entry as audio (Priority: P1)

A user prefers to speak rather than type. They tap "+", switch to the "Áudio" tab, tap the round start control, and recording begins with a visible waveform and timer. They tap stop, and after a brief moment the spoken content is saved as a journal entry just like a written one.

**Why this priority**: Voice capture is one of the two microphone/camera-dependent paths and, together with Story 1, establishes that every modality converges on the same entry format — the central acceptance criterion of this unit.

**Independent Test**: Can be fully tested by opening the Áudio tab, recording a short spoken note, stopping the recording, confirming Save completes, and confirming a new entry exists with origin "audio" and text content derived from what was spoken.

**Acceptance Scenarios**:

1. **Given** the Insertion Modal is open, **When** the user switches to the "Áudio" tab, **Then** it shows an idle state with a round start control and the caption "Toque para gravar", with no recording yet; **When** the user taps that control, **Then** recording starts, showing a stop control, an animated waveform, and a running mm:ss timer.
2. **Given** an active recording, **When** the user taps stop, **Then** the recording ends and the system automatically transcribes it and completes the save as part of confirming the capture, producing one new entry with origin "audio" and the transcribed text as its content.
3. **Given** a completed audio capture that is being transcribed and saved, **When** that processing is underway, **Then** the user sees a plain loading indicator (not a detailed multi-state screen) until it finishes.
4. **Given** transcription or the save itself fails (e.g., inaudible recording, network timeout), **When** that happens, **Then** no entry is created, a clear failure message is shown, and the user can retry without having to re-record, as long as the captured audio is still held locally.

---

### User Story 3 - Capturing a journal entry from a photo (Priority: P2)

A user has something written down on paper, a receipt, or a whiteboard. They tap "+", switch to the "Foto" tab, choose "Câmera" or "Galeria", and the text in the image becomes a journal entry.

**Why this priority**: Mirrors Story 2's recognition pipeline for a second input type; ordered after audio because the text-recognition concern it shares with Story 2 is already established there.

**Independent Test**: Can be fully tested by opening the Foto tab, choosing "Câmera" or "Galeria" to supply an image containing legible text, confirming the save completes, and confirming a new entry exists with origin "photo" and the recognized text as its content.

**Acceptance Scenarios**:

1. **Given** the Insertion Modal is open, **When** the user switches to the "Foto" tab, **Then** two options are shown — "Câmera" and "Galeria" — with no image selected yet.
2. **Given** the user picks "Câmera" or "Galeria" and supplies an image, **When** that image is provided, **Then** the system automatically extracts its text and completes the save as part of confirming the capture, producing one new entry with origin "photo" and the recognized text as its content.
3. **Given** a completed photo capture that is being recognized and saved, **When** that processing is underway, **Then** the user sees a plain loading indicator (not a detailed multi-state screen) until it finishes.
4. **Given** text recognition or the save itself fails, **When** that happens, **Then** no entry is created, a clear failure message is shown, and the user can retry without having to recapture the image, as long as it is still held locally.

---

### User Story 4 - Abandoning a capture leaves nothing behind (Priority: P3)

A user starts writing, recording, or photographing, changes their mind, and backs out. Nothing about that attempt is saved anywhere.

**Why this priority**: A safety property that applies across all three modalities rather than a feature of its own; depends on Stories 1–3 already existing to have something to abandon.

**Independent Test**: Can be fully tested by starting each modality (typing a partial note, starting a recording, opening the camera/gallery picker) and closing the modal or navigating away before tapping Salvar, then confirming no new entry was created in any case.

**Acceptance Scenarios**:

1. **Given** partially typed text in the Texto tab, **When** the user closes the modal without tapping "Salvar", **Then** no entry is created and the draft text is discarded.
2. **Given** an in-progress audio recording, **When** the user closes the modal or stops without confirming save, **Then** no entry is created and no partially-recorded audio is persisted as an entry.
3. **Given** the Foto tab's camera/gallery picker is open, **When** the user cancels it without completing a capture, **Then** no entry is created.

---

### Edge Cases

- Microphone or camera permission is denied at the OS level: the respective tab shows an explanatory message in place of the recording/capture controls, instead of silently failing or crashing.
- The user switches tabs while a recording is in progress: the in-progress recording is discarded (same outcome as closing the modal), since no partial entry may survive regardless of which tab is active afterward.
- The app is backgrounded or killed while a capture is in progress and unsaved, **or while it is stopped/captured and awaiting retry after a recognition or save failure**: nothing is lost that mattered, because nothing was persisted yet — the captured audio/image and any pending retry state exist only in memory for the current app session. On return (after a mere backgrounding, the modal resumes normally; after a kill, the modal reopens to its default empty state), and if the content was lost to a process kill, the user must recapture rather than retry.
- Transcription or OCR succeeds technically but returns no usable text (e.g., silence, a blank or illegible image): Save fails with a clear message rather than creating an empty or near-empty entry. A `low`-confidence OCR result that still contains text is not treated as a failure — confidence-based quality gating is out of scope for this unit (reserved for RF02) — so Save proceeds normally with whatever text was recognized.
- The device is offline when the user taps "Salvar": the save is blocked immediately with a clear message, without attempting a network call that cannot succeed, consistent with this product's cloud-only architecture (no offline writes).
- The user double-taps "Salvar": only one entry is ever created per confirmed capture, never duplicates.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an Insertion Modal, opened by the "+" button on Home/Chat, shown as an overlay above Home/Chat (with a darkened scrim) without discarding or navigating away from Home/Chat's state underneath.
- **FR-002**: The Insertion Modal MUST present exactly three capture modes as tabs — "Texto", "Áudio", "Foto" — with the active tab visually distinguished, and MUST reset every tab to its initial, empty state each time the modal is freshly opened.
- **FR-003**: The "Texto" tab MUST provide a free multiline text field and a "Salvar" action that is unavailable while the field is empty.
- **FR-004**: The "Áudio" tab MUST open on an idle state showing a round start control with the caption "Toque para gravar"; real-time audio recording MUST start only once the user taps that control, at which point a stop control, an animated waveform, and a running timer appear, matching the "Gravando" state.
- **FR-005**: The "Foto" tab MUST offer the user a choice between the device camera and the photo gallery to supply a single image, matching the "Captura" state.
- **FR-006**: Confirming Save on any modality MUST result in exactly one persisted journal entry, created through the entry-creation endpoint, carrying the content appropriate to that modality and the correct origin (`manual` for text, `audio` for audio, `photo` for photo) — never a chat message. This guarantee MUST hold even if the user triggers Save/stop/picker-confirm more than once in quick succession for the same capture (e.g., a double tap): the system MUST ignore any such trigger received while a save for that capture is already in flight, so at most one entry is ever created per confirmed capture.
- **FR-007**: For the audio and photo modalities, confirming Save MUST automatically produce the text content the entry requires — via on-device transcription for audio and backend text recognition for photo — before the entry is created, shown to the user only as a plain, generic loading indicator while it happens; this unit MUST NOT present a dedicated multi-state screen (distinct "processing", "transcribed"/"recognized", or "error" states with their own styling), an editable review step for the recognized text, or modality-specific retry affordances such as "Tentar novamente" or "Salvar só a foto" — those are reserved for a later unit.
- **FR-008**: If a capture is abandoned before Save is confirmed — the modal is closed, the user navigates away, a recording is stopped without saving, or an in-progress camera/gallery selection is cancelled — the system MUST NOT create any entry, partial or empty, for that capture.
- **FR-009**: If recognizing audio or photo content fails, or the entry-creation call itself fails, when Save is attempted, the system MUST NOT create a partial or placeholder entry; it MUST show a clear failure indication and let the user retry the same captured audio or image without requiring a fresh recording or photo, as long as that captured content is still held locally for the current app session (this guarantee does not survive the app process being killed — see Edge Cases).
- **FR-010**: Creating an entry MUST require network connectivity; when the device is offline, the system MUST block the Save action with a clear message rather than attempting a write that cannot succeed.
- **FR-011**: On a successful Save, the Insertion Modal MUST close and return the user to Home/Chat with no other visible change to that screen (the prototype defines no confirmation screen or toast for this flow); the newly created entry MUST be reflected only in the app's local entries store/cache, available for later units (e.g., Meus Registros, RF07) to read.
- **FR-012**: This unit MUST NOT implement any functional behavior belonging to later-delivered requirements (RF02's dedicated recognition-state screens beyond the minimal loading indicator in FR-007, and the full behavior of RF04, RF05, RF06, RF07, RF08, RF09, RF10), nor any extension feature (manual tags/categories, action plans, persona selection).
- **FR-013**: This unit MUST NOT modify the backend, its API contract, or its configuration in any way.

### Key Entities

- **Journal Entry**: A persisted record with text content, an origin (`manual`, `audio`, or `photo` for this unit), and a creation time; structurally identical regardless of which modality produced it, and immutable once created.
- **Capture Session**: Ephemeral, device-only state that exists only while the Insertion Modal is open — which tab is active, any in-progress recording or selected image, and text recognized but not yet saved. It is entirely discarded if the capture is abandoned, and never itself becomes a persisted entry.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of successfully saved captures, across all three modalities, produce a journal entry that is structurally identical to the others (differing only in its content and origin) — none is treated as a special case downstream.
- **SC-002**: 100% of abandoned captures (modal closed, navigation away, in-progress recording stopped without saving, or picker cancelled) leave zero entries behind.
- **SC-003**: Users can go from tapping "+" to a newly saved text entry in well under 15 seconds of their own interaction time (typing and one tap), with no required intermediate screens.
- **SC-004**: A failure recognizing or saving audio or photo content never forces the user to redo the recording or recapture the photo while that captured content is still available — 0% of such failures result in lost source material.
- **SC-005**: 100% of save attempts made while offline are blocked with a clear message before any network call is attempted.

## Assumptions

- The "Áudio" tab opens on an idle state (round start control, "Toque para gravar") and only requests microphone permission and begins recording once the user taps that control — matching the prototype's Tela 2, which shows this idle state before "Gravando."
- Audio transcription runs on-device (per the project's fixed technology stack) and photo text recognition runs via the backend's existing OCR endpoint (which does not persist the image); invoking both is a use of already-established, fixed stack pieces rather than new functionality reserved for RF02 — only RF02's dedicated multi-state UI, editable review, and modality-specific retry/fallback actions are deferred, per the resolved Clarification above.
- No maximum audio recording duration is defined by the input documents; this unit imposes none beyond ordinary device/storage limits.
- Because entries cannot be edited or deleted after creation, recognition (transcription or OCR) must complete successfully before an entry is created for audio or photo — there is no later correction step in this unit.
- Saving is blocked while offline following the same cloud-only, no-offline-writes pattern already established elsewhere in the product (chat, search); this unit does not introduce an offline queue.
- "Salvar" being disabled while a save is already in flight (FR-006) is the mechanism satisfying that requirement's idempotency clause, mirroring the explicit callout RF10's own requirements.md text gives this same safeguard.
- Switching tabs mid-recording discards the in-progress recording, since the prototype documentation leaves this behavior undefined and no partial entry may survive regardless.
