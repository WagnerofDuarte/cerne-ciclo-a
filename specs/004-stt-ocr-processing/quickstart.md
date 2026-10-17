# Quickstart: P-RF02 — Speech-to-text / OCR processing

How to validate this unit end-to-end once implemented, mapped to spec.md's five user stories. A run guide,
not an implementation spec — interfaces are in `contracts/`, state/entities in `data-model.md`.

## Prerequisites

- RF01 already implemented and passing (`specs/003-multimodal-capture/`) — this unit edits, not replaces, its
  Insertion Modal, repositories, and data sources. No new package, no new native-project change, no new `.env`
  variable beyond what RF01 already required.
- The backend fixtures this unit specifically exercises:
  `docs/input/backend/fixtures/media/audio_fixture_01.wav` (reference transcript in
  `expected-transcription.md`), `media/ocr_fixture_01.png` (legible text → "Foto — Reconhecido"),
  `media/ocr_fixture_ilegivel.png` (illegible → "Foto — Erro"). Audio's own failure path has no dedicated
  fixture (spec.md Assumptions) — force it with a silent or corrupted recording instead.

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint (unchanged convention)
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html   # RNF07 gate — now covering recognize_photo_usecase.dart + confirm_entry_save_usecase.dart in place of the two deleted usecases
```

Key domain/bloc tests this unit's coverage depends on — contracts/recognition-and-save-usecases.md's table
has the full scenario list for `RecognizePhotoUseCase`, `ConfirmEntrySaveUseCase`, and `InsertionModalBloc`.
`AudioTranscriptionRepositoryImpl`/`PhotoRecognitionRepositoryImpl` tests are unchanged from RF01 (the
repositories themselves are untouched).

## Manual verification (device/Simulator — `whisper_ggml`/`image_picker` have no platform channel under `flutter_test`)

### Story 1 — Reviewing and saving a transcribed audio entry (P1)

1. Tap "+", switch to "Áudio", tap the start control, speak a short phrase, tap stop. **Expect**: "Áudio —
   Processando" — a spinner in place of the stop control, the waveform frozen and faded, "Transcrevendo...",
   the recorded duration — and the modal does **not** close yet.
2. Once transcription finishes. **Expect**: "Áudio — Transcrito" — the transcribed text in an editable
   field, the same duration, "Salvar" enabled. Still no entry created (check via a debug log/backend-side
   check that no `entries-create` call has happened yet).
3. Edit the text, tap "Salvar". **Expect**: exactly one entry created with `source: "audio"` and the *edited*
   text, not the original transcription; modal closes.
4. Repeat using `audio_fixture_01.wav` played into the Simulator's mic and compare the "Transcrito" text
   against `expected-transcription.md` before saving.
5. Confirm via a debug log that at no point during steps 1–3 was any network call made carrying audio bytes
   (FR-004) — only the final `entries-create` call, carrying text.

### Story 2 — Recovering from a failed transcription (P1)

1. Force a transcription failure (e.g., a silent or corrupted recording), stop. **Expect**: "Áudio — Erro" —
   red warning icon, "Não foi possível transcrever", outline "Tentar novamente" — no entry created.
2. Tap "Tentar novamente". **Expect**: back to "Áudio — Processando" against the *same* held audio — no new
   recording prompt.
3. From "Áudio — Erro", close the modal instead of retrying. **Expect**: no entry created, held audio
   discarded (confirm by reopening "+" → Áudio shows the idle "Toque para gravar" state, not a resumed Erro).

### Story 3 — Reviewing and saving a recognized photo entry (P2)

1. Tap "+", switch to "Foto", tap "Galeria", pick `ocr_fixture_01.png`. **Expect**: "Foto — Processando OCR"
   — thumbnail, spinner, "Reconhecendo texto..." — no entry yet.
2. Once OCR finishes. **Expect**: "Foto — Reconhecido" — the thumbnail next to the extracted editable text,
   "Salvar" enabled. Still no entry created.
3. Optionally edit the text, tap "Salvar". **Expect**: exactly one entry with `source: "photo"` and the
   current (possibly edited) text; modal closes.
4. Confirm via a debug log/backend-side check that the image itself was never persisted — only the one
   `media-ocr` call (with the base64 image) and the final `entries-create` call (text only) happened.

### Story 4 — Recovering from a failed photo recognition (P2)

1. Pick `ocr_fixture_ilegivel.png`. **Expect**: "Foto — Erro" — thumbnail kept, red warning icon, "Não foi
   possível reconhecer o texto", "Tentar novamente" and the secondary text action "Salvar só a foto" — no
   entry created yet.
2. Tap "Tentar novamente". **Expect**: back to "Foto — Processando OCR" against the same held image — no new
   picker call.
3. From "Foto — Erro" again, tap "Salvar só a foto" instead. **Expect**: exactly one entry created
   immediately with `source: "photo"` and the fixed placeholder content (non-empty) — confirm via a debug log
   that **no** further `media-ocr` call was made for this capture.
4. From a fresh "Foto — Erro", close the modal instead of choosing either action. **Expect**: no entry
   created, held image discarded.

### Story 5 — Abandoning mid-recognition or mid-review leaves nothing behind (P3)

1. Start a recording, stop it, and while "Áudio — Processando" is showing, immediately switch to "Foto".
   **Expect**: no entry created even once the (now-abandoned) transcription eventually resolves in the
   background — confirm via a debug log that no late `entries-create` call ever fires, and that returning to
   "Áudio" shows the idle state, not a stale "Transcrito"/"Erro".
2. Reach "Áudio — Transcrito", edit the text, then close the modal without tapping "Salvar". **Expect**: no
   entry created; reopening "+" shows a fresh, empty Áudio idle state.
3. Reach "Foto — Reconhecido", then switch to "Texto" instead of saving. **Expect**: no entry created; the
   picked image/recognized text is discarded (returning to "Foto" shows the two-button Captura state, not a
   resumed Reconhecido).

### Edge cases worth exercising manually at least once

- Edit "Áudio — Transcrito"'s or "Foto — Reconhecido"'s text down to only whitespace. **Expect**: "Salvar"
  becomes disabled immediately (<100 ms, RNF01) — confirm no entry can be created this way.
- Turn on airplane mode, then pick a legible image. **Expect**: "Foto — Processando OCR" resolves directly to
  "Foto — Erro" with a distinct offline-appropriate message (not the generic "Não foi possível reconhecer o
  texto") — confirm via a network log that no `media-ocr` call was even attempted.
- With audio still on-device-only, confirm transcription itself still runs in airplane mode (it must reach
  "Áudio — Transcrito" normally) — only the subsequent "Salvar" should be blocked by airplane mode, with its
  own offline message, keeping the transcribed text on screen for a retry once reconnected.
- Double-tap "Salvar" (from Transcrito/Reconhecido) and double-tap "Salvar só a foto" on a slow connection.
  **Expect**: exactly one entry each, never two.
- Tap "Tentar novamente" repeatedly in quick succession. **Expect**: only one recognition attempt runs; the
  repeat taps are no-ops (the state is already `*Processing`, not `*Failure`, once the first tap lands).
- Background the app (Simulator: Cmd+Shift+H) while "Áudio — Transcrito" is showing with unsaved edits, then
  foreground it again. **Expect**: the edited text and state resume normally (mere backgrounding, not a
  process kill). Force-kill and relaunch instead. **Expect**: cold launch re-enters via splash → vault →
  Home/Chat; the modal does not reopen in any partially-reviewed state.
