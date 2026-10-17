---

description: "Task list for P-RF02 — Speech-to-text / OCR processing"
---

# Tasks: P-RF02 — Speech-to-text / OCR processing

**Input**: Design documents from `/specs/004-stt-ocr-processing/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. RNF07 (`lib/**/domain/**` ≥80% coverage) is carried into this unit's Constitution
Check as "PASS (gate carried into tasks)", and quickstart.md's "Automated checks" section names the
domain/bloc tests this unit's coverage depends on — so test tasks are generated alongside
implementation, matching RF01/RF03's existing `bloc_test`/`mocktail` style exactly.

**Organization**: Tasks are grouped by user story (US1–US5, spec.md priorities P1/P1/P2/P2/P3). Per
contracts/insertion-modal-bloc.md, all five stories edit the one existing `InsertionModalBloc`/
`InsertionModalPage` RF01 already built (research.md's "independent" here means each story's
acceptance scenarios can be exercised and automated-tested on their own once Foundational is done,
not that each story gets its own screen or bloc — same convention RF01's own tasks.md used). Unlike
RF01 (building fresh), this unit edits a working app: the Áudio (US1/US2) and Foto (US3/US4) handler
rewrites are sequenced so the app keeps compiling and the *other* modality keeps its RF01 behavior
until its own story phase lands — `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` and
`CaptureFailureBand` are deleted only once nothing references them any more (end of US3/US4), not
up front.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on an incomplete task)
- **[Story]**: US1 (audio review/save), US2 (audio recognition failure/retry), US3 (photo
  review/save), US4 (photo recognition failure/retry), US5 (abandoning mid-recognition or
  mid-review leaves nothing behind)

## Path Conventions

Single Flutter project (RF01/RF03's existing `lib/`, `test/`) — see plan.md Project Structure. Every
file this unit touches already exists inside `lib/features/capture/` or `lib/core/`; no new feature
folder, no new top-level directory (plan.md Scale/Scope).

---

## Phase 1: Setup

**Purpose**: Project initialization — N/A for this unit.

No setup tasks apply. This unit adds no new package, no native-project change, and no new `.env`
variable — it reuses RF01's full stack as-is (plan.md Technical Context, Primary Dependencies: "No
additions"). Proceed directly to Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The one new shared usecase every "Salvar"/"Salvar só a foto" trigger across both
modalities funnels through (`ConfirmEntrySaveUseCase`), the two new design tokens the prototype's
"Erro" states and photo thumbnail need, and the new `RecognitionErrorView` widget both modalities'
Erro states will render through. `RecognizePhotoUseCase` is **not** here — it is built in US3,
since only the Foto pipeline needs it (see US3's rationale).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T001 [P] Add `sizePhotoThumbnail = 64` and `sizeStatusIcon = 32` to the Sizes section of `lib/core/design_tokens.dart` (research.md R2 — the "small thumbnail" and the recurring red warning icon prototype-extract.md §2.3 names for the Áudio/Foto "Erro" states and Foto's "Reconhecido"/"Erro" thumbnail; `colorError`, already present, is reused unchanged for the icon/copy color)
- [X] T002 [P] Create `ConfirmEntrySaveUseCase` and sealed `ConfirmEntrySaveFailure`/`ConfirmEntrySaveOffline`/`ConfirmEntrySaveCreationFailed` in `lib/features/capture/domain/usecases/confirm_entry_save_usecase.dart` (data-model.md, contracts/recognition-and-save-usecases.md): `call(String content, EntrySource source)` checks `ConnectivityChecker.hasConnection()` first — `false` short-circuits to `Left(ConfirmEntrySaveOffline())` without calling `CreateEntryUseCase` at all (FR-010 / Edge Cases' "both still require connectivity"); otherwise delegates to `CreateEntryUseCase(content, source)` and wraps its `Left`/`Right`. Does not re-validate `content` non-emptiness — that is the bloc's job before calling this (FR-009), the same contract `CreateEntryUseCase` itself already has
- [X] T003 [P] Write `ConfirmEntrySaveUseCase` tests in `test/features/capture/domain/usecases/confirm_entry_save_usecase_test.dart` against a fake `CreateEntryUseCase` + fake `ConnectivityChecker` (contracts/recognition-and-save-usecases.md's RNF07 table): offline → `Left(ConfirmEntrySaveOffline())` with `CreateEntryUseCase` never invoked; `CreateEntryUseCase` `Right(entry)` passes through unchanged; `CreateEntryUseCase` `Left(failure)` maps to `Left(ConfirmEntrySaveCreationFailed(failure))` — depends on T002
- [X] T004 Register `ConfirmEntrySaveUseCase` (as `registerLazySingleton`, injecting `CreateEntryUseCase`/`ConnectivityChecker`) in `lib/core/di/service_locator.dart` — leave the existing `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` registrations and `InsertionModalBloc`'s current constructor call untouched for now; both old usecases are still the only thing powering the Foto tab until US3 rewrites it, and Audio until US1 rewrites it — depends on T002
- [X] T005 [P] Create a `RecognitionErrorView` widget in `lib/features/capture/presentation/widgets/capture_status_views.dart` rendering prototype-extract.md §2.3's "Erro" shape: a `DesignTokens.sizeStatusIcon`-sized warning icon in `DesignTokens.colorError`, a `message` string, an outline "Tentar novamente" button (`onRetry` callback), and an optional secondary text-action slot (`secondaryAction` — a `(label, onTap)` pair, used only by Foto's "Salvar só a foto" in US4, left `null` for Audio). Add it **alongside** the existing `CaptureFailureBand` — do not remove `CaptureFailureBand` yet, since `AudioTabView`/`FotoTabView` still reference it until US2/US4 migrate their own "Erro" sub-views (research.md R4) — depends on T001

**Checkpoint**: `ConfirmEntrySaveUseCase`, the two new design tokens, and `RecognitionErrorView` all
exist and are wired through DI/available to import. The Áudio and Foto tabs still behave exactly as
RF01 built them (single generic "Saving" spinner, plain `CaptureFailureBand` on failure) until their
own story phases rewrite the handlers below.

---

## Phase 3: User Story 1 - Reviewing and saving a transcribed audio entry (Priority: P1) 🎯 MVP

**Goal**: Stopping a recording no longer saves itself — it shows "Áudio — Processando", then lands
on an editable "Áudio — Transcrito" review with its own explicit "Salvar"; the entry created on
"Salvar" carries exactly the (possibly edited) reviewed text.

**Independent Test**: Record a short note, stop, observe "Áudio — Processando", confirm "Áudio —
Transcrito" shows the transcribed text editable with "Salvar" enabled, optionally edit it, tap
"Salvar", and confirm one new entry exists with origin "audio" and exactly the (possibly edited)
reviewed text as content.

### Implementation for User Story 1

- [X] T006 [P] [US1] Add `InsertionModalAudioProcessing(duration)` and `InsertionModalAudioTranscribed(text, duration)` states to `lib/features/capture/presentation/bloc/insertion_modal_state.dart`; change the existing `InsertionModalAudioSaving` to carry `(text, duration)` and `InsertionModalAudioFailure` to carry `(duration, message)` instead of their current RF01 shapes (data-model.md's full `InsertionModalState` shape) — depends on Foundational
- [X] T007 [P] [US1] Add `AudioReviewTextChanged(text)` and `AudioSaveConfirmed` events to `lib/features/capture/presentation/bloc/insertion_modal_event.dart` (data-model.md) — depends on Foundational
- [X] T008 [US1] Rewrite `InsertionModalBloc._onAudioStopRequested` in `lib/features/capture/presentation/bloc/insertion_modal_bloc.dart`: remove the pre-transcription connectivity gate entirely (FR-001, research.md R1 — transcription is on-device and must begin unconditionally on stop); store the stopped path in `_pendingAudioPath`, capture the final `elapsed` as `duration`, emit `InsertionModalAudioProcessing(duration)`, then await `AudioTranscriptionRepository.transcribe(path)` directly — no usecase wrapper, since the only orchestration step (the connectivity check) no longer applies here (research.md R1/contracts/recognition-and-save-usecases.md). Before applying the result, check `state is InsertionModalAudioProcessing && _pendingAudioPath == path`; if that no longer holds, discard the result outright (research.md R6/FR-011 — User Story 5 depends on this guard existing). Otherwise map `Left(EmptyRecognitionResult())`/`Left(TranscriptionError())` to `InsertionModalAudioFailure(duration, message)` (reusing the existing `_noSpeechMessage`/`_genericAudioMessage` constants), and `Right(text)` to `_audioReviewText = text; emit(InsertionModalAudioTranscribed(text, duration))` — no entry created (FR-002) — depends on T006, T007
- [X] T009 [US1] Add an `_onAudioReviewTextChanged` handler to `InsertionModalBloc`: from `InsertionModalAudioTranscribed` or `InsertionModalAudioSaveFailure` only, sets `_audioReviewText = event.text` and re-emits the same state subtype with the updated text, holding `duration`/other fields unchanged — depends on T006, T007
- [X] T010 [US1] Add an `_onAudioSaveConfirmed` handler to `InsertionModalBloc`: ignored unless `state is InsertionModalAudioTranscribed || state is InsertionModalAudioSaveFailure`, `_audioReviewText` is non-empty/non-whitespace after `.trim()` (FR-009 — the "Salvar MUST be unavailable whenever the editable text field is empty or whitespace-only" guard), and no save is already in flight for this capture (FR-010 double-tap guard); emits `InsertionModalAudioSaving(_audioReviewText, duration)`, awaits `ConfirmEntrySaveUseCase(_audioReviewText, EntrySource.audio)`; `Right(entry)` clears `_pendingAudioPath` and triggers the existing one-shot `closeRequests` side effect; `Left(ConfirmEntrySaveOffline())`/`Left(ConfirmEntrySaveCreationFailed(f))` map to `InsertionModalAudioSaveFailure(_audioReviewText, duration, message)`, keeping the audio file and reviewed text both held so a repeat `AudioSaveConfirmed` is the retry (research.md R5) — depends on T006, T007, T002
- [X] T011 [US1] Update `InsertionModalBloc`'s constructor: remove the `SaveAudioEntryUseCase` dependency, add `AudioTranscriptionRepository` and `ConfirmEntrySaveUseCase`; register the `AudioReviewTextChanged`/`AudioSaveConfirmed` handlers via `on<...>()` — leave `SavePhotoEntryUseCase` untouched (Foto is migrated in US3) — depends on T008, T009, T010
- [X] T012 [US1] Add `InsertionModalAudioProcessing`, `InsertionModalAudioTranscribed`, and the new-shaped `InsertionModalAudioSaveFailure` cases (mapping to `CaptureTab.audio`) to `InsertionModalPage._tabOf`'s exhaustive switch in `lib/features/capture/presentation/pages/insertion_modal_page.dart`, and to the page's own `BlocBuilder` tab-content switch — depends on T006
- [X] T013 [US1] Extend `AudioTabView` in `lib/features/capture/presentation/widgets/audio_tab_view.dart` with three new sub-views: "Áudio — Processando" (a spinner — `CaptureLoadingIndicator` or equivalent — in place of the stop control, `Opacity(0.35)` around the existing `AudioWaveform`, the caption "Transcrevendo...", and the recorded `duration` in `DesignTokens.textMonoCaption` — FR-001); "Áudio — Transcrito" (an editable `TextFormField` seeded from `text`, dispatching `AudioReviewTextChanged` on change, the same `duration` caption, and a "Salvar" `ElevatedButton` enabled iff `text.trim().isNotEmpty`, dispatching `AudioSaveConfirmed` — FR-002/FR-009); "Áudio — SaveFailure" (the same editable field plus an inline message in `DesignTokens.colorError`, "Salvar" still enabled for the retry — research.md R5) — depends on T006, T007, T010
- [X] T014 [US1] Update `lib/core/di/service_locator.dart`'s `InsertionModalBloc` factory registration to inject `AudioTranscriptionRepository` and `ConfirmEntrySaveUseCase` in place of `SaveAudioEntryUseCase` (keep `SavePhotoEntryUseCase` injected for now) — depends on T011, T004
- [X] T015 [P] [US1] Write `InsertionModalBloc` tests in `test/features/capture/presentation/bloc/insertion_modal_bloc_test.dart` for the Audio review flow: `AudioStopRequested` reaches `InsertionModalAudioProcessing(duration)` then `InsertionModalAudioTranscribed(text, duration)` on a successful `transcribe()`, with no `entries-create` call made at any point in between (SC-001); `AudioReviewTextChanged` updates the held draft and re-emits the same state subtype; `AudioSaveConfirmed` with edited text creates the entry with that *edited* text (not the original transcription) and `source: audio`, then triggers the close side-effect; a repeat `AudioSaveConfirmed` while already `InsertionModalAudioSaving` is ignored (Edge Cases: "double-taps... only one entry is ever created"); a `transcribe()` result that resolves after the bloc has moved away from the matching `InsertionModalAudioProcessing` state is discarded, producing no state change and no entry (research.md R6); `ConfirmEntrySaveUseCase` returning `Left(ConfirmEntrySaveOffline())`/`Left(ConfirmEntrySaveCreationFailed(f))` from `InsertionModalAudioTranscribed` maps to `InsertionModalAudioSaveFailure(text, duration, message)` with the held text/duration both preserved and no entry created; a subsequent `AudioSaveConfirmed` from that `SaveFailure` state retries `ConfirmEntrySaveUseCase` and, on `Right(entry)`, creates exactly one entry and triggers the close side-effect; dispatching `AudioSaveConfirmed` while the reviewed text is whitespace-only (bypassing the UI's disabled "Salvar") is ignored — no entry created, no state change (FR-009/SC-005) — depends on T008, T009, T010

**Checkpoint**: User Story 1 is independently functional — Audio now shows the dedicated
Processando/Transcrito review flow end to end, and a new audio entry's content is exactly the
reviewed (possibly edited) text. The Foto tab is untouched and still behaves exactly as RF01 built
it.

---

## Phase 4: User Story 2 - Recovering from a failed transcription (Priority: P1)

**Goal**: A transcription failure shows "Áudio — Erro" with "Tentar novamente", re-attempting
transcription against the same already-held audio without a new recording; abandoning it instead
discards the audio and creates no entry.

**Independent Test**: Force a transcription failure (silent/corrupted recording), stop, confirm
"Áudio — Erro" appears with "Tentar novamente" and no entry is created, then tap "Tentar novamente"
and confirm the same held audio is retried.

### Implementation for User Story 2

- [X] T016 [US2] Implement the Audio branch of `_onRetryRequested` in `InsertionModalBloc`: ignored unless `state is InsertionModalAudioFailure && _pendingAudioPath != null`; re-enters T008's transcription branch (emitting `InsertionModalAudioProcessing(duration)` first) against the same held path — no new recording required (FR-003) — depends on T008 (US1)
- [X] T017 [US2] Extend `_onTabSelected`/`_onModalClosed` in `InsertionModalBloc` so that leaving `InsertionModalAudioFailure` (via tab switch or modal close) clears `_pendingAudioPath`/`_audioReviewText` before the target state is emitted (FR-011, Edge Cases: "closes the modal... instead of retrying... no entry is created and the held audio and error state are discarded") — depends on T016
- [X] T018 [US2] Extend `AudioTabView`'s `InsertionModalAudioFailure` case to render the new "Áudio — Erro" sub-view via `RecognitionErrorView` (warning icon, "Não foi possível transcrever", "Tentar novamente" dispatching `RetryRequested`, no secondary action) in place of the old generic `CaptureFailureBand` (research.md R4, FR-003) — depends on T005 (Foundational), T016
- [X] T019 [P] [US2] Extend `InsertionModalBloc` tests for the Audio failure/retry flow: `Left(EmptyRecognitionResult())` and `Left(TranscriptionError())` each map to `InsertionModalAudioFailure(duration, message)` with the correct message and no entry created; `RetryRequested` re-transcribes the same `_pendingAudioPath` without a new `AudioCaptureRepository.stop()` call (SC-003); closing the modal or switching tabs from `InsertionModalAudioFailure` discards the held audio — reopening shows the idle "Toque para gravar" state, not a resumed Erro (SC-006) — depends on T016, T017, T018

**Checkpoint**: User Stories 1 and 2 both work independently — the full Audio pipeline (review,
save, failure, retry, abandon) now matches the prototype end to end.

---

## Phase 5: User Story 3 - Reviewing and saving a recognized photo entry (Priority: P2)

**Goal**: Supplying an image no longer saves itself — it shows "Foto — Processando OCR", then lands
on an editable "Foto — Reconhecido" review (thumbnail + text) with its own explicit "Salvar"; the
entry created on "Salvar" carries exactly the (possibly edited) reviewed text.

**Independent Test**: Supply the legible-text fixture, observe "Foto — Processando OCR", confirm
"Foto — Reconhecido" shows the extracted text editable next to a thumbnail with "Salvar" enabled,
optionally edit it, tap "Salvar", and confirm one new entry exists with origin "photo" and exactly
the (possibly edited) reviewed text as content.

### Implementation for User Story 3

- [X] T020 [P] [US3] Create `RecognizePhotoUseCase` and sealed `PhotoRecognitionAttemptFailure`/`PhotoRecognitionOffline`/`PhotoRecognitionCallFailed` in `lib/features/capture/domain/usecases/recognize_photo_usecase.dart` (data-model.md, contracts/recognition-and-save-usecases.md): `call(String imageFilePath)` checks `ConnectivityChecker.hasConnection()` first — `false` short-circuits to `Left(PhotoRecognitionOffline())` without calling `PhotoRecognitionRepository.recognize()` at all (same "don't attempt a call that cannot succeed" principle as RF01's own pre-save gate, now scoped to just this call); otherwise delegates to `recognize(imageFilePath)` and wraps its `Left`/`Right` in `PhotoRecognitionCallFailed`/`Right`. Does not call `CreateEntryUseCase` or touch `EntriesRepository` in any way — depends on Foundational
- [X] T021 [P] [US3] Write `RecognizePhotoUseCase` tests in `test/features/capture/domain/usecases/recognize_photo_usecase_test.dart` against a mock `PhotoRecognitionRepository` + fake `ConnectivityChecker` (contracts/recognition-and-save-usecases.md's RNF07 table): offline short-circuit with no repository call; repository `Right(ocrResult)` passes through; repository `Left(OcrNoTextFailure)` and `Left(<other Failure>)` both wrap into `PhotoRecognitionCallFailed` — depends on T020
- [X] T022 [P] [US3] Add `InsertionModalFotoProcessing(imagePath)` and `InsertionModalFotoReconhecido(imagePath, text)` states to `insertion_modal_state.dart`; change the existing `InsertionModalFotoSaving` to carry `(imagePath, text)` and `InsertionModalFotoFailure` to carry `(imagePath, message)` instead of their current RF01 shapes (data-model.md) — depends on Foundational
- [X] T023 [P] [US3] Add `PhotoReviewTextChanged(text)` and `PhotoSaveConfirmed` events to `insertion_modal_event.dart` (data-model.md) — depends on Foundational
- [X] T024 [US3] Rewrite `InsertionModalBloc._onPhotoSourceSelected`: on a picked (non-null) path, store it in `_pendingImagePath`, emit `InsertionModalFotoProcessing(path)` (FR-005), then await `RecognizePhotoUseCase(path)`. Before applying the result, check `state is InsertionModalFotoProcessing && _pendingImagePath == path`; discard a stale result outright otherwise (research.md R6/FR-011). Otherwise map `Left(PhotoRecognitionOffline())` to the existing `_offlineMessage`, `Left(PhotoRecognitionCallFailed(f))` to `f is OcrNoTextFailure ? _noTextMessage : f.message` (same branch RF01's `_photoFailureMessage` already used), both as `InsertionModalFotoFailure(path, message)`; and `Right(ocrResult)` — confidence read but never branched on, per spec.md's resolved Clarification 3 — to `_photoReviewText = ocrResult.text; emit(InsertionModalFotoReconhecido(path, ocrResult.text))` — no entry created (FR-006) — depends on T020, T022, T023
- [X] T025 [US3] Add an `_onPhotoReviewTextChanged` handler (same shape as T009's audio equivalent) for `InsertionModalFotoReconhecido`/`InsertionModalFotoSaveFailure` — depends on T022, T023
- [X] T026 [US3] Add an `_onPhotoSaveConfirmed` handler: ignored unless `state is InsertionModalFotoReconhecido || state is InsertionModalFotoSaveFailure`, `_photoReviewText` non-empty/non-whitespace (FR-009), no save already in flight (FR-010); emits `InsertionModalFotoSaving(path, _photoReviewText)`, awaits `ConfirmEntrySaveUseCase(_photoReviewText, EntrySource.photo)`; `Right(entry)` clears `_pendingImagePath` and triggers `closeRequests`; `Left(...)` maps to `InsertionModalFotoSaveFailure(path, _photoReviewText, message)` (research.md R5) — depends on T022, T023, T002 (Foundational)
- [X] T027 [US3] Update `InsertionModalBloc`'s constructor: remove the `SavePhotoEntryUseCase` dependency, add `RecognizePhotoUseCase` (reusing the `ConfirmEntrySaveUseCase` already added in T011); register the `PhotoReviewTextChanged`/`PhotoSaveConfirmed` handlers — depends on T024, T025, T026, T011
- [X] T028 [US3] Add `InsertionModalFotoProcessing`, `InsertionModalFotoReconhecido`, and the new-shaped `InsertionModalFotoSaveFailure` cases to `InsertionModalPage._tabOf`'s switch and the page's tab-content switch — depends on T022
- [X] T029 [US3] Extend `FotoTabView` in `lib/features/capture/presentation/widgets/foto_tab_view.dart` with three new sub-views: "Foto — Processando OCR" (an `Image.file(File(imagePath))` thumbnail sized `DesignTokens.sizePhotoThumbnail`, a spinner, and "Reconhecendo texto..." — FR-005); "Foto — Reconhecido" (the thumbnail next to an editable `TextFormField` seeded from `text`, dispatching `PhotoReviewTextChanged`, and "Salvar" enabled iff `text.trim().isNotEmpty`, dispatching `PhotoSaveConfirmed` — FR-006/FR-009); "Foto — SaveFailure" (the thumbnail, the same editable field, an inline `colorError` message, "Salvar" still enabled — research.md R5) — depends on T022, T023, T026
- [X] T030 [US3] Update `lib/core/di/service_locator.dart`: register `RecognizePhotoUseCase`; update the `InsertionModalBloc` factory registration to inject it in place of `SavePhotoEntryUseCase`; then delete `lib/features/capture/domain/usecases/save_audio_entry_usecase.dart`, `save_photo_entry_usecase.dart`, and their test files `test/features/capture/domain/usecases/save_audio_entry_usecase_test.dart`/`save_photo_entry_usecase_test.dart` — both fully superseded now that Audio (US1/US2) and Foto (this story) are both migrated off them (contracts/recognition-and-save-usecases.md "Deleted" section, research.md R7) — depends on T027, T014
- [X] T031 [P] [US3] Write `InsertionModalBloc` tests for the Foto review flow: `PhotoSourceSelected` reaches `InsertionModalFotoProcessing(path)` then `InsertionModalFotoReconhecido(path, text)` on a successful `recognize()`, with no `entries-create` call made in between (SC-002); `PhotoReviewTextChanged` updates the held draft; `PhotoSaveConfirmed` with the current (possibly edited) text creates the entry with `source: photo`, then triggers the close side-effect; a repeat `PhotoSaveConfirmed` while already `InsertionModalFotoSaving` is ignored; a `recognize()` result that resolves after the bloc has moved away from the matching `InsertionModalFotoProcessing` state is discarded (research.md R6); `ConfirmEntrySaveUseCase` returning `Left(...)` from `InsertionModalFotoReconhecido` maps to `InsertionModalFotoSaveFailure(path, text, message)` with the held path/text preserved and no entry created; a subsequent `PhotoSaveConfirmed` from that `SaveFailure` state retries and creates exactly one entry on success; dispatching `PhotoSaveConfirmed` while the reviewed text is whitespace-only is ignored — no entry created, no state change (FR-009/SC-005) — depends on T024, T025, T026

**Checkpoint**: User Stories 1, 2, AND 3 all work independently — Foto now also shows its dedicated
Processando OCR/Reconhecido review flow, and both RF01-era per-modality save usecases are gone.

---

## Phase 6: User Story 4 - Recovering from a failed photo recognition (Priority: P2)

**Goal**: An OCR failure shows "Foto — Erro" with both "Tentar novamente" (re-runs OCR on the same
held image) and "Salvar só a foto" (saves immediately with a fixed placeholder, no further OCR
attempt); abandoning it instead discards the image and creates no entry.

**Independent Test**: Supply the illegible-text fixture, confirm "Foto — Erro" appears with both
actions and no entry is created yet, then separately verify (a) "Tentar novamente" re-runs OCR on
the same held image, and (b) "Salvar só a foto" creates exactly one entry with origin "photo" and
non-empty placeholder content, without a further OCR attempt.

### Implementation for User Story 4

- [X] T032 [US4] Add `PhotoSaveWithoutTextRequested` event to `insertion_modal_event.dart` (data-model.md) — depends on T023 (US3)
- [X] T033 [US4] Define the fixed placeholder `const _photoNoTextPlaceholder = 'Foto registrada sem texto reconhecido.'` in `insertion_modal_bloc.dart` (research.md R3 — a single `const` at the usecase call site, not duplicated anywhere else), and implement the Foto branch of `_onRetryRequested`: ignored unless `state is InsertionModalFotoFailure && _pendingImagePath != null`; re-enters T024's recognition branch (emitting `InsertionModalFotoProcessing(path)` first) against the same held path — no new picker call (FR-007) — depends on T024 (US3)
- [X] T034 [US4] Implement `_onPhotoSaveWithoutTextRequested`: ignored unless `state is InsertionModalFotoFailure`; emits `InsertionModalFotoSaving(path, _photoNoTextPlaceholder)` directly — no further OCR call for that capture (FR-008) — then awaits `ConfirmEntrySaveUseCase(_photoNoTextPlaceholder, EntrySource.photo)` with the same success/`InsertionModalFotoSaveFailure` mapping as `_onPhotoSaveConfirmed` — depends on T033, T002 (Foundational)
- [X] T035 [US4] Register the `PhotoSaveWithoutTextRequested` handler (`on<PhotoSaveWithoutTextRequested>(_onPhotoSaveWithoutTextRequested)`) in `InsertionModalBloc`'s constructor — depends on T034
- [X] T036 [US4] Extend `FotoTabView`'s `InsertionModalFotoFailure` case to render the new "Foto — Erro" sub-view via `RecognitionErrorView`: thumbnail kept on screen, warning icon, "Não foi possível reconhecer o texto", "Tentar novamente" (`RetryRequested`), and the secondary text action "Salvar só a foto" (`PhotoSaveWithoutTextRequested`) — in place of the old generic `CaptureFailureBand` (research.md R4, FR-007) — depends on T005 (Foundational), T033, T034
- [X] T037 [US4] Delete the now-fully-superseded `CaptureFailureBand` widget from `lib/features/capture/presentation/widgets/capture_status_views.dart` — both Audio's (T018) and Foto's (T036) "Erro" states now render through `RecognitionErrorView` instead, so nothing else in the codebase references it (research.md R4: "deleted outright, not deprecated") — depends on T018 (US2), T036
- [X] T038 [US4] Extend `_onTabSelected`/`_onModalClosed` so leaving `InsertionModalFotoFailure` clears `_pendingImagePath`/`_photoReviewText` before the target state is emitted (FR-011, Edge Cases: "closes the modal... instead of choosing either action... no entry is created and the held image and error state are discarded") — depends on T033
- [X] T039 [P] [US4] Extend `InsertionModalBloc` tests for the Foto failure/retry flow: `Left(PhotoRecognitionOffline())`, `Left(PhotoRecognitionCallFailed(OcrNoTextFailure))`, and `Left(PhotoRecognitionCallFailed(<other Failure>))` each map to `InsertionModalFotoFailure(path, message)` with the correct message and no entry created; `RetryRequested` re-runs OCR on the same `_pendingImagePath` without a new `pickImage()` call (SC-003); `PhotoSaveWithoutTextRequested` creates exactly one entry with `source: photo` and the fixed placeholder content, with **no** further `recognize()` call for that capture (SC-004); closing the modal or switching tabs from `InsertionModalFotoFailure` discards the held image (no entry, SC-006) — depends on T033, T034, T038

**Checkpoint**: All four P1/P2 stories work independently — the full Foto pipeline (review, save,
failure, retry, "Salvar só a foto", abandon) now matches the prototype end to end.

---

## Phase 7: User Story 5 - Abandoning mid-recognition or mid-review leaves nothing behind (Priority: P3)

**Goal**: A safety property spanning both modalities — closing the modal, navigating away, or
switching tabs at any point before "Salvar"/"Salvar só a foto" is tapped (whether recognition is
still running, succeeded and sitting in review, or failed) never leaves a persisted entry behind.

**Independent Test**: Trigger each of "Processando"/"Transcrevendo", "Transcrito"/"Reconhecido", and
"Erro" for both Áudio and Foto, close the modal or navigate away from each without saving, and
confirm no entry was created in any case.

### Implementation for User Story 5

- [X] T040 [US5] Consolidate `InsertionModalBloc._onTabSelected`'s per-state guards (T017's audio-only and T038's foto-only versions) into the full set data-model.md's transition table requires: leaving any Áudio sub-state beyond `Idle`/`Recording` (`Processing`, `Transcribed`, `Saving`, `SaveFailure`, `Failure`) clears `_pendingAudioPath`/`_audioReviewText`; leaving any Foto sub-state beyond `Idle`/`Captura` (`Processing`, `Reconhecido`, `Saving`, `SaveFailure`, `Failure`) clears `_pendingImagePath`/`_photoReviewText` — both before the target tab's state is emitted (FR-011) — depends on T017 (US2), T038 (US4)
- [X] T041 [US5] Extend `InsertionModalBloc._onModalClosed` to unconditionally clear `_pendingAudioPath`/`_audioReviewText`/`_pendingImagePath`/`_photoReviewText` regardless of which Áudio/Foto sub-state is active when the modal closes (FR-011), matching the existing `close()` override's own fallback path for the swipe-down/tap-outside dismissal case — depends on T040
- [X] T042 [P] [US5] Write `InsertionModalBloc` tests covering abandonment across both modalities and every intermediate state (User Story 5's three Acceptance Scenarios): closing the modal or switching tabs during `InsertionModalAudioProcessing`/`InsertionModalFotoProcessing` causes a later-arriving `transcribe()`/`recognize()` result to be discarded with no entry created, building on T015/T031's stale-result guard (Scenario 1); doing so during `InsertionModalAudioTranscribed`/`InsertionModalFotoReconhecido` with unsaved edits discards both the edits and the capture with no entry created (Scenario 2); doing so during `InsertionModalAudioSaveFailure`/`InsertionModalFotoSaveFailure` likewise creates no entry (Scenario 3, SC-006) — depends on T040, T041

**Checkpoint**: All five user stories are independently functional — no capture, at any stage of
either pipeline, can leave a stray entry behind.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: The constitution/quickstart gates that span every story above.

- [X] T043 [P] Run `fvm flutter analyze` and resolve any `always_use_package_imports`/lint findings introduced under `lib/features/capture/` by this unit
- [X] T044 [P] Run `test/architecture/domain_purity_test.dart` and confirm it still reports 0 violations with `recognize_photo_usecase.dart` and `confirm_entry_save_usecase.dart` included — neither may import `package:flutter`/`dio`/`image_picker`/`whisper_ggml` (RNF06, Post-Design Constitution Check)
- [X] T045 Run `fvm flutter test --coverage`, extract `lib/**/domain/**` via `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info`, and confirm ≥80% coverage with `recognize_photo_usecase.dart` and `confirm_entry_save_usecase.dart` covered in place of the two deleted usecases (RNF07, quickstart.md)
- [ ] T046 Execute quickstart.md's manual verification on the iOS Simulator for Stories 1–5 and its Edge Cases: editing "Transcrito"/"Reconhecido" text down to whitespace-only disables "Salvar" within 100 ms (RNF01); airplane mode resolves "Foto — Processando OCR" directly to a distinct offline "Foto — Erro" message without ever attempting `media-ocr`, while audio transcription still completes normally offline and only its own subsequent "Salvar" is blocked with its own offline message; double-tapping "Salvar"/"Salvar só a foto" on a slow connection creates exactly one entry each; repeated "Tentar novamente" taps in quick succession run only one recognition attempt; backgrounding the app mid-review (`InsertionModalAudioTranscribed`/`InsertionModalFotoReconhecido` with unsaved edits) and foregrounding resumes normally, while a force-kill-and-relaunch does not reopen the modal in any partially-reviewed state

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No tasks — proceed directly to Foundational.
- **Foundational (Phase 2)**: No dependencies — BLOCKS all user stories.
- **User Stories (Phase 3–7)**: All depend on Foundational completion.
  - US1 (P1) and US2 (P1) together build the complete Áudio pipeline; US2 depends on US1's
    `AudioStopRequested` rewrite (T008) already existing to retry against.
  - US3 (P2) and US4 (P2) together build the complete Foto pipeline the same way; US4 depends on
    US3's `PhotoSourceSelected` rewrite (T024). US3 additionally depends on US1's `ConfirmEntrySaveUseCase`
    wiring (T011) and `SaveAudioEntryUseCase`-removal readiness (T014) before it can delete both old
    usecases in T030 — do US1/US2 before US3/US4, per spec.md's own priority ordering.
  - US5 (P3) depends on US2's and US4's narrower abandonment guards (T017, T038) already existing
    to consolidate into the full guard (T040/T041), and on US1's/US3's stale-result guards (T008,
    T024) to build its tests against.
- **Polish (Phase 8)**: Depends on all five stories being complete.

### Within Each User Story

- State/event additions before the bloc handler rewrite that needs them; the bloc handler rewrite
  before the DI update that injects its new dependencies; DI update before the widget sub-views that
  read the new states through `context.read<InsertionModalBloc>()`.
- Tests are written alongside (and can run immediately after) each handler task, per this project's
  existing convention of extending one shared `insertion_modal_bloc_test.dart` across a story's tasks
  rather than one file per task.
- Story complete (states + events + bloc handlers + DI + widget + tests) before moving to the next
  priority.

### Parallel Opportunities

- T001, T002/T003, T005 (Foundational) in parallel with each other — different files.
- T006/T007 (US1 state/event additions) in parallel with each other; same for T022/T023 (US3).
- T020/T021 (US3's `RecognizePhotoUseCase` + its test) in parallel with T022/T023 once Foundational
  lands.
- T015, T019, T031, T039, T042 (bloc test extensions) in parallel with each other once their
  respective sibling implementation tasks land, since they all extend the same file sequentially in
  practice but have no cross-task code dependency beyond that file existing.

---

## Parallel Example: Foundational Phase

```bash
Task: "Add sizePhotoThumbnail/sizeStatusIcon to lib/core/design_tokens.dart"
Task: "Create ConfirmEntrySaveUseCase in lib/features/capture/domain/usecases/confirm_entry_save_usecase.dart"
Task: "Create RecognitionErrorView in lib/features/capture/presentation/widgets/capture_status_views.dart"
```

## Parallel Example: User Story 3 domain layer

```bash
Task: "Create RecognizePhotoUseCase in lib/features/capture/domain/usecases/recognize_photo_usecase.dart"
Task: "Add InsertionModalFotoProcessing/Reconhecido states to insertion_modal_state.dart"
Task: "Add PhotoReviewTextChanged/PhotoSaveConfirmed events to insertion_modal_event.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
2. Complete Phase 3: User Story 1.
3. **STOP and VALIDATE**: record a note, stop, watch "Processando" → "Transcrito", edit the text,
   tap "Salvar" — a new "audio" entry exists with the edited text, and the modal closes. Foto still
   behaves exactly as RF01 built it.

### Incremental Delivery

1. Foundational → `ConfirmEntrySaveUseCase`/tokens/`RecognitionErrorView` exist, nothing visible
   changes yet.
2. Add US1 → Audio's happy-path review flow works end to end (SC-001).
3. Add US2 → Audio's failure/retry/abandon path completes the modality (SC-003, SC-006).
4. Add US3 → Foto's happy-path review flow works end to end (SC-002); both RF01-era save usecases
   are deleted.
5. Add US4 → Foto's failure/retry/"Salvar só a foto"/abandon path completes the modality (SC-003,
   SC-004, SC-006).
6. Add US5 → the cross-modality abandonment safety property is fully consolidated and tested.
7. Polish → RNF06/07 gates + quickstart's full manual pass.

---

## Notes

- `insertion_modal_bloc.dart`, `insertion_modal_event.dart`, `insertion_modal_state.dart`, and
  `insertion_modal_page.dart` are each touched by multiple story phases (T008/T016/T033/T040/T041 for
  the bloc; T007/T023/T032 for events; T006/T022 for states; T012/T028 for the page) — this mirrors
  RF01's own tasks.md precedent: a deliberate consequence of one shared bloc/page serving all tabs,
  not a same-file conflict to avoid.
- `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` and `CaptureFailureBand` are left alive and in use
  until the task that deletes them (T030, T037) — deleting them earlier would break whichever
  modality hadn't been migrated yet, since the app must keep compiling and the non-migrated tab must
  keep working at every checkpoint.
- No task in this list touches `docs/input/`, `docs/input/backend/api/openapi.yaml`, `.env`, any
  native iOS project file, or any of RF04–RF10's behavior — all explicitly out of scope (FR-012,
  FR-013).
- `OcrResult.confidence` is read in T024 but never branched on anywhere, including in the UI (T029),
  per spec.md's resolved Clarification 3 — identical treatment to RF01's own precedent for the same
  field.
