# Implementation Plan: P-RF01 — Multimodal capture

**Branch**: `003-multimodal-capture` (spec directory only — no git branch exists; see spec header)

**Date**: 2026-10-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-multimodal-capture/spec.md`,
`docs/input/requirements.md` §1 (RF01), §6.2 (`/entries`, `/media/ocr`), §9 (data model
reference), §13 (technical constraints), and `.specify/memory/constitution.md`. Depends on F000
(`specs/001-foundation/`) and RF03 (`specs/002-biometric-auth-vault/`), both already implemented.

## Summary

RF01 gives Home/Chat's composer a real "+" button (F000 shipped none — research.md R9) that opens
a bottom-sheet Insertion Modal with three tabs: Texto (free text), Áudio (auto-starts recording on
tab activation), Foto (camera/gallery choice). Confirming Save — tapping "Salvar" for Texto,
tapping stop for Áudio, or supplying an image for Foto (research.md R6) — runs the minimal
recognition this unit owns (on-device Whisper transcription for audio, the backend's existing
`media-ocr` call for photo, per the spec's resolved Clarification) and then creates exactly one
journal entry through a brand-new `entries` feature's shared `CreateEntryUseCase` — the same seam
`requirements.md`'s RF10 text already names and will extend later, never bypass (research.md R8).
Recognition and the entry-creation call both show only a plain, generic loading indicator;
dedicated multi-state recognition screens, an editable review step, and modality-specific retry
affordances are explicitly RF02's to build, not this unit's (FR-007). An offline Save is blocked
before any network call is attempted, via a new cross-cutting `ConnectivityChecker` (research.md
R5) that later offline-gated units (RF04, RF06) can reuse. No backend/contract change.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000/RF03, no new pin needed.

**Primary Dependencies** (additions on top of F000/RF03's stack):
- `record` — real-time microphone capture with a live amplitude signal (research.md R1).
- `whisper_ggml` — on-device speech-to-text; **fixed by Constitution Principle II**, not a choice
  (research.md R2).
- `image_picker` — camera/gallery photo selection (research.md R3).
- `connectivity_plus` — interface-level online/offline check powering the new `ConnectivityChecker`
  (research.md R5).
- `path_provider` — resolves a writable directory for the one-time Whisper model-asset copy
  (research.md R2).
- Reused unchanged from F000/RF03: `flutter_bloc`, `fpdart`, `dio` (via `ApiClient`), `get_it`,
  `equatable`; dev-only `mocktail`, `bloc_test`. `flutter_secure_storage`/`local_auth`/`crypto` are
  not touched by this unit.

**Storage**: No new local database and no new secure-storage key. The only new "storage" this unit
introduces is in-memory: `EntriesRepositoryImpl`'s `cachedEntries` list (process lifetime, via
`get_it`'s `lazySingleton` — same pattern as RF03's `VaultRepository`) and the two bloc-private
temp-file paths (`_pendingAudioPath`/`_pendingImagePath`) that exist only while the modal is open,
to support FR-009's retry-without-recapture. The temp WAV/JPEG files themselves live wherever
`record`/`image_picker` write them (OS-managed app sandbox temp/cache dirs) — this unit does not
manage their cleanup beyond what `AudioCaptureRepository.discard()` deletes explicitly.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, identical to F000/RF03; coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter for the RNF07 gate, now also
covering `lib/features/entries/domain/` and `lib/features/capture/domain/`. `record`,
`image_picker`, and `whisper_ggml` all have no platform channel under `flutter_test` — see
quickstart.md for the manual iOS Simulator verification Stories 1–4 and their Edge Cases need.

**Target Platform**: iOS, portrait only — unchanged. `IPHONEOS_DEPLOYMENT_TARGET` raised from
`15.0` to `15.6` (research.md R2, `whisper_ggml`'s documented floor) across all three build
configurations in `ios/Runner.xcodeproj/project.pbxproj`. Three new `Info.plist` usage-description
strings (`NSMicrophoneUsageDescription`, `NSCameraUsageDescription`,
`NSPhotoLibraryUsageDescription` — research.md R1/R3); no other native project change.

**Project Type**: Same single Flutter mobile app. This unit adds two new feature folders —
`lib/features/entries/` (the shared entry-creation seam, research.md R8) and
`lib/features/capture/` (the Insertion Modal UI and its audio/photo pipelines) — and touches one
existing F000 file (`home_chat_shell_page.dart`, to add the real "+" button — research.md R9). No
backend/server code, no change to `docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 — every network call this unit makes (`entries-create`, `media-ocr`)
shows the existing plain loading indicator (`DesignTokens.sizeLoadingIndicator`/
`strokeWidthLoadingIndicator`, already present from F000/RF03) whenever it exceeds 300 ms; the one
local action with its own 100 ms bar is the Texto tab's "Salvar" enabled/disabled toggle as the
field's emptiness changes, and the Áudio tab's recording starting "immediately" on tab activation.

**Constraints**:
- No RF02 dedicated recognition-state screens (processing/transcribed/recognized/error with their
  own styling), no editable review step, no modality-specific retry affordances ("Tentar
  novamente" styled to match RF02's named Erro states, "Salvar só a foto") — FR-007, research.md
  R11. This unit's own failure/retry UI is deliberately plainer than the prototype's named "Erro"
  states, per spec.md's own resolved Clarification 1.
- No RF04/RF05/RF06/RF07/RF08/RF09/RF10 behavior, no extension feature (manual tags/categories,
  action plans, persona selection) — FR-012.
- No backend/contract/config change (FR-013) — only two already-existing functions are called
  (`entries-create`, `media-ocr`), with request bodies limited to exactly the fields this unit
  needs (data-model.md).
- Audio content never reaches the backend (Constitution Principle II) — transcription is entirely
  on-device via `whisper_ggml`; only its resulting text is ever sent, as an `entries-create` body.
- Clean Architecture, 3 layers per feature (Principle V); `entries/domain/` and `capture/domain/`
  stay free of `package:flutter`, `record`, `image_picker`, and `whisper_ggml` types — see
  contracts/*.md.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — this
  unit needs no new token (research.md R10), reusing F000/RF03's existing scale entirely.

**Scale/Scope**: 1 new "+" button on an existing screen (research.md R9); 1 new bottom-sheet page
(`InsertionModalPage`) with 3 tab widgets, backed by 1 screen-scoped bloc covering 11 sub-states
across the three tabs (contracts/insertion-modal-bloc.md); 2 new feature folders
(`entries`, `capture`) with 2 new network-backed repositories (`EntriesRepository`,
`PhotoRecognitionRepository`, both `Either<Failure, T>`) plus 2 new device-only repositories
(`AudioCaptureRepository`, `PhotoCaptureRepository`) and 1 on-device-only repository
(`AudioTranscriptionRepository`, `Either<RecognitionFailure, T>` — not the backend taxonomy); 1 new
cross-cutting `ConnectivityChecker` in `core/network/`, reusable by later offline-gated units.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this
section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only; this unit's one genuinely silent spot (how "confirming Save" maps to a concrete user action per modality, and how far this unit's own failure UI may deviate from the prototype's named Erro states) was resolved by reasonable technical judgment, documented in research.md R6/R11, building directly on spec.md's own already-resolved Clarifications rather than reopening them. |
| II. Fixed Technology Stack | PASS | `flutter_bloc`/`fpdart`/`mocktail` reused as-is. `whisper_ggml` is Principle II's explicit, non-negotiable choice for speech-to-text (research.md R2) — audio never reaches the backend. `record`/`image_picker`/`connectivity_plus`/`path_provider` are incidental, non-conflicting additions needed to implement literal FRs (FR-004/FR-005/FR-010), in the same category RF03's `crypto` addition already set precedent for. |
| III. Backend Boundary | PASS | Exactly two already-existing functions called: `entries-create` (`POST /entries`) and `media-ocr` (`POST /media/ocr`), both via `{FUNCTIONS_BASE_URL}/<function>`, `Authorization: Bearer <access token>` (user session, `bearerAuth`), reusing `ApiClient` unmodified. No AI provider is ever called directly by the app — both AI-involved steps (PII/embedding on `entries-create`, vision/OCR on `media-ocr`) happen inside the backend. Audio transcription stays entirely on-device, per Principle II. |
| IV. Design Token Discipline & Visual Fidelity | PASS | All three tabs render from `design_tokens.dart`'s existing scale, no new token needed (research.md R10). The one deliberate fidelity carve-out — this unit's plainer failure/retry UI not reproducing the prototype's named "Erro" states — is explicitly sanctioned by spec.md's own resolved Clarification 1, not a new deviation (research.md R11). |
| V. Clean Architecture Folder Convention | PASS | `lib/features/entries/{data,domain,presentation}` (presentation unused by this unit's scope — no entries/-owned screen yet, intentionally left for RF07), `lib/features/capture/{data,domain,presentation}`. No domain type in either feature imports `package:flutter`, `record`, `image_picker`, `whisper_ggml`, or a `data/` class — contracts/*.md. |
| RNF01 (latency) | PASS | Every network call (`entries-create`, `media-ocr`) reuses the existing >300 ms loading-indicator convention; the Áudio tab's "starts immediately" and the Texto tab's enabled/disabled toggle are both purely local, well under 100 ms. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF01 | PII stripping and retention are backend-side policies on `entries-create`, unchanged by this unit; RLS is already enforced server-side on every call this unit makes. |
| RNF05 (hard delete) | N/A to RF01 | Belongs to the Settings/RF09 unit. |
| RNF06 (layer violations) | PASS | `entries/domain/` and `capture/domain/` import no `package:flutter`, `record`, `image_picker`, `whisper_ggml`, or `data/` class — enforced by the same `always_use_package_imports`/`domain_purity_test.dart` convention F000 set up. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | Every usecase in this unit (`CreateEntryUseCase`, `SaveTextEntryUseCase`, `SaveAudioEntryUseCase`, `SavePhotoEntryUseCase`) is a pure orchestration of injected repository interfaces, straightforwardly testable against fakes/mocks — see quickstart.md's test list. |
| RNF08 (visual fidelity) | PASS, with one documented, spec-sanctioned carve-out | Texto/Áudio-Gravando/Foto-Captura rendered per prototype-extract.md §2.3; the audio/photo failure states are this unit's own plainer UI, not the prototype's named "Erro" states — see research.md R11 for why this is not a fidelity gap. |
| RNF09 (Either + 15/15 error scenarios) | PARTIAL BY DESIGN, not a violation | Consistent with F000/RF03's own note: RNF09's 15-scenario target (5 write endpoints × 3 failures) is reached incrementally across the delivery order. This unit contributes full timeout/malformed/offline coverage for 2 of the 5 write endpoints (`entries-create`, `media-ocr`) — 6/15 scenarios, cumulative with F000's auth endpoints. `AudioTranscriptionRepository` deliberately does **not** return `Either<Failure, T>` (the backend taxonomy) — research.md R7, the same scoping precedent RF03's R5 already established for its own local-only repository. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/003-multimodal-capture/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── entries-repository.md
│   ├── audio-capture-repository.md
│   ├── photo-capture-repository.md
│   ├── save-usecases.md
│   └── insertion-modal-bloc.md
├── checklists/
│   └── requirements.md   # already present
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

F000/RF03's Flutter project already exists (`pubspec.yaml`, `lib/`, `test/`). RF01 adds two new
feature folders, one new `core/network/` file, and touches one existing F000 file at its
documented extension point.

```text
cerne-ciclo-a/
├── pubspec.yaml                         # + record, image_picker, whisper_ggml, connectivity_plus, path_provider
├── ios/Runner/Info.plist                # + NSMicrophoneUsageDescription, NSCameraUsageDescription, NSPhotoLibraryUsageDescription
├── ios/Runner.xcodeproj/project.pbxproj # IPHONEOS_DEPLOYMENT_TARGET 15.0 -> 15.6 (research.md R2)
├── assets/models/ggml-tiny*.bin          # bundled Whisper model asset (research.md R2)
├── lib/
│   ├── core/
│   │   └── network/
│   │       └── connectivity_checker.dart    # + (research.md R5) — cross-cutting, not capture-specific
│   ├── features/
│   │   ├── home/presentation/pages/home_chat_shell_page.dart   # composer: + a real "+" IconButton (research.md R9)
│   │   ├── entries/
│   │   │   ├── data/
│   │   │   │   ├── entries_remote_data_source.dart       # POST entries-create
│   │   │   │   └── entries_repository_impl.dart           # + in-memory cachedEntries
│   │   │   └── domain/
│   │   │       ├── entities/
│   │   │       │   └── entry.dart                          # Entry, EntrySource, EntryTag, PiiStatus, PiiSpan, EmbeddingStatus
│   │   │       ├── repositories/
│   │   │       │   └── entries_repository.dart
│   │   │       └── usecases/
│   │   │           └── create_entry_usecase.dart           # the shared seam RF10 will extend
│   │   └── capture/
│   │       ├── data/
│   │       │   ├── audio_recorder_data_source.dart          # wraps `record`
│   │       │   ├── whisper_transcription_data_source.dart   # wraps `whisper_ggml` + model-asset copy
│   │       │   ├── image_picker_data_source.dart             # wraps `image_picker`
│   │       │   ├── media_ocr_remote_data_source.dart          # POST media-ocr
│   │       │   ├── audio_capture_repository_impl.dart
│   │       │   ├── audio_transcription_repository_impl.dart
│   │       │   ├── photo_capture_repository_impl.dart
│   │       │   └── photo_recognition_repository_impl.dart
│   │       ├── domain/
│   │       │   ├── entities/
│   │       │   │   └── recognition_failure.dart              # EmptyRecognitionResult | TranscriptionError (research.md R7)
│   │       │   ├── repositories/
│   │       │   │   ├── audio_capture_repository.dart
│   │       │   │   ├── audio_transcription_repository.dart
│   │       │   │   ├── photo_capture_repository.dart
│   │       │   │   └── photo_recognition_repository.dart
│   │       │   └── usecases/
│   │       │       ├── save_text_entry_usecase.dart
│   │       │       ├── save_audio_entry_usecase.dart
│   │       │       └── save_photo_entry_usecase.dart
│   │       └── presentation/
│   │           ├── bloc/
│   │           │   ├── insertion_modal_bloc.dart
│   │           │   ├── insertion_modal_event.dart
│   │           │   └── insertion_modal_state.dart
│   │           ├── pages/
│   │           │   └── insertion_modal_page.dart             # shown via showModalBottomSheet
│   │           └── widgets/
│   │               ├── capture_tab_bar.dart
│   │               ├── texto_tab_view.dart
│   │               ├── audio_tab_view.dart
│   │               ├── foto_tab_view.dart
│   │               └── audio_waveform.dart                    # reads AudioCaptureRepository.amplitudeStream directly
│   └── core/di/service_locator.dart     # + entries + capture feature registrations, + ConnectivityChecker
└── test/
    └── features/
        ├── entries/
        │   ├── data/...
        │   └── domain/usecases/create_entry_usecase_test.dart     # RNF07 gate lives here
        └── capture/
            ├── data/...
            ├── domain/usecases/...                                  # RNF07 gate lives here
            └── presentation/bloc/insertion_modal_bloc_test.dart
```

**Structure Decision**: Same single Flutter app F000/RF03 established. RF01 is additive
(`features/entries/`, `features/capture/`, `core/network/connectivity_checker.dart`) plus one
one-line-equivalent edit to an existing F000 file's composer widget — chosen over folding
entry-creation logic into `capture/` (research.md R8, directly driven by RF10's own "entries
feature" wording in `requirements.md`). No new top-level directory beyond a small `assets/models/`
addition for the bundled Whisper model, no change to `docs/`, `.specify/`, or prior units' spec
directories.

## Complexity Tracking

*No entries — every addition below is either one of the constitution's implicitly-open choices
(a device-capability package needed to implement a literal FR, same category as RF03's `crypto`)
or `whisper_ggml` itself, which Principle II fixes outright rather than leaving open.*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `EntriesRepository`/`AudioCaptureRepository`/`AudioTranscriptionRepository`/
  `PhotoCaptureRepository`/`PhotoRecognitionRepository` (contracts/*.md) all expose only domain
  types (`Entry`, `EntrySource`, `RecognitionFailure`, `OcrResult`, `PhotoSource`, plain
  `bool`/`String`/`Stream<double>`) — no `record`, `image_picker`, or `whisper_ggml` class crosses
  into `domain/`. RNF06/Principle V confirmed before any code exists.
- `EntriesRepository.create()` and `PhotoRecognitionRepository.recognize()` are the only two
  repositories this unit adds that return `Either<Failure, T>`, reusing F000's existing `Failure`
  hierarchy unchanged — no new `Failure` subtype needed, since `OcrNoTextFailure`/`OCR_NO_TEXT` was
  already present from F000 and fits the illegible-image Edge Case exactly.
  `AudioTranscriptionRepository.transcribe()` deliberately returns `Either<RecognitionFailure, T>`
  instead (research.md R7) — re-checked against RF03's own R5 precedent and found to be the same
  shape of decision, not a new kind of exception to RNF09.
- `CreateEntryUseCase`'s signature (`content`, `source` — no `chatMessageId`, research.md R8) was
  re-checked against RF10's exact requirements.md wording ("the chat feature triggers the creation
  of the entry through a shared interface / use case") and confirmed to satisfy it: RF10 will add
  a parameter to this one usecase, not build a second path into `EntriesRepository`.
- `InsertionModalBloc`'s state machine (contracts/insertion-modal-bloc.md, data-model.md's
  transition tables) was re-checked against research.md R6 specifically for any accidentally
  re-introduced second "Salvar" tap for Áudio/Foto — none exists: stopping the recording and
  supplying an image are each the one and only confirming action for their modality.
- No change surfaced that touches `docs/input/backend/api/openapi.yaml`, `.env`, F000's
  `session_expired_overlay.dart`/re-auth path, RF03's `vault/` feature, or any AI provider —
  Principle III remains intact. The two native-project changes this unit makes
  (`IPHONEOS_DEPLOYMENT_TARGET`, three `Info.plist` strings) are both package-forced, not product
  decisions, the same category RF03's own `NSFaceIDUsageDescription` addition already set
  precedent for.

No new violations. Gate remains PASS.
