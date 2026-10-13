# Quickstart: P-RF01 — Multimodal capture

How to validate this unit end-to-end once implemented, mapped to spec.md's four user stories. A
run guide, not an implementation spec — interfaces are in `contracts/`, state/entities in
`data-model.md`.

## Prerequisites

- F000 and RF03 already implemented and passing (`specs/001-foundation/`,
  `specs/002-biometric-auth-vault/`) — this unit builds on their `ApiClient`/`Failure`/routing/DI
  and reaches Home/Chat the same way those units' quickstarts do (sign up or log in, pass the
  vault).
- `fvm flutter pub get` after `record`, `image_picker`, `whisper_ggml`, `connectivity_plus`, and
  `path_provider` are added to `pubspec.yaml` (research.md R1–R5).
- `ios/Runner/Info.plist` contains `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, and
  `NSPhotoLibraryUsageDescription` (research.md R1/R3) — without these, the first attempt to
  record or pick an image crashes immediately on-device/Simulator rather than merely failing.
- `IPHONEOS_DEPLOYMENT_TARGET` raised to `15.6` in all three `ios/Runner.xcodeproj/project.pbxproj`
  configurations (research.md R2 — `whisper_ggml`'s documented minimum).
- The bundled Whisper `tiny` model asset is present under the project's assets and declared in
  `pubspec.yaml` (research.md R2) — without it, the first audio Save hangs or errors on the
  one-time model copy step rather than transcribing.
- A `.env` with valid `FUNCTIONS_BASE_URL`/`SUPABASE_ANON_KEY` — every Save (all three modalities)
  calls the backend at least once (`entries-create`; audio/photo also call `media-ocr` for photo,
  or only `entries-create` for audio since transcription itself is local).
- The backend fixtures are useful for manual verification:
  `docs/input/backend/fixtures/media/audio_fixture_01.wav` (expected transcript in
  `expected-transcription.md`), `media/ocr_fixture_01.png` (legible text), `media/ocr_fixture_ilegivel.png`
  (illegible — exercises the no-usable-text Edge Case).

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint (always_use_package_imports)
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html   # RNF07 gate — now including lib/features/entries/domain, lib/features/capture/domain
```

Key domain tests this unit's coverage depends on (contracts/*.md):
- `SaveTextEntryUseCase`/`SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` against fake repositories:
  offline short-circuit, recognition failure, empty-result, entry-creation failure, and the happy
  path, for each modality.
- `EntriesRepositoryImpl`: the 3 failure scenarios (timeout/offline/malformed) for `entries-create`,
  plus the cache-append-on-success behavior.
- `PhotoRecognitionRepositoryImpl`: the same 3 scenarios for `media-ocr`, plus `OCR_NO_TEXT` and
  the client-side empty-text guard (contracts/photo-capture-repository.md).
- `AudioTranscriptionRepositoryImpl`/its fake: empty/whitespace transcript -> `EmptyRecognitionResult`.
- `InsertionModalBloc`: tab-switch resets, mid-recording tab-switch discard, double-tap-save
  ignored while already saving, retry re-using the held file path without a fresh
  recording/picker call.

## Manual verification (device/Simulator — `record`/`image_picker`/`whisper_ggml` have no platform
channel under `flutter_test`)

### Story 1 — Text entry (P1)

1. From Home/Chat, tap "+". **Expect**: the modal rises as an overlay (Home/Chat visible/dimmed
   underneath), Texto tab active, empty field, "Salvar" disabled.
2. Type a short note. **Expect**: "Salvar" becomes enabled the moment the field is non-empty.
3. Tap "Salvar". **Expect**: a brief plain loading indicator if the call takes >300 ms (RNF01),
   then the modal closes back to Home/Chat with no other visible change (FR-011).
4. Confirm via a debug log of the request (or a backend-side check) that `POST entries-create` was
   called with `source: "manual"` and the typed content.

### Story 2 — Audio entry (P1)

1. Tap "+", switch to "Áudio". **Expect**: an idle state — a round start control with the caption
   "Toque para gravar" — no recording yet. Tap the start control. **Expect**: stop button, animated
   waveform, running `mm:ss` timer.
2. Speak a short phrase, tap stop. **Expect**: a plain loading indicator (not a styled
   "Transcrevendo..." screen, not an editable-text review step — FR-007), then the modal closes.
3. Confirm the created entry's content matches what was said and `source: "audio"`.
4. Repeat using `audio_fixture_01.wav` played into the Simulator's mic (or injected directly into
   `AudioCaptureRepository` in a debug harness) and compare the resulting entry's content against
   `expected-transcription.md`.
5. **Failure path**: force a network failure (airplane mode) after stopping a recording. **Expect**:
   no entry created, a plain failure message, and a retry action that re-attempts without asking to
   re-record (FR-009/SC-004) — confirm by restoring connectivity and tapping retry, which succeeds
   using the same already-recorded audio.

### Story 3 — Photo entry (P2)

1. Tap "+", switch to "Foto". **Expect**: two buttons, "Câmera" and "Galeria", no image yet.
2. Tap "Galeria", pick `ocr_fixture_01.png` (or any image with legible text) from the Simulator's
   photo library (seed it via `xcrun simctl addmedia` beforehand if needed). **Expect**: a plain
   loading indicator, then the modal closes.
3. Confirm the created entry's content is the image's recognized text and `source: "photo"`.
4. Repeat with `ocr_fixture_ilegivel.png`. **Expect**: no entry created, a plain failure message
   (not the prototype's styled "Foto — Erro" screen, and no "Salvar só a foto" action — research.md
   R11), with a retry action that re-attempts OCR on the same already-picked image.
5. Tap "Câmera" instead and cancel the system camera UI without taking a photo. **Expect**: stays
   on the two-button Captura state, no entry created.

### Story 4 — Abandoning a capture (P3)

1. Type partial text in Texto, tap the modal's close ("x"). **Expect**: no entry created.
2. Switch to Áudio, tap the start control to begin recording, then close the modal before tapping
   stop. **Expect**: no entry created, no leftover audio file persisted as an entry.
3. Start a recording, switch to Foto mid-recording. **Expect**: the recording is discarded (Edge
   Cases); Foto shows its normal two-button Captura state, not an error about audio.
4. Open the Foto tab, tap "Galeria", cancel the picker. **Expect**: no entry created.

### Edge cases worth exercising manually at least once

- Deny microphone permission at the OS level (Simulator: Settings → Privacy → Microphone → off for
  the app), open the Áudio tab, and tap the start control. **Expect**: an explanatory message in
  place of the recording controls, no crash.
- Deny camera permission, tap "Câmera". **Expect**: an explanatory message, no crash; "Galeria"
  still works independently.
- Turn on airplane mode, open the Texto tab, type something, tap "Salvar". **Expect**: blocked
  immediately with a clear message — confirm via a network log that no `entries-create` call was
  even attempted (FR-010/SC-005), not just that it failed.
- Double-tap "Salvar" quickly on a slow connection. **Expect**: exactly one entry is created, not
  two.
- Background the app mid-recording (Simulator: Cmd+Shift+H), then relaunch. **Expect**: cold launch
  re-enters the app's normal routing (splash → vault → Home/Chat); the modal is not reopened in any
  partially-recorded state — nothing was persisted.
