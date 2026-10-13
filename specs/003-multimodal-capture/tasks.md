---

description: "Task list for P-RF01 — Multimodal capture"
---

# Tasks: P-RF01 — Multimodal capture

**Input**: Design documents from `/specs/003-multimodal-capture/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. The constitution's RNF07 (`lib/**/domain/**` ≥80% coverage) and RNF09
(15/15 write-endpoint failure scenarios via `mocktail`) gates apply to this unit, and
quickstart.md's "Automated checks" section explicitly names the domain/data tests this unit's
coverage depends on — so test tasks are generated alongside implementation, matching
F000/RF03's existing `bloc_test`/`mocktail` style exactly.

**Organization**: Tasks are grouped by user story (US1–US4, spec.md priorities P1/P1/P2/P3). Per
contracts/insertion-modal-bloc.md, all four stories share one page/bloc
(`InsertionModalPage`/`InsertionModalBloc`) by deliberate design (research.md R6) — "independent"
here means each story's acceptance scenarios can be exercised and automated-tested on their own
once Foundational is done, not that each story gets its own screen or bloc. `entries/` (research.md
R8) is built once in Foundational because all three capture modalities (US1–US3) depend on
`CreateEntryUseCase` to persist their result.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on an incomplete task)
- **[Story]**: US1 (text entry), US2 (audio entry), US3 (photo entry), US4 (abandoning a capture
  leaves nothing behind)

## Path Conventions

Single Flutter project (F000/RF03's existing `lib/`, `test/`) — see plan.md Project Structure. All
new files live under `lib/features/entries/`, `lib/features/capture/`, `test/features/entries/`,
`test/features/capture/`, and one new `lib/core/network/connectivity_checker.dart`; one existing
F000 file (`home_chat_shell_page.dart`) and the shared `service_locator.dart`/`pubspec.yaml`/iOS
project files are touched at documented extension points.

---

## Phase 1: Setup

**Purpose**: Dependencies and native-project changes every later task needs.

- [X] T001 Add `record`, `image_picker`, `whisper_ggml`, `connectivity_plus`, and `path_provider` to `pubspec.yaml` dependencies (research.md R1–R5), then run `fvm flutter pub get`
- [X] T002 [P] Add `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, and `NSPhotoLibraryUsageDescription` (three one-line usage strings) to `ios/Runner/Info.plist` — required before any mic/camera/gallery access is even attempted on-device or in the Simulator (research.md R1/R3)
- [X] T003 Raise `IPHONEOS_DEPLOYMENT_TARGET` from `15.0` to `15.6` across all three build configurations (Debug/Release/Profile) in `ios/Runner.xcodeproj/project.pbxproj` — `whisper_ggml`'s documented minimum (research.md R2)
- [X] T004 [P] Bundle the `ggml-tiny` (quantized `q5_1` variant preferred for size) Whisper model asset under `assets/models/` and declare it under `flutter.assets` in `pubspec.yaml` — delivered as a bundled asset, never downloaded over the network, so on-device transcription stays network-independent from first launch (research.md R2)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared `entries` feature (the one sanctioned seam every capture modality creates
an entry through), the cross-cutting `ConnectivityChecker`, and the Insertion Modal's
page/bloc/tab-bar shell every user story extends. No story's acceptance scenario can be exercised,
manually or in a test, until this phase is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### `entries` feature (research.md R8 — built once, depended on by US1/US2/US3)

- [X] T005 [P] Create `Entry` entity plus its `EntrySource` (`manual`, `audio`, `photo` only for this unit — **not** `chat`, which is RF10's own addition), `PiiStatus` (`pending`\|`clean`\|`flagged`\|`failed`), and `EmbeddingStatus` (`pending`\|`ready`\|`failed`) enums, and `EntryTag`/`PiiSpan` classes, in `lib/features/entries/domain/entities/entry.dart` — every field in data-model.md's table is `required` (the full `entries-create` response shape), including `content` (`String`, "1–20000 chars; the text this unit always supplies non-empty"), `chatMessageId` ("Always `null` for every entry this unit creates"), `tags` ("Always empty for a freshly created entry"), and `mediaDurationSeconds` ("This unit never sends it in the request, so it is always `null`")
- [X] T006 Create the `EntriesRepository` abstract interface — `Future<Either<Failure, Entry>> create({required String content, required EntrySource source})` and `List<Entry> get cachedEntries` — in `lib/features/entries/domain/repositories/entries_repository.dart` (contracts/entries-repository.md) — depends on T005
- [X] T007 [P] Create `CreateEntryUseCase` ("the one and only sanctioned way any other feature creates an entry") in `lib/features/entries/domain/usecases/create_entry_usecase.dart` — `call(String content, EntrySource source)` delegates straight to `repository.create(...)`; takes only `(content, source)`, no `chatMessageId` parameter (research.md R8 — RF10 will extend this signature, never bypass it) — depends on T006
- [X] T008 [P] Write `CreateEntryUseCase` tests in `test/features/entries/domain/usecases/create_entry_usecase_test.dart` against a fake `EntriesRepository` (RNF07 gate): delegates with the exact `content`/`source` given; `Right(entry)` and `Left(failure)` both pass through unchanged — depends on T007
- [X] T009 Create `EntriesRemoteDataSource` in `lib/features/entries/data/entries_remote_data_source.dart` — the only class calling `ApiClient.call('entries-create', method: 'POST', body: {'content': content, 'source': source.name})` and parsing the full `Entry` response shape; never sends `occurredAt`/`mediaDurationSeconds`/`chatMessageId` in the request body (contracts/entries-repository.md) — depends on T005
- [X] T010 [P] Write `EntriesRemoteDataSource` tests in `test/features/entries/data/entries_remote_data_source_test.dart` (mocktail, mocking `ApiClient`, matching `auth_remote_data_source_test.dart`'s existing pattern) — depends on T009
- [X] T011 Create `EntriesRepositoryImpl` implementing `EntriesRepository` in `lib/features/entries/data/entries_repository_impl.dart` — wraps `EntriesRemoteDataSource`, maps `DioException`/malformed bodies through the existing `ErrorMapper` unchanged, and owns the in-memory `List<Entry>` backing `cachedEntries` (appended to only on a successful `create()`, never read back out for display by this unit — FR-011) — depends on T006, T009
- [X] T012 [P] Write `EntriesRepositoryImpl` tests in `test/features/entries/data/entries_repository_impl_test.dart` covering the 3 failure scenarios for `entries-create` (timeout → `NetworkTimeoutFailure`, no connection → `NetworkOfflineFailure`, malformed response → `ValidationFailure` — data-model.md, toward RNF09's running 15-scenario total) plus the cache-append-on-success behavior — depends on T011

### Cross-cutting

- [X] T013 [P] Create `ConnectivityChecker` in `lib/core/network/connectivity_checker.dart` — `Future<bool> hasConnection()` wrapping `connectivity_plus`'s `Connectivity().checkConnectivity()`, `true` unless the result is `ConnectivityResult.none` — lives in `core/`, not inside `capture/`, because later offline-gated units (RF04, RF06) reuse this exact checker (research.md R5)

### Dependency injection

- [X] T014 Register `EntriesRemoteDataSource`, `EntriesRepository` (as `registerLazySingleton` — one instance for the app's process lifetime, same pattern `VaultRepository` uses, so `cachedEntries` survives across modal opens), `CreateEntryUseCase`, and `ConnectivityChecker` in `lib/core/di/service_locator.dart` — depends on T009, T011, T007, T013

### Insertion Modal shell (shared by all three capture tabs)

- [X] T015 [P] Create `CaptureTab` enum (`texto`, `audio`, `foto`) and the `InsertionModalEvent` sealed base with `TabSelected` and `ModalClosed` events in `lib/features/capture/presentation/bloc/insertion_modal_event.dart` (contracts/insertion-modal-bloc.md)
- [X] T016 [P] Create the `InsertionModalState` sealed base with `InsertionModalTexto(text)` — the initial state (`const InsertionModalTexto(text: '')`, FR-002's default tab) — in `lib/features/capture/presentation/bloc/insertion_modal_state.dart`
- [X] T017 Create `InsertionModalBloc` skeleton in `lib/features/capture/presentation/bloc/insertion_modal_bloc.dart` — no `ModalOpened`/async-resolution event needed since the Texto tab's default state is static and synchronous (contracts/insertion-modal-bloc.md); handle `TabSelected(texto)` by restoring the bloc-private text draft, and a placeholder `ModalClosed` handler (extended by T065 in US4) — depends on T015, T016
- [X] T018 [P] Create `CaptureTabBar` widget in `lib/features/capture/presentation/widgets/capture_tab_bar.dart` — exactly three tabs ("Texto", "Áudio", "Foto") dispatching `TabSelected`, with the active tab visually distinguished ("MUST present exactly three capture modes as tabs... with the active tab visually distinguished" — FR-002) — depends on T015
- [X] T019 Create `InsertionModalPage` skeleton in `lib/features/capture/presentation/pages/insertion_modal_page.dart` — rendered as an overlay above Home/Chat with a darkened scrim and a close control, without discarding Home/Chat's state underneath ("MUST provide an Insertion Modal... shown as an overlay above Home/Chat (with a darkened scrim) without discarding or navigating away from Home/Chat's state underneath" — FR-001); an exhaustive `BlocBuilder` switch over `InsertionModalState` (tab bodies filled in by later story tasks) plus a `BlocListener` that pops the sheet on the one-shot success side effect (FR-011 — no dedicated `InsertionModalSuccess` state needed, per contracts/insertion-modal-bloc.md) — depends on T017, T018

**Checkpoint**: Foundation ready — the `entries` feature, `ConnectivityChecker`, and
`InsertionModalPage`/`InsertionModalBloc`/`CaptureTabBar` shell all exist and are wired through DI.
User story implementation can now begin.

---

## Phase 3: User Story 1 - Writing a journal entry as text (Priority: P1) 🎯 MVP

**Goal**: Tapping "+" opens the modal on its Texto tab; typing non-empty text enables "Salvar";
tapping it creates exactly one entry with origin "manual" and closes the modal back to Home/Chat.

**Independent Test**: Tap "+", type text into the Texto tab, tap "Salvar", and confirm a new entry
with that exact text and origin "manual" now exists, and the modal has closed back to Home/Chat.

### Implementation for User Story 1

- [X] T020 [P] [US1] Add `TextDraftChanged(text)` and `SaveTextSubmitted` events to `insertion_modal_event.dart` — depends on T015
- [X] T021 [P] [US1] Add `InsertionModalTextoSaving(text)` and `InsertionModalTextoFailure(text, message)` states to `insertion_modal_state.dart` — depends on T016
- [X] T022 [US1] Create `SaveTextEntryUseCase` in `lib/features/capture/domain/usecases/save_text_entry_usecase.dart` — `call(text)`: `ConnectivityChecker.hasConnection() == false` → `Left(NetworkOfflineFailure(...))` *before* calling `CreateEntryUseCase` at all ("the system MUST block the Save action with a clear message rather than attempting a write that cannot succeed" — FR-010); else `CreateEntryUseCase(text, EntrySource.manual)` (save-usecases.md) — depends on T007, T013
- [X] T023 [P] [US1] Write `SaveTextEntryUseCase` tests in `test/features/capture/domain/usecases/save_text_entry_usecase_test.dart` against fakes: offline → `Left(NetworkOfflineFailure)` without `CreateEntryUseCase` ever being invoked; `CreateEntryUseCase` failure passes through unchanged; happy path → `Right(entry)` with `source: manual` — depends on T022
- [X] T024 [US1] Register `InsertionModalBloc` as a `registerFactory` in `lib/core/di/service_locator.dart`, constructed with `SaveTextEntryUseCase` — depends on T022, T017, T014
- [X] T025 [US1] Extend `InsertionModalBloc`'s constructor and implement `TextDraftChanged` (→ `InsertionModalTexto(text)`) and `SaveTextSubmitted` (ignored while `state is InsertionModalTextoSaving` — double-tap guard, Assumptions; else → `InsertionModalTextoSaving(text)`, await `SaveTextEntryUseCase(text)`, `Right(entry)` → one-shot success side effect, `Left(failure)` → `InsertionModalTextoFailure(text, failure.message)`) — depends on T017, T020, T021, T022
- [X] T026 [US1] Create `TextoTabView` widget in `lib/features/capture/presentation/widgets/texto_tab_view.dart` — a free multiline text field and a "Salvar" action "that is unavailable while the field is empty" ("MUST provide a free multiline text field and a 'Salvar' action that is unavailable while the field is empty" — FR-003, enabled iff `text.trim().isNotEmpty`); renders the plain generic loading indicator (`DesignTokens.sizeLoadingIndicator`/`strokeWidthLoadingIndicator`) for `InsertionModalTextoSaving` and a plain failure message for `InsertionModalTextoFailure` — depends on T021
- [X] T027 [US1] Wire `InsertionModalPage`'s Texto branch to render `TextoTabView`, and add a real, enabled leading `IconButton` ("+") to `_ComposerBar` in `lib/features/home/presentation/pages/home_chat_shell_page.dart`, opening `InsertionModalPage` via `showModalBottomSheet` wrapped in a fresh `BlocProvider(create: (_) => getIt<InsertionModalBloc>())` per open — a fresh bloc on every open is what satisfies FR-002's "reset every tab... each time the modal is freshly opened" by construction (research.md R9, contracts/insertion-modal-bloc.md) — depends on T019, T024, T026
- [X] T028 [P] [US1] Write `InsertionModalBloc` tests in `test/features/capture/presentation/bloc/insertion_modal_bloc_test.dart` for the Texto flow: empty-field `SaveTextSubmitted` is never reachable (enabled/disabled is a widget-level concern, verified in T026, but the bloc test confirms `TextDraftChanged` round-trips the draft correctly); `SaveTextSubmitted` success triggers the close side-effect and appends to `cachedEntries`; offline blocks before `CreateEntryUseCase` is ever called; a second `SaveTextSubmitted` while already `InsertionModalTextoSaving` is ignored (no duplicate entry — Edge Cases: "double-taps 'Salvar'... only one entry is ever created") — depends on T025

**Checkpoint**: User Story 1 is independently functional and testable — text capture works end to
end.

---

## Phase 4: User Story 2 - Recording a journal entry as audio (Priority: P1)

**Goal**: Switching to the Áudio tab starts recording immediately with a waveform and timer;
tapping stop transcribes on-device and saves, producing one entry with origin "audio"; a
recognition/save failure never loses the recording and lets the user retry without re-recording.

**Independent Test**: Open the Áudio tab, record a short spoken note, stop the recording, confirm
Save completes, and confirm a new entry exists with origin "audio" and text content derived from
what was spoken.

### Implementation for User Story 2

- [X] T029 [P] [US2] Create the `RecognitionFailure` sealed type (`EmptyRecognitionResult`, `TranscriptionError`) in `lib/features/capture/domain/entities/recognition_failure.dart` — local to `capture/domain/`, **not** added to `core/network/failure.dart`, since this is a purely local condition with no corresponding backend code (research.md R7)
- [X] T030 [P] [US2] Create `AudioCaptureRepository` abstract interface (`hasPermission()`, `start()`, `amplitudeStream`, `stop()` returning the finished WAV file's path, `discard()`) in `lib/features/capture/domain/repositories/audio_capture_repository.dart` (contracts/audio-capture-repository.md)
- [X] T031 [P] [US2] Create `AudioTranscriptionRepository` abstract interface (`Future<Either<RecognitionFailure, String>> transcribe(String audioFilePath)`) in `lib/features/capture/domain/repositories/audio_transcription_repository.dart` — depends on T029
- [X] T032 [US2] Create `AudioRecorderDataSource` in `lib/features/capture/data/audio_recorder_data_source.dart` — the only class importing `record`'s `AudioRecorder`/`RecordConfig`/`AudioEncoder` types, configured `RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)` (research.md R1), exposing `onAmplitudeChanged(Duration)` as a `Stream<double>`
- [X] T033 [US2] Create `AudioCaptureRepositoryImpl` implementing `AudioCaptureRepository` in `lib/features/capture/data/audio_capture_repository_impl.dart`, mapping everything to plain `bool`/`String`/`Stream<double>` before it reaches `domain/` (RNF06) — depends on T030, T032
- [X] T034 [US2] Create `WhisperTranscriptionDataSource` in `lib/features/capture/data/whisper_transcription_data_source.dart` — the only class importing `whisper_ggml`'s `WhisperController`/`WhisperModel` types; owns the one-time "copy the bundled `ggml-tiny` model asset to a writable app-support directory via `path_provider`" step on first use, reusing the copied file on subsequent calls (research.md R2) — depends on T004
- [X] T035 [US2] Create `AudioTranscriptionRepositoryImpl` implementing `AudioTranscriptionRepository` in `lib/features/capture/data/audio_transcription_repository_impl.dart` — calls `WhisperController.transcribe(model: WhisperModel.tiny, audioPath: ..., lang: 'pt')`; a transcript that is "empty or whitespace-only after `.trim()`" is reported as `Left(EmptyRecognitionResult())`, never `Right('')` (contracts/audio-capture-repository.md); an internal/model-load exception → `Left(TranscriptionError())` — depends on T031, T034
- [X] T036 [P] [US2] Write `AudioTranscriptionRepositoryImpl` tests in `test/features/capture/data/audio_transcription_repository_impl_test.dart` (fake `WhisperTranscriptionDataSource`): empty/whitespace transcript → `EmptyRecognitionResult`; thrown exception → `TranscriptionError`; happy path → `Right(text)` — depends on T035
- [X] T037 [US2] Create `SaveAudioEntryUseCase` in `lib/features/capture/domain/usecases/save_audio_entry_usecase.dart` — a `SaveAudioFailure` sealed result (`offline`, `recognition`, `entryCreation(Failure)`); `ConnectivityChecker.hasConnection() == false` → `Left(SaveAudioFailure.offline)` checked *before* transcribing at all (research.md R5); else `AudioTranscriptionRepository.transcribe(path)`, `Left(recognitionFailure)` → `Left(SaveAudioFailure.recognition)`, `Right(text)` → `CreateEntryUseCase(text, EntrySource.audio)`, mapping its own `Left(failure)` to `Left(SaveAudioFailure.entryCreation(failure))` (save-usecases.md) — depends on T031, T007, T013
- [X] T038 [P] [US2] Write `SaveAudioEntryUseCase` tests in `test/features/capture/domain/usecases/save_audio_entry_usecase_test.dart` against fakes: offline short-circuit before `transcribe()` is ever called; transcription failure → `recognition`; empty-result transcription → `recognition`; entry-creation failure → `entryCreation(failure)`; happy path → `Right(entry)` with `source: audio` — depends on T037
- [X] T039 [P] [US2] Add `InsertionModalAudioPermissionDenied`, `InsertionModalAudioRecording(elapsed)`, `InsertionModalAudioSaving`, and `InsertionModalAudioFailure(message)` states to `insertion_modal_state.dart` — depends on T016
- [X] T040 [P] [US2] Add `AudioTimerTicked` (internal, drives `elapsed` only), `AudioStopRequested`, and `RetryRequested` events to `insertion_modal_event.dart` — depends on T015
- [X] T041 [US2] Extend `InsertionModalBloc`'s constructor (add `AudioCaptureRepository`, `SaveAudioEntryUseCase`) and implement: `TabSelected(audio)` (`hasPermission() == false` → `InsertionModalAudioPermissionDenied` — "the respective tab shows an explanatory message in place of the recording/capture controls" — Edge Cases; else `start()` → `InsertionModalAudioRecording(elapsed: Duration.zero)` plus a local 1-second ticker dispatching `AudioTimerTicked`); `AudioStopRequested` (ignored unless `state is InsertionModalAudioRecording`; `stop()` → store the path in `_pendingAudioPath`, emit `InsertionModalAudioSaving()`, await `SaveAudioEntryUseCase(path)`, mapping its three-way failure to `InsertionModalAudioFailure` with the matching message or triggering the close side-effect on success); and extend `TabSelected(<anything>)` while `InsertionModalAudioRecording` to call `AudioCaptureRepository.discard()` and clear `_pendingAudioPath` before transitioning to the target tab ("the in-progress recording is discarded... since no partial entry may survive regardless of which tab is active afterward" — Edge Cases) — depends on T017, T025, T030, T037, T039, T040
- [X] T042 [US2] Implement `RetryRequested` for the audio branch: re-dispatch `AudioStopRequested`'s saving logic against the already-held `_pendingAudioPath`, "without having to re-record" ("the user can retry without having to re-record, as long as the captured audio is still held locally" — FR-009) — depends on T041
- [X] T043 [US2] Create `AudioWaveform` widget in `lib/features/capture/presentation/widgets/audio_waveform.dart`, reading `AudioCaptureRepository.amplitudeStream` directly via `get_it` — the one sanctioned bypass of "always through the bloc" for this unit, since the amplitude signal is too high-frequency to belong in bloc event history (contracts/audio-capture-repository.md) — depends on T033
- [X] T044 [US2] Create `AudioTabView` widget in `lib/features/capture/presentation/widgets/audio_tab_view.dart` — a stop control, `AudioWaveform`, and a running `mm:ss` timer for `InsertionModalAudioRecording` ("showing a stop control, an animated waveform, and a running mm:ss timer" — FR-004); the permission-denied explanatory message; the plain generic loading indicator for `InsertionModalAudioSaving` (FR-007 — not a styled "Transcrevendo..." screen); a plain failure message plus one generic retry action for `InsertionModalAudioFailure`, deliberately **not** reproducing the prototype's named "Áudio — Erro" styling/copy/"Tentar novamente" treatment (research.md R11) — depends on T039, T043
- [X] T045 [US2] Wire `InsertionModalPage`'s Áudio branch to render `AudioTabView` — depends on T019, T044
- [X] T046 [US2] Register `AudioRecorderDataSource`, `AudioCaptureRepository`, `WhisperTranscriptionDataSource`, `AudioTranscriptionRepository`, and `SaveAudioEntryUseCase` in `lib/core/di/service_locator.dart`, and update `InsertionModalBloc`'s factory registration to inject `AudioCaptureRepository` and `SaveAudioEntryUseCase` alongside `SaveTextEntryUseCase` — depends on T033, T035, T037, T024
- [X] T047 [P] [US2] Extend `InsertionModalBloc` tests in `insertion_modal_bloc_test.dart` for the Audio flow: `TabSelected(audio)` with permission denied/granted; `AudioStopRequested` success triggers the close side-effect and appends to `cachedEntries`; recognition failure / empty result / entry-creation failure each map to `InsertionModalAudioFailure` with the correct message; `RetryRequested` re-uses `_pendingAudioPath` without calling `start()`/`stop()` again; `TabSelected(<other tab>)` mid-recording calls `discard()` — depends on T041, T042

**Checkpoint**: User Stories 1 AND 2 both work independently — text and audio capture both
converge on the same entry format.

---

## Phase 5: User Story 3 - Capturing a journal entry from a photo (Priority: P2)

**Goal**: Switching to the Foto tab offers Câmera/Galeria; supplying an image runs backend OCR and
saves, producing one entry with origin "photo"; a recognition/save failure never loses the image
and lets the user retry without recapturing.

**Independent Test**: Open the Foto tab, choose "Câmera" or "Galeria" to supply an image containing
legible text, confirm the save completes, and confirm a new entry exists with origin "photo" and
the recognized text as its content.

### Implementation for User Story 3

- [X] T048 [P] [US3] Create the `PhotoSource` enum (`camera`, `gallery`) and `PhotoCaptureRepository` abstract interface (`Future<String?> pickImage(PhotoSource source)` — `null` means the user cancelled the OS picker) in `lib/features/capture/domain/repositories/photo_capture_repository.dart` (contracts/photo-capture-repository.md)
- [X] T049 [P] [US3] Create the `OcrResult` class (`text`, `confidence: "high"|"low"` — "carried through, never branched on" per Clarification 3) and `PhotoRecognitionRepository` abstract interface (`Future<Either<Failure, OcrResult>> recognize(String imageFilePath)`) in `lib/features/capture/domain/repositories/photo_recognition_repository.dart`
- [X] T050 [US3] Create `ImagePickerDataSource` in `lib/features/capture/data/image_picker_data_source.dart` — the only class importing `image_picker`'s `ImagePicker`/`ImageSource`/`XFile` types, always calling `pickImage(source: ..., imageQuality: 90)` so every returned file is JPEG regardless of the original asset format, notably HEIC from the iOS Photos library (research.md R3) — depends on T048
- [X] T051 [US3] Create `PhotoCaptureRepositoryImpl` implementing `PhotoCaptureRepository` in `lib/features/capture/data/photo_capture_repository_impl.dart` — depends on T048, T050
- [X] T052 [US3] Create `MediaOcrRemoteDataSource` in `lib/features/capture/data/media_ocr_remote_data_source.dart` — reads the picked file's bytes, `base64Encode`s them (`dart:convert`, no new package), and calls `ApiClient.call('media-ocr', method: 'POST', body: {'image': base64, 'mimeType': 'image/jpeg'})` (research.md R4) — depends on T049
- [X] T053 [US3] Create `PhotoRecognitionRepositoryImpl` implementing `PhotoRecognitionRepository` in `lib/features/capture/data/photo_recognition_repository_impl.dart` — reuses `ApiClient`/`ErrorMapper` unmodified; `OCR_NO_TEXT` maps to the already-existing `OcrNoTextFailure` (present in `failure.dart` since F000); a client-side guard treats a `200` response whose `text` is empty/whitespace-only identically to `OcrNoTextFailure` ("a defensive normalization, not a new failure type" — contracts/photo-capture-repository.md) — depends on T049, T052
- [X] T054 [P] [US3] Write `PhotoRecognitionRepositoryImpl` tests in `test/features/capture/data/photo_recognition_repository_impl_test.dart`: the 3 failure scenarios for `media-ocr` (timeout/offline/malformed → `NetworkTimeoutFailure`/`NetworkOfflineFailure`/`ValidationFailure`, toward RNF09's running total), `OcrNoTextFailure`, and the client-side empty-text guard on a `200` with blank `text` — depends on T053
- [X] T055 [US3] Create `SavePhotoEntryUseCase` in `lib/features/capture/domain/usecases/save_photo_entry_usecase.dart` — same shape as `SaveAudioEntryUseCase` (`SavePhotoFailure`: `offline`\|`recognition`\|`entryCreation(Failure)`), substituting `PhotoRecognitionRepository.recognize(imageFilePath)` for the transcription call, ignoring `OcrResult.confidence` entirely regardless of `"high"`/`"low"` (Clarification 3: "any non-empty recognized text, regardless of confidence, proceeds to Save normally") — depends on T049, T007, T013
- [X] T056 [P] [US3] Write `SavePhotoEntryUseCase` tests in `test/features/capture/domain/usecases/save_photo_entry_usecase_test.dart` against fakes: offline short-circuit before `recognize()` is ever called; `OcrNoTextFailure`/other recognition failure → `recognition`; entry-creation failure → `entryCreation(failure)`; happy path with `confidence: "low"` still proceeds to `Right(entry)` with `source: photo` (Clarification 3) — depends on T055
- [X] T057 [P] [US3] Add `InsertionModalFotoCaptura`, `InsertionModalFotoPermissionDenied`, `InsertionModalFotoSaving`, and `InsertionModalFotoFailure(message)` states to `insertion_modal_state.dart` — depends on T016
- [X] T058 [P] [US3] Add `PhotoSourceSelected(source)` event to `insertion_modal_event.dart` — depends on T015, T048
- [X] T059 [US3] Extend `InsertionModalBloc`'s constructor (add `PhotoCaptureRepository`, `SavePhotoEntryUseCase`) and implement: `TabSelected(foto)` (→ `InsertionModalFotoCaptura()` unconditionally — camera/gallery permission is requested per-button-tap by `image_picker` itself, not up front); `PhotoSourceSelected(source)` (ignored if `state is InsertionModalFotoSaving`; `pickImage(source)` → `null` stays `InsertionModalFotoCaptura()` — "cancels it without completing a capture... no entry is created" — User Story 4/Edge Cases; a path → store it in `_pendingImagePath`, emit `InsertionModalFotoSaving()`, await `SavePhotoEntryUseCase(path)`, mapping failure to `InsertionModalFotoFailure` with the matching message or triggering the close side-effect on success) — depends on T017, T025, T048, T055, T057, T058
- [X] T060 [US3] Implement `RetryRequested` for the foto branch (extend T042's handler to also cover `InsertionModalFotoFailure`): re-run the recognize+create logic against the already-held `_pendingImagePath`, "without having to recapture the image" (FR-009) — depends on T059, T042
- [X] T061 [US3] Create `FotoTabView` widget in `lib/features/capture/presentation/widgets/foto_tab_view.dart` — two buttons, "Câmera" and "Galeria", with no image selected yet, for `InsertionModalFotoCaptura` ("two options are shown — 'Câmera' and 'Galeria' — with no image selected yet" — FR-005/User Story 3 Scenario 1); the permission-denied explanatory message; the plain generic loading indicator for `InsertionModalFotoSaving`; a plain failure message plus one generic retry action for `InsertionModalFotoFailure`, deliberately not reproducing the prototype's named "Foto — Erro" styling/copy or its "Salvar só a foto" action (research.md R11) — depends on T057
- [X] T062 [US3] Wire `InsertionModalPage`'s Foto branch to render `FotoTabView` — depends on T019, T061
- [X] T063 [US3] Register `ImagePickerDataSource`, `PhotoCaptureRepository`, `MediaOcrRemoteDataSource`, `PhotoRecognitionRepository`, and `SavePhotoEntryUseCase` in `lib/core/di/service_locator.dart`, and update `InsertionModalBloc`'s factory registration to inject `PhotoCaptureRepository` and `SavePhotoEntryUseCase` alongside the audio/text dependencies — depends on T051, T053, T055, T046
- [X] T064 [P] [US3] Extend `InsertionModalBloc` tests in `insertion_modal_bloc_test.dart` for the Foto flow: `TabSelected(foto)` → `InsertionModalFotoCaptura`; `PhotoSourceSelected` cancelled (`null`) stays on `InsertionModalFotoCaptura`; success triggers the close side-effect and appends to `cachedEntries`; recognition failure / `OCR_NO_TEXT` / entry-creation failure each map to `InsertionModalFotoFailure` with the correct message; `RetryRequested` re-uses `_pendingImagePath` without calling `pickImage()` again — depends on T059, T060

**Checkpoint**: User Stories 1, 2, AND 3 all work independently — all three modalities converge on
the same persisted-entry format (SC-001).

---

## Phase 6: User Story 4 - Abandoning a capture leaves nothing behind (Priority: P3)

**Goal**: Closing the modal, navigating away, stopping a recording without saving, or cancelling
the photo picker — in any tab, at any point before Save is confirmed — leaves zero entries behind.

**Independent Test**: Start each modality (typing a partial note, starting a recording, opening the
camera/gallery picker) and close the modal or navigate away before tapping Salvar; confirm no new
entry was created in any case.

### Implementation for User Story 4

- [X] T065 [US4] Extend `InsertionModalBloc`'s `ModalClosed` handler (placeholder from T017) to call `AudioCaptureRepository.discard()` if `state is InsertionModalAudioRecording` and clear `_pendingAudioPath`/`_pendingImagePath` — "the system MUST NOT create any entry, partial or empty, for that capture" (FR-008); the bloc itself is then disposed by `BlocProvider` as the sheet closes, with nothing further to do — depends on T041, T059
- [X] T066 [P] [US4] Extend `InsertionModalBloc` tests in `insertion_modal_bloc_test.dart` with abandonment scenarios across all three modalities: partially typed `InsertionModalTexto` + `ModalClosed` → no `CreateEntryUseCase` call, draft discarded; `ModalClosed` during `InsertionModalAudioRecording` → `discard()` called, no entry; `PhotoSourceSelected` cancelled or `ModalClosed` during `InsertionModalFotoCaptura` → no entry; re-confirm `TabSelected(<other>)` mid-recording (covered by T047) also produces zero entries — SC-002's "100% of abandoned captures... leave zero entries behind" — depends on T065
- [X] T067 [US4] Confirm `InsertionModalPage`'s `showModalBottomSheet` call (wired in T027) constructs a brand-new `BlocProvider<InsertionModalBloc>` on every open, so no tab selection, draft text, or sub-state survives a close-then-reopen cycle ("MUST reset every tab to its initial, empty state each time the modal is freshly opened" — FR-002) — depends on T027, T065

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: The constitution/quickstart gates that span every story above.

- [X] T068 [P] Run `fvm flutter analyze` and resolve any `always_use_package_imports`/lint findings under `lib/features/entries/` and `lib/features/capture/`
- [X] T069 [P] Run `test/architecture/domain_purity_test.dart` and confirm it still reports 0 violations with `lib/features/entries/domain/` and `lib/features/capture/domain/` included — no `package:flutter`, `record`, `image_picker`, or `whisper_ggml` type may appear in either `domain/` (RNF06)
- [X] T070 Run `fvm flutter test --coverage`, extract `lib/**/domain/**` via `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info`, and confirm ≥80% coverage with `lib/features/entries/domain/` and `lib/features/capture/domain/` included (RNF07)
- [ ] T071 Execute quickstart.md's manual verification on the iOS Simulator for Stories 1–4 and its Edge Cases: microphone/camera permission denial shows an explanatory message with no crash; tab-switch mid-recording discards the recording; the app backgrounded/killed mid-capture loses nothing because nothing was persisted, and the modal reopens empty; transcription/OCR succeeding with no usable text (silence / blank or illegible image) fails Save with a clear message rather than creating a near-empty entry, while a `low`-confidence-but-non-empty OCR result still proceeds normally (Clarification 3); airplane mode blocks Save immediately before any `entries-create`/`media-ocr` call is attempted (FR-010/SC-005); double-tapping "Salvar" on a slow connection creates exactly one entry

---

## Phase 8: Convergence

- [X] T072 Replace the three hardcoded pixel literals in `lib/features/capture/presentation/widgets/audio_waveform.dart` (`EdgeInsets.symmetric(horizontal: 2)`, `width: 4`, `height: 8 + normalized * 32`) with the existing `DesignTokens.spacingXs`/`spacingSm`/`spacingXl` constants (values 4/8/32 already defined in `lib/core/design_tokens.dart`) per Constitution Principle IV (contradicts)
- [X] T073 Fix `InsertionModalBloc.close()` in `lib/features/capture/presentation/bloc/insertion_modal_bloc.dart` to call `AudioCaptureRepository.discard()` (and clear `_pendingAudioPath`) whenever `state is InsertionModalAudioRecording` at disposal time, not only on an explicit `ModalClosed` event — `showModalBottomSheet`'s default swipe-down/tap-outside dismissal (used by `home_chat_shell_page.dart`'s `_openInsertionModal`) currently bypasses `ModalClosed` entirely, leaving the singleton `AudioCaptureRepository`'s native recorder active and able to break the next Áudio-tab recording attempt per FR-008 / US4 AC2 (partial)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup (T004's bundled model asset is read by US2's T034) — BLOCKS all user stories.
- **User Stories (Phase 3–6)**: All depend on Foundational completion.
  - US1 (P1) should be done first — it is the only story with no recognition dependency, and it is
    the one that first registers `InsertionModalBloc` in DI (T024) and adds the real "+" button
    (T027), which US2/US3 build on.
  - US2 (P1) and US3 (P2) each extend the same `InsertionModalBloc`/`insertion_modal_event.dart`/
    `insertion_modal_state.dart`/`insertion_modal_page.dart` files US1 touches (T041/T059 both
    extend the bloc's constructor; T045/T062 both extend the page's `BlocBuilder` switch) — doing
    them in priority order (US2 before US3) avoids rework, even though each is independently
    testable once done, per spec.md's own priority ordering (P1 before P2).
  - US4 (P3) depends on US2's and US3's `*Recording`/`*Saving`/`*Captura` states already existing
    to have something to abandon (T065 extends the same `ModalClosed` handler T017 stubbed).
- **Polish (Phase 7)**: Depends on all four stories being complete.

### Within Each User Story

- Domain entities/enums before repository interfaces; repository interfaces before data sources
  and usecases; usecases before bloc wiring; bloc wiring before the tab-view widget that reads it;
  DI registration before the "+"/tab-selection path that resolves the bloc from `get_it`.
- Tests are written alongside (and can be run immediately after) each implementation task, per the
  file pairing above, rather than strictly before — this project's F000/RF03 precedent write/extend
  the same test file across a story's tasks rather than one file per task.
- Story complete (domain + data + bloc + widget + tests) before moving to the next priority.

### Parallel Opportunities

- T002, T004 (Setup) in parallel with T001/T003 once each is independently actionable.
- T005, T013 (entities/connectivity) in parallel within Foundational; T015/T016/T018 (event/state/
  tab-bar skeletons) in parallel with each other and with the `entries` feature tasks.
- T008, T010, T012 (test files) can be written in parallel with each other once their respective
  implementation task lands.
- T020/T021 (US1 bloc event/state additions) in parallel with T022/T023 (US1 usecase + its test) —
  different files, both depend only on Foundational.
- T029/T030/T031 (US2 domain types) in parallel with each other; T048/T049 (US3 domain types) in
  parallel with each other.
- T036/T038 and T054/T056 (test files) in parallel with their respective sibling implementation
  task's dependents once that task lands.

---

## Parallel Example: Foundational Phase

```bash
# Launch independent entity/interface files together:
Task: "Create Entry entity + enums in lib/features/entries/domain/entities/entry.dart"
Task: "Create ConnectivityChecker in lib/core/network/connectivity_checker.dart"
Task: "Create CaptureTab enum + InsertionModalEvent base in lib/features/capture/presentation/bloc/insertion_modal_event.dart"
Task: "Create InsertionModalState base in lib/features/capture/presentation/bloc/insertion_modal_state.dart"
```

## Parallel Example: User Story 2 domain layer

```bash
Task: "Create RecognitionFailure sealed type in lib/features/capture/domain/entities/recognition_failure.dart"
Task: "Create AudioCaptureRepository interface in lib/features/capture/domain/repositories/audio_capture_repository.dart"
Task: "Create AudioTranscriptionRepository interface in lib/features/capture/domain/repositories/audio_transcription_repository.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
3. Complete Phase 3: User Story 1.
4. **STOP and VALIDATE**: tap "+", type text, tap "Salvar" — a new "manual" entry exists and the
   modal closes back to Home/Chat with no other visible change.

### Incremental Delivery

1. Setup + Foundational → the `entries` feature and modal shell exist (Texto-only skeleton).
2. Add US1 → text capture works end to end; the "+" button exists for the first time.
3. Add US2 → audio capture converges on the same entry format as text (the central acceptance
   criterion, SC-001).
4. Add US3 → photo capture converges on the same entry format too; all three modalities proven
   structurally identical.
5. Add US4 → the safety property that no modality ever leaves a partial/empty entry behind.
6. Polish → RNF06/07 gates + quickstart's full manual pass.

---

## Notes

- `insertion_modal_bloc.dart`, `insertion_modal_event.dart`, `insertion_modal_state.dart`, and
  `insertion_modal_page.dart` are each touched by multiple story phases (T017/T025/T041/T059/T065
  for the bloc; T015/T020/T040/T058 for events; T016/T021/T039/T057 for states; T019/T027/T045/T062
  for the page) — this is the deliberate single-screen/single-bloc shape contracts/
  insertion-modal-bloc.md chose (mirroring RF03's `VaultBloc`), not a same-file conflict to avoid.
- `AudioTranscriptionRepository.transcribe()` deliberately returns `Either<RecognitionFailure, T>`,
  **not** `Either<Failure, T>` — it has no network call and no corresponding backend code
  (research.md R7). `PhotoRecognitionRepository.recognize()`, by contrast, is a real network call
  and reuses the existing `Failure` hierarchy unchanged.
- No task in this list touches `docs/input/`, `docs/input/backend/api/openapi.yaml`, `.env`, RF02's
  (not-yet-built) dedicated recognition-state screens, or any of RF04–RF10's behavior — all
  explicitly out of scope (FR-012, FR-013).
- `OcrResult.confidence` is carried through the full pipeline (T049, T055) but never branched on
  anywhere, including in the UI (T061) — confidence-based quality gating is explicitly RF02's
  concern (Clarification 3).
