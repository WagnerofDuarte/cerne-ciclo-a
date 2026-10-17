# Implementation Plan: P-RF02 — Speech-to-text / OCR processing

**Branch**: `004-stt-ocr-processing` (spec directory only — no git branch exists; see spec header)

**Date**: 2026-10-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-stt-ocr-processing/spec.md`, `docs/input/requirements.md`
§1 (RF02), §6.2 (`/media/ocr`, `/entries`), §13 (technical constraints), `docs/input/prototype/prototype-extract.md`
§2.3/§4, and `.specify/memory/constitution.md`. Depends on RF01 (`specs/003-multimodal-capture/`, already
implemented) whose placeholder recognition UX (its own FR-007) this unit replaces for the Áudio and Foto tabs.

## Summary

RF01 already wired the real pipelines this unit needs — `whisper_ggml` transcription, the `media-ocr` call,
and `POST /entries` — but fused each modality's recognition and entry-creation into one atomic, auto-saving
step behind a plain spinner (FR-007's deliberate placeholder). This unit splits that single step into two:
recognition (transcription/OCR) now runs alone, driving dedicated "Processando"/"Transcrevendo" and
"Reconhecendo texto..." states (prototype-extract.md §2.3), and lands on an editable review state
("Transcrito"/"Reconhecido") with its own explicit "Salvar" — no entry exists until that tap. A prototype-
faithful "Erro" state replaces RF01's own deliberately plain failure band for both modalities (research.md R11
is now superseded by this unit, as spec.md's Clarification 1 always intended), adding Foto's extra "Salvar só
a foto" exit. `InsertionModalBloc`'s audio/photo handlers, `InsertionModalState`/`InsertionModalEvent`, and the
two per-modality save usecases are rewritten; `AudioTranscriptionRepository`, `PhotoRecognitionRepository`, and
every other RF01 repository/data source are reused completely unchanged — this unit adds no new network call
shape and no backend/contract change (FR-013).

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from F000/RF03/RF01.

**Primary Dependencies**: No additions. Reuses RF01's full stack as-is — `whisper_ggml` (on-device transcription,
Constitution Principle II), `image_picker`, `connectivity_plus` (via `ConnectivityChecker`), `dio` (via
`ApiClient`), `flutter_bloc`, `fpdart`, `get_it`, `equatable`; dev-only `mocktail`, `bloc_test`. `record` is
untouched — this unit never changes how audio is captured, only what happens after `stop()` returns a path.

**Storage**: No change to RF01's storage shape. `_pendingAudioPath`/`_pendingImagePath` (bloc-private) keep
their RF01 role (the held file for a retry without re-recording/re-picking) and gain one new responsibility:
surviving the newly-split Processando→Transcrito/Reconhecido boundary, not just the old single Saving state.
`EntriesRepositoryImpl.cachedEntries` (in-memory, `get_it` `lazySingleton`) is unchanged.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter (RNF07), now exercising the two rewritten
usecases below instead of `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase`. `whisper_ggml`/`image_picker` still
have no platform channel under `flutter_test` — quickstart.md covers manual iOS Simulator verification for the
new review/retry/"Salvar só a foto" flows the widget tests can't exercise.

**Target Platform**: iOS, portrait only — unchanged. No native project file touched (no new permission, no
deployment-target change) — this unit is pure Dart/Flutter logic and UI on top of RF01's already-provisioned
native capabilities.

**Project Type**: Same single Flutter mobile app, same two feature folders RF01 created
(`lib/features/capture/`, `lib/features/entries/`) — no new feature folder. No backend/server code, no change
to `docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 unchanged — the `media-ocr` call still shows a loading affordance past 300 ms
(now the prototype's own spinner-plus-caption, not the generic indicator); the Áudio tab's "Processando" state
also appears immediately on stop (on-device transcription itself has no network latency to gate on, but still
renders a spinner for the duration of the Whisper inference call, which commonly exceeds 300 ms on-device).
Toggling "Salvar" enabled/disabled as the reviewed text's emptiness changes stays a local, <100 ms action
(FR-009), identical in spirit to the Texto tab's existing toggle.

**Constraints**:
- No RF04/RF05/RF06/RF07/RF08/RF09/RF10 behavior, no extension feature — FR-012 (unchanged from RF01).
- No backend/contract/config change (FR-013) — the same two functions RF01 already calls
  (`entries-create`, `media-ocr`) are called with the same request shapes; this unit changes only *when* and
  *how many times* they are called relative to recognition, never their payloads.
- Audio content never reaches the backend (Constitution Principle II, FR-004) — unchanged; transcription
  stays entirely on-device, and the connectivity gate that used to run *before* transcription (RF01
  research.md R5) is deliberately removed for audio in this unit (research.md R1 below) since transcription
  itself needs no connectivity and spec.md's FR-001 requires it to start unconditionally on stop.
- Clean Architecture, 3 layers per feature (Principle V) — the two new/rewritten usecases
  (`RecognizePhotoUseCase`, `ConfirmEntrySaveUseCase`) stay in `capture/domain/usecases/` and
  `entries/domain/usecases/`-adjacent territory, free of `package:flutter`/`dio`/`image_picker` types, same as
  every usecase RF01 already shipped.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — this unit, unlike
  RF01, *does* need to render the prototype's actual "Erro" iconography/copy (research.md R2 below) and a
  photo thumbnail, so it adds the small number of new tokens research.md R2 justifies.

**Scale/Scope**: 0 new feature folders; 1 new domain usecase (`RecognizePhotoUseCase`), 1 usecase
consolidation (`SaveAudioEntryUseCase` + `SavePhotoEntryUseCase` → one `ConfirmEntrySaveUseCase`, since both
become identical except for the hardcoded `EntrySource` once recognition moves out of them — data-model.md);
8 new/renamed `InsertionModalState` subclasses (4 per modality) and 5 new `InsertionModalEvent` subclasses;
3 widget files edited (`audio_tab_view.dart`, `foto_tab_view.dart`, `insertion_modal_page.dart`'s tab-mapping
switch); 2 new design tokens (`sizePhotoThumbnail`, `sizeStatusIcon`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only. This unit's genuinely silent spots — the exact UI for a *save-call* failure after a successful recognition (the prototype's "Erro" states are reserved for recognition failures, not post-review save failures), the fixed placeholder string for "Salvar só a foto", and whether audio transcription still needs a pre-flight connectivity check — are resolved by reasonable technical judgment in research.md R1/R3/R4, each built directly on spec.md's own already-resolved Clarifications rather than reopening them. |
| II. Fixed Technology Stack | PASS | No new package. `whisper_ggml` stays Principle II's fixed, non-negotiable choice; audio still never reaches the backend. |
| III. Backend Boundary | PASS | The exact same two functions RF01 already calls (`entries-create`, `media-ocr`), same `ApiClient`/bearer-auth path, same AI-involved steps happening entirely inside the backend. No new function, no contract change. |
| IV. Design Token Discipline & Visual Fidelity | PASS | The prototype's "Erro" states (red warning icon, exact copy, named retry/placeholder actions) are now faithfully rendered — RF01's research.md R11 carve-out is this unit's to close, per spec.md's own resolved Clarification 1. Two new tokens (`sizePhotoThumbnail`, `sizeStatusIcon`, research.md R2) cover the one genuinely new visual element (the photo thumbnail) and the recurring warning icon; everything else (spinner, "Transcrevendo..."/"Reconhecendo texto..." captions, editable field, "Salvar" button, frozen/faded waveform via `Opacity`) reuses RF01's existing token scale and `AudioWaveform` widget unchanged. |
| V. Clean Architecture Folder Convention | PASS | No new feature folder. `RecognizePhotoUseCase`/`ConfirmEntrySaveUseCase` live in `capture/domain/usecases/`, importing only `fpdart`, `core/network/failure.dart`, `core/network/connectivity_checker.dart`, and existing domain repository interfaces — no `package:flutter`, no `data/` class. |
| RNF01 (latency) | PASS | Unchanged call sites, now with the prototype's own loading affordances instead of the generic one past the same 300 ms threshold. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF02 | Backend-side, unaffected by this unit. |
| RNF05 (hard delete) | N/A to RF02 | Belongs to the Settings/RF09 unit. |
| RNF06 (layer violations) | PASS | Same `always_use_package_imports`/domain-purity convention RF01 already set up; no new violation surface introduced by splitting the two usecases apart. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `RecognizePhotoUseCase` and `ConfirmEntrySaveUseCase` are pure orchestrations of injected interfaces (`PhotoRecognitionRepository`/`ConnectivityChecker`, `CreateEntryUseCase`/`ConnectivityChecker`), as straightforwardly testable against fakes as RF01's originals — see quickstart.md. |
| RNF08 (visual fidelity) | PASS | This unit is precisely the one that closes RF01's documented, spec-sanctioned fidelity carve-out (research.md R11 in specs/003) for the Áudio/Foto "Erro" states — see research.md R4 here. |
| RNF09 (Either + 15/15 error scenarios) | PARTIAL BY DESIGN, unchanged count | Still 6/15 cumulative from RF01's `entries-create`/`media-ocr` coverage — this unit restructures *where* those three-scenario checks live (now inside `ConfirmEntrySaveUseCase`/`RecognizePhotoUseCase` rather than the old combined usecases) without adding a new write endpoint. `AudioTranscriptionRepository` still deliberately returns `Either<RecognitionFailure, T>`, not the backend taxonomy (RF01 research.md R7, unchanged). |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/004-stt-ocr-processing/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── insertion-modal-bloc.md
│   └── recognition-and-save-usecases.md
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

RF01's `lib/features/capture/` and `lib/features/entries/` already exist. This unit edits files inside them
and `lib/core/design_tokens.dart`; it creates no new top-level or feature-level directory.

```text
cerne-ciclo-a/
└── lib/
    ├── core/
    │   └── design_tokens.dart                                 # + sizePhotoThumbnail, sizeStatusIcon (research.md R2)
    ├── features/
    │   ├── capture/
    │   │   ├── domain/
    │   │   │   └── usecases/
    │   │   │       ├── recognize_photo_usecase.dart             # NEW — connectivity gate + PhotoRecognitionRepository.recognize()
    │   │   │       ├── confirm_entry_save_usecase.dart          # NEW — replaces save_audio_entry_usecase.dart + save_photo_entry_usecase.dart
    │   │   │       ├── save_audio_entry_usecase.dart             # DELETED (data-model.md)
    │   │   │       └── save_photo_entry_usecase.dart             # DELETED (data-model.md)
    │   │   └── presentation/
    │   │       ├── bloc/
    │   │       │   ├── insertion_modal_event.dart                # + AudioReviewTextChanged, AudioSaveConfirmed, PhotoReviewTextChanged, PhotoSaveConfirmed, PhotoSaveWithoutTextRequested
    │   │       │   ├── insertion_modal_state.dart                 # + *Processing, *Transcrito/*Reconhecido, *SaveFailure states (contracts/insertion-modal-bloc.md)
    │   │       │   └── insertion_modal_bloc.dart                  # audio/photo handlers rewritten to call recognition and save as two separate steps
    │   │       ├── pages/
    │   │       │   └── insertion_modal_page.dart                  # _tabOf switch extended for the new state cases
    │   │       └── widgets/
    │   │           ├── audio_tab_view.dart                        # + Processando/Transcrito/Erro/SaveFailure sub-views
    │   │           ├── foto_tab_view.dart                         # + Processando OCR/Reconhecido/Erro (two actions)/SaveFailure sub-views, thumbnail
    │   │           └── capture_status_views.dart                  # CaptureFailureBand removed (superseded); new RecognitionErrorView added
    │   └── (entries/ unchanged — Entry, EntriesRepository, CreateEntryUseCase all reused as-is)
    └── core/di/service_locator.dart                              # registrations updated for the usecase/bloc-dependency changes above
```

**Structure Decision**: Purely additive-and-corrective edits inside RF01's existing `capture`/`entries`
feature folders — no new top-level directory, no new feature. The one naming-level decision
(`ConfirmEntrySaveUseCase` replacing two near-duplicate per-modality usecases) is a consolidation, not a new
abstraction: once recognition moves out of each, `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` differ only
by a hardcoded `EntrySource` constant — data-model.md documents the merge.

## Complexity Tracking

*No entries — this unit adds no new dependency, no new feature folder, and no new kind of architectural
seam; its one consolidation (two usecases → one) reduces rather than adds complexity.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `RecognizePhotoUseCase`/`ConfirmEntrySaveUseCase` expose and consume only domain types (`OcrResult`,
  `Entry`, `EntrySource`, the two new local sealed failure types) — no `dio`/`image_picker`/`whisper_ggml`
  class crosses into `domain/`. RNF06/Principle V confirmed before any code exists.
- `AudioTranscriptionRepository.transcribe()` and `PhotoRecognitionRepository.recognize()` are called
  directly by `InsertionModalBloc` (no new usecase wrapping either), matching RF01's own established
  precedent of calling `AudioCaptureRepository`/`PhotoCaptureRepository` directly from the bloc for
  orchestration-free pass-throughs (data-model.md's rationale) — re-checked and found consistent, not a new
  kind of exception.
- The bloc's new "guard against a stale recognition result" rule (data-model.md: a `transcribe()`/
  `recognize()` result is only applied if the bloc's current state is still the matching `*Processing` state
  for the same held path) was re-checked against spec.md's Edge Case "no entry is created, regardless of how
  the in-flight recognition call eventually resolves" (User Story 5) and confirmed necessary — without it, a
  tab-switch-away-and-back during an in-flight call could apply a stale result to the wrong, newer state.
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file,
  F000's session/vault features, or any AI provider — Principle III remains intact.

No new violations. Gate remains PASS.
