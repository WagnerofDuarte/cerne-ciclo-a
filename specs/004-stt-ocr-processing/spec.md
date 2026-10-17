# Feature Specification: P-RF02 — Speech-to-text / OCR processing

**Feature Branch**: `004-stt-ocr-processing` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "P-RF02 — Speech-to-text / OCR processing: Turn captured audio into text on the device, and photos into text through the backend, before saving the entry. Requirement and acceptance criteria: docs/input/requirements.md, section 1, RF02. Prototype states: 'Áudio — Processando / Transcrito / Erro' and 'Foto — Processando OCR / Reconhecido / Erro' (prototype extract, sections 2.3 and 4). On-device speech-to-text with whisper_ggml (audio never goes to the backend); OCR with POST /media/ocr; then POST /entries. Test material: docs/input/backend/fixtures/. Depends on: RF01. Do not implement features of later units, extension features (requirements section 2), or change the backend."

## Clarifications

### Session 2026-10-13

- Q: RF01's own specification (FR-007) deliberately stopped at a plain, generic loading indicator for audio/photo recognition and explicitly deferred "a dedicated multi-state screen..., an editable review step..., or modality-specific retry affordances" to "a later unit." Does this unit replace that RF01 behavior, or sit alongside it? → A: This unit replaces RF01's placeholder recognition UX for the audio and photo tabs with the dedicated states the prototype defines (`docs/input/prototype/prototype-extract.md` §2.3, §4): "Processando"/"Transcrevendo" (spinner, frozen waveform), "Transcrito"/"Reconhecido" (editable text, explicit "Salvar"), and "Erro" (retry, plus photo's extra "Salvar só a foto"). Concretely, stopping a recording or supplying an image no longer completes the save automatically — it starts recognition, and the user reviews (and may edit) the result before explicitly confirming "Salvar." The text-entry tab (no recognition involved) is unaffected and stays exactly as RF01 built it. (Resolved by technical judgment per user direction, applying Constitution Principle I, where RF01's own text names this unit as the owner of that deferred behavior.)
- Q: The prototype's "Foto — Erro" state offers "Salvar só a foto," which saves the record "even without extracted text" (§4). The backend never persists the photo itself (`POST /media/ocr` summary: "the image is never persisted") and `POST /entries` requires `content` with `minLength: 1` — so what content does that saved entry actually carry? → A: A fixed, non-empty placeholder string (not the empty string, which the backend contract forbids) is sent as `content`, with `source: "photo"`; no later OCR attempt is made for that capture once this action is taken. This is the only reading consistent with the frozen `POST /entries` contract, which has no field for an unrecognized image and no way to accept empty content. (Resolved by technical judgment per user direction, applying Constitution Principle I, where the input docs specify the UI affordance but not the entry's stored content.)
- Q: `POST /media/ocr`'s success response always carries a `confidence: "high"|"low"` field alongside the recognized text. RF01's own spec explicitly deferred any confidence-based quality gating to this unit ("confidence-based quality gating is out of scope for this unit — reserved for RF02") while carrying the field through unused. Does this unit now add confidence-aware handling to "Foto — Reconhecido," or continue ignoring it? → A: Continue ignoring it. Any non-empty OCR text — `high` or `low` confidence alike — reaches "Foto — Reconhecido" identically, with no visual distinction, warning, or separate review path keyed to confidence. The prototype's "Foto — Reconhecido" row (§2.3) defines no confidence-related element, so adding one here would invent a UI state the prototype never specifies; this also keeps the field's treatment consistent with RF01's own precedent. (Resolved by technical judgment per user direction, applying Constitution Principle I, where the input docs are silent on this exact boundary.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reviewing and saving a transcribed audio entry (Priority: P1)

A user finishes recording in the "Áudio" tab (built in RF01). Instead of the entry saving itself right away, the app shows it is transcribing, then presents the transcribed text for the user to read — and optionally correct — before they explicitly tap "Salvar" to create the entry.

**Why this priority**: This is RF02's core deliverable for audio — the dedicated processing/review states the prototype defines, replacing RF01's placeholder "automatic save behind a generic spinner" behavior for this modality.

**Independent Test**: Can be fully tested by recording a short note using the audio fixture (`docs/input/backend/fixtures/media/audio_fixture_01.wav`, reference text in `expected-transcription.md`), stopping, observing the "Processando" state, confirming the "Transcrito" state shows that text editable with "Salvar" enabled, optionally editing it, tapping "Salvar," and confirming one new entry exists with origin "audio" and exactly the (possibly edited) reviewed text as content.

**Acceptance Scenarios**:

1. **Given** the user has just stopped an audio recording, **When** that happens, **Then** the app automatically begins on-device transcription and shows "Áudio — Processando": a spinner in place of the stop control, the waveform frozen and faded, the text "Transcrevendo...", and the recorded duration — with no entry created yet.
2. **Given** transcription completes successfully, **When** that happens, **Then** the app shows "Áudio — Transcrito": the transcribed text in an editable field, the original audio duration shown, and "Salvar" enabled — still with no entry created.
3. **Given** the "Áudio — Transcrito" state with the transcribed text unedited, **When** the user taps "Salvar", **Then** exactly one entry is created with origin "audio" and that exact text as content.
4. **Given** the "Áudio — Transcrito" state, **When** the user edits the text before tapping "Salvar", **Then** the entry created on "Salvar" carries the edited text, not the original transcription.
5. **Given** transcription is on-device, **When** any part of this flow runs, **Then** the recorded audio is never sent to the backend — only the final (possibly edited) text leaves the device, inside the `POST /entries` call.

---

### User Story 2 - Recovering from a failed transcription (Priority: P1)

A recording is too noisy, too quiet, or otherwise fails to transcribe. The user is told clearly and can retry without re-recording, since the audio is still held.

**Why this priority**: Mirrors Story 1's happy path with the failure branch the prototype explicitly requires ("Áudio — Erro"); pairs with it as the complete audio pipeline.

**Independent Test**: Can be fully tested by forcing an on-device transcription failure (e.g., a silent or corrupted audio capture) after stopping a recording, confirming "Áudio — Erro" appears with "Tentar novamente" and no entry is created, then tapping "Tentar novamente" and confirming the same held audio is retried (no new recording required).

**Acceptance Scenarios**:

1. **Given** on-device transcription fails or returns no usable text, **When** that happens, **Then** the app shows "Áudio — Erro": a red warning icon, "Não foi possível transcrever", and an outline button "Tentar novamente" — and no entry is created.
2. **Given** "Áudio — Erro" is showing, **When** the user taps "Tentar novamente", **Then** the system re-attempts transcription of the same already-held audio, without requiring a new recording, moving back to "Áudio — Processando".
3. **Given** "Áudio — Erro" is showing, **When** the user closes the modal, switches tabs, or navigates away instead of retrying, **Then** no entry is created and the held audio and error state are discarded.

---

### User Story 3 - Reviewing and saving a recognized photo entry (Priority: P2)

A user supplies an image in the "Foto" tab (built in RF01). The app sends it to the backend for OCR, shows that it is recognizing text, then presents the recognized text next to a thumbnail for the user to read — and optionally correct — before they explicitly tap "Salvar."

**Why this priority**: The photo counterpart of Story 1; ordered after the audio pair because it shares the same reviewed-recognition pattern, just backed by the backend OCR call instead of on-device transcription.

**Independent Test**: Can be fully tested by supplying the legible-text fixture (`docs/input/backend/fixtures/media/ocr_fixture_01.png`), observing "Foto — Processando OCR", confirming "Foto — Reconhecido" shows the extracted text editable next to a thumbnail with "Salvar" enabled, optionally editing it, tapping "Salvar," and confirming one new entry exists with origin "photo" and exactly the (possibly edited) reviewed text as content.

**Acceptance Scenarios**:

1. **Given** the user has just supplied an image (camera or gallery), **When** that happens, **Then** the app automatically calls the OCR endpoint and shows "Foto — Processando OCR": the photo thumbnail, a spinner, and "Reconhecendo texto..." — with no entry created yet.
2. **Given** OCR completes successfully with usable text, **When** that happens, **Then** the app shows "Foto — Reconhecido": the thumbnail next to the extracted text in an editable field, and "Salvar" enabled — still with no entry created.
3. **Given** the "Foto — Reconhecido" state, **When** the user taps "Salvar" (with or without edits), **Then** exactly one entry is created with origin "photo" and the current (possibly edited) text as content.
4. **Given** OCR is backend-driven, **When** any part of this flow runs, **Then** the image itself is never persisted by the backend — only its extracted text is used, consistent with the `POST /media/ocr` contract.

---

### User Story 4 - Recovering from a failed photo recognition (Priority: P2)

An image has no legible text, or the OCR call otherwise fails. The user is told clearly and has two ways forward: retry recognition on the same image, or save the entry anyway without any recognized text.

**Why this priority**: The photo failure path is explicitly richer than audio's (two recovery actions instead of one), so it is scoped as its own story even though it parallels Story 2.

**Independent Test**: Can be fully tested by supplying the illegible-text fixture (`docs/input/backend/fixtures/media/ocr_fixture_ilegivel.png`), confirming "Foto — Erro" appears with both "Tentar novamente" and "Salvar só a foto" and no entry is created yet, then separately verifying (a) "Tentar novamente" re-runs OCR on the same held image, and (b) "Salvar só a foto" creates exactly one entry with origin "photo" and non-empty placeholder content, without a further OCR attempt.

**Acceptance Scenarios**:

1. **Given** OCR fails, times out, or returns no usable text, **When** that happens, **Then** the app shows "Foto — Erro": the thumbnail kept on screen, a red warning icon, "Não foi possível reconhecer o texto", the button "Tentar novamente", and the secondary text action "Salvar só a foto" — and no entry is created yet.
2. **Given** "Foto — Erro" is showing, **When** the user taps "Tentar novamente", **Then** the system re-attempts OCR on the same already-held image, without requiring a new capture, moving back to "Foto — Processando OCR".
3. **Given** "Foto — Erro" is showing, **When** the user taps "Salvar só a foto" instead, **Then** exactly one entry is created immediately with origin "photo" and a fixed, non-empty placeholder as its content, and no further OCR call is made for that capture.
4. **Given** "Foto — Erro" is showing, **When** the user closes the modal, switches tabs, or navigates away instead of choosing either action, **Then** no entry is created and the held image and error state are discarded.

---

### User Story 5 - Abandoning mid-recognition or mid-review leaves nothing behind (Priority: P3)

A user starts the transcription/recognition flow for audio or photo and backs out before ever tapping "Salvar" — whether recognition is still running, succeeded and is sitting in the editable review, or failed.

**Why this priority**: A safety property spanning both new recognition pipelines rather than a feature of its own; depends on Stories 1–4 already existing to have intermediate states to abandon from.

**Independent Test**: Can be fully tested by triggering each of "Processando"/"Transcrevendo", "Transcrito"/"Reconhecido", and "Erro" for both audio and photo, closing the modal or navigating away from each without tapping "Salvar" or "Salvar só a foto", and confirming no entry was created in any case.

**Acceptance Scenarios**:

1. **Given** audio transcription or photo OCR is in progress ("Processando"/"Transcrevendo" or "Processando OCR"), **When** the user closes the modal or navigates away, **Then** no entry is created, regardless of how the in-flight recognition call eventually resolves.
2. **Given** the editable "Transcrito" or "Reconhecido" review state, possibly with unsaved edits, **When** the user closes the modal or navigates away without tapping "Salvar", **Then** no entry is created and the edited text is discarded.
3. **Given** the user switches tabs while any of these states is active, **When** that happens, **Then** the in-progress or completed-but-unsaved recognition is discarded, the same as closing the modal.

---

### Edge Cases

- The editable text in "Transcrito" or "Reconhecido" is edited down to an empty or whitespace-only field: "Salvar" MUST become unavailable, since the backend requires non-empty entry content — the same empty-content guard RF01 applies to the "Texto" tab, now also applied here after edits.
- The device is offline when OCR would normally be attempted: "Foto — Processando OCR" MUST resolve to "Foto — Erro" with a clear, offline-appropriate message (not a generic failure) rather than hanging; "Salvar só a foto" and "Tentar novamente" remain visible, but "Salvar" (from a would-be "Reconhecido" state) and "Salvar só a foto" both still require connectivity for the underlying `POST /entries` call, following the same offline-blocks-writes rule established in RF01.
- Retrying OCR on an image that genuinely has no legible text (e.g., the illegible fixture) is still allowed via "Tentar novamente" even though the same result is likely; the system does not pre-emptively hide "Tentar novamente" based on whether the prior failure looked retryable.
- The underlying `POST /entries` call itself fails (offline or backend error) after a successful transcription/OCR, i.e. while in "Transcrito"/"Reconhecido" and "Salvar" is tapped: the reviewed text and held audio/image are retained, an inline error is shown, and re-tapping "Salvar" retries the same save — no new recognition attempt is triggered.
- The app is backgrounded or killed while in "Processando"/"Transcrevendo", "Transcrito"/"Reconhecido", or "Erro": nothing is lost that mattered, because nothing was persisted yet. On return after a mere backgrounding, the state resumes normally (including any unsaved edits); after a process kill, the modal reopens to its default empty state and the user must recapture, the same lifecycle rule RF01 established for its own in-progress states, now extended to these additional ones.
- The user double-taps "Salvar" (from "Transcrito"/"Reconhecido") or double-taps "Salvar só a foto": only one entry is ever created per confirmed capture, never duplicates — the system ignores a repeat trigger received while a save for that capture is already in flight.
- "Tentar novamente" is tapped repeatedly in quick succession: only one recognition attempt runs at a time per capture; a repeat tap while an attempt is already in flight is ignored.
- A `low`-confidence OCR result that still contains text is treated identically to a `high`-confidence one: it reaches "Foto — Reconhecido" with no visual distinction, warning, or extra gating step — confidence-based quality handling remains out of scope for this unit, matching RF01's established treatment of the field.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When the user stops an audio recording (started in RF01's "Áudio" tab), the system MUST automatically begin on-device transcription and show "Áudio — Processando" — a spinner in place of the stop control, the waveform frozen and faded, the caption "Transcrevendo...", and the recorded duration — without creating any entry.
- **FR-002**: On successful transcription, the system MUST show "Áudio — Transcrito" with the transcribed text in an editable field, the original audio duration, and "Salvar" enabled; it MUST NOT create an entry until the user explicitly taps "Salvar", and the content saved MUST be the field's current text at the moment "Salvar" is tapped (reflecting any user edits).
- **FR-003**: If on-device transcription fails or produces no usable text, the system MUST show "Áudio — Erro" (warning icon, "Não foi possível transcrever", outline button "Tentar novamente") and create no entry; tapping "Tentar novamente" MUST re-attempt transcription of the same already-held audio without requiring a new recording.
- **FR-004**: Audio content MUST NEVER be transmitted to the backend at any point in this flow — transcription runs entirely on-device via `whisper_ggml`, and only the resulting (possibly edited) text is ever sent over the network, inside the `POST /entries` call.
- **FR-005**: When the user supplies an image via the "Foto" tab (built in RF01), the system MUST automatically call the backend OCR endpoint (`POST /media/ocr`) and show "Foto — Processando OCR" — the photo thumbnail, a spinner, and the caption "Reconhecendo texto..." — without creating any entry.
- **FR-006**: On a successful OCR response with usable text, the system MUST show "Foto — Reconhecido" with the thumbnail next to the extracted text in an editable field and "Salvar" enabled; it MUST NOT create an entry until the user explicitly taps "Salvar", and the content saved MUST be the field's current text at that moment (reflecting any user edits). This applies identically regardless of the response's `confidence` value (`high` or `low`) — this unit adds no confidence-based gating, warning, or distinct review path, continuing RF01's established treatment of that field.
- **FR-007**: If the OCR call fails (including a no-usable-text result) the system MUST show "Foto — Erro" — thumbnail kept, warning icon, "Não foi possível reconhecer o texto" — offering both "Tentar novamente" (re-attempts OCR on the same already-held image, without requiring a new capture) and "Salvar só a foto" (see FR-008), and create no entry until one of those two actions is taken.
- **FR-008**: Tapping "Salvar só a foto" MUST immediately create exactly one entry with origin "photo" and a fixed, non-empty placeholder string as its content (since the backend never persists the photo itself and requires non-empty entry content), without making any further OCR attempt for that capture.
- **FR-009**: In both "Transcrito" and "Reconhecido" states, "Salvar" MUST be unavailable whenever the editable text field is empty or whitespace-only, preventing an empty entry from being created through manual edits.
- **FR-010**: Confirming "Salvar" from "Transcrito" or "Reconhecido", or confirming "Salvar só a foto" from "Foto — Erro", MUST result in exactly one persisted entry via the entry-creation endpoint with the correct origin (`audio` or `photo`); the system MUST ignore any repeat trigger of that same action received while a save for that capture is already in flight, so at most one entry is ever created per confirmed capture.
- **FR-011**: If a capture is abandoned at any point while in "Processando"/"Transcrevendo", "Transcrito"/"Reconhecido", or "Erro" — the modal is closed, the user navigates away, or the user switches tabs — the system MUST NOT create any entry, and MUST discard any in-progress recognition, recognized/transcribed text, and edits held for that capture.
- **FR-012**: This unit MUST NOT change the "Texto" tab's behavior (no recognition applies to typed text) and MUST NOT implement any functional behavior belonging to later-delivered requirements (the full behavior of RF04, RF05, RF06, RF07, RF08, RF09, RF10) or any extension feature (manual tags/categories, action plans, persona selection).
- **FR-013**: This unit MUST NOT modify the backend, its API contract, or its configuration in any way.

### Key Entities

- **Recognition Attempt**: Ephemeral, device-only state tracking one in-progress or completed transcription (audio) or OCR (photo) call for the capture currently open in the Insertion Modal — its status (processing, succeeded with text, failed), the resulting editable text (including user edits made before "Salvar"), and a reference to the still-locally-held audio/image it was run against. For photo, the OCR response's `confidence` value is carried through this state but never branched on (per the resolved Clarification above). It never itself becomes a persisted entry and is entirely discarded when the capture is abandoned or once "Salvar" successfully creates the entry.
- **Journal Entry** (extended from RF01): A persisted record with text content, an origin (`audio` or `photo` for this unit), and a creation time. For audio/photo, that content is now either the user-reviewed (and possibly edited) transcribed/recognized text, or — only via "Salvar só a foto" — a fixed placeholder string when no text was recognized. Structurally identical to entries from any other origin, and immutable once created.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of audio captures whose on-device transcription succeeds reach the editable "Áudio — Transcrito" review state before any entry is created — none saves itself automatically.
- **SC-002**: 100% of photo captures whose OCR succeeds reach the editable "Foto — Reconhecido" review state before any entry is created — none saves itself automatically.
- **SC-003**: 100% of transcription or OCR failures leave the originally captured audio or image available for at least one retry attempt, without requiring the user to re-record or recapture.
- **SC-004**: 100% of OCR failures additionally offer a working path ("Salvar só a foto") to create an entry without recognized text, independent of whether a further OCR retry would succeed.
- **SC-005**: 0% of entries created through this unit's flows have empty or whitespace-only content, regardless of how the user edits the reviewed text beforehand.
- **SC-006**: 0% of captures abandoned during "Processando"/"Transcrevendo", "Transcrito"/"Reconhecido", or "Erro" (for either modality) leave behind a persisted entry.

## Assumptions

- Per the resolved Clarification above, this unit supersedes RF01's FR-007 placeholder recognition UX for the "Áudio" and "Foto" tabs with the dedicated prototype states; the "Texto" tab is unaffected.
- The fixed placeholder content used by "Salvar só a foto" is a short, non-empty, Portuguese string signaling that the entry is a photo capture with no text recognized (exact wording left to implementation, since the prototype specifies only the triggering UI action, not the stored content, and the input documents are otherwise silent on it).
- "Tentar novamente" re-runs recognition against the same in-memory audio/image held since the original capture in RF01's modal — it never asks the user to re-record or reselect the source.
- Because entries are immutable (no `PATCH`/`DELETE /entries/:id`), the editable "Transcrito"/"Reconhecido" review is the only opportunity to correct a transcription/recognition mistake — there is no later in-app editing of a saved entry's content.
- The on-device transcription failure path (FR-003) is exercised in testing by forcing a transcription error (e.g., a corrupted or silent audio buffer), since the fixtures directory provides a reference success case (`audio_fixture_01.wav`) but no dedicated "untranscribable audio" fixture; OCR's failure path is exercised directly with the provided `ocr_fixture_ilegivel.png` fixture.
- "Salvar só a foto" and the OCR retry both still require network connectivity for their own calls (`POST /entries` and `POST /media/ocr` respectively), consistent with this product's cloud-only, no-offline-writes architecture already established in RF01 and RF06.
- Double-tap and repeat-trigger idempotency guards (FR-009, FR-010, and the "Tentar novamente" repeat-tap edge case) follow the same in-flight-action-is-ignored pattern RF01 already established for its own Save action.
- If the save call itself fails after a successful transcription/OCR (e.g., the device goes offline or `POST /entries` errors between landing on "Transcrito"/"Reconhecido" and tapping "Salvar"), the reviewed text and held audio/image are kept, an inline error is shown in place of (not instead of) the editable review state, and "Salvar" remains available to retry the same save — this is a save-call failure, distinct from the recognition failure "Erro" states above, and is resolved by technical judgment per Constitution Principle I since the prototype and input docs are silent on it.
