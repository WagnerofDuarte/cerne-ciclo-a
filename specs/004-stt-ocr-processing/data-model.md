# Data Model: P-RF02 — Speech-to-text / OCR processing

Source: spec.md §Key Entities, RF01's already-built `Entry`/`EntriesRepository`/`CreateEntryUseCase`
(unchanged), and `docs/input/backend/api/openapi.yaml`'s `/entries` and `/media/ocr` schemas (also
unchanged — this unit calls both functions with exactly the same request shapes RF01 already used). No new
backend-shaped entity. One ephemeral, device-only "entity" from spec.md's Key Entities — **Recognition
Attempt** — is modeled as presentation state, the same convention RF01 used for its own Capture Session.

## Entry / EntriesRepository / CreateEntryUseCase (unchanged)

Reused verbatim from `specs/003-multimodal-capture/data-model.md` — no field, no signature, no repository
behavior changes. The only thing this unit changes about *how* `CreateEntryUseCase` gets called is covered
below (`ConfirmEntrySaveUseCase`).

**Content sent for this unit's entries**:

| Path | `content` | `source` |
|---|---|---|
| Áudio — "Salvar" from Transcrito | the editable field's current text (possibly user-edited) | `audio` |
| Foto — "Salvar" from Reconhecido | the editable field's current text (possibly user-edited) | `photo` |
| Foto — "Salvar só a foto" from Erro | the fixed placeholder `'Foto registrada sem texto reconhecido.'` (research.md R3) | `photo` |

## Recognition Attempt (presentation-only state — not a domain entity, not persisted)

Spec.md's Key Entities names this as "ephemeral, device-only state tracking one in-progress or completed
transcription (audio) or OCR (photo) call for the capture currently open." As with RF01's Capture Session,
this lives entirely in `InsertionModalBloc`'s own state plus bloc-private fields — no other layer sees it.

| Held where | What | Lifetime |
|---|---|---|
| `InsertionModalState` (public, contracts/insertion-modal-bloc.md) | active tab + that tab's processing/reviewed/error/saving sub-state + the currently-editable reviewed text | One `InsertionModalBloc` instance per modal open — unchanged from RF01. |
| `_pendingAudioPath` (bloc-private `String?`) | The already-recorded WAV path, now held across the whole Processando→Transcrito→Salvar lifecycle (not just across a failure, as in RF01), so "Tentar novamente" and a final "Salvar" both act on the same file. Cleared on successful save, modal close, or switching away from Áudio. | Same as RF01, extended across more sub-states. |
| `_pendingImagePath` (bloc-private `String?`) | Same extension for the picked JPEG path — held across Processando OCR→Reconhecido/Erro→Salvar/"Salvar só a foto". | Same as above. |
| `_audioReviewText` / `_photoReviewText` (bloc-private `String?`) | The editable field's current draft while in Transcrito/Reconhecido (or SaveFailure), seeded from the recognition result and updated by `AudioReviewTextChanged`/`PhotoReviewTextChanged`. Discarded (never read again) once the capture is abandoned or saved. | Same lifetime as the pending path above. |

**Confidence**: `OcrResult.confidence` (`"high"`\|`"low"`, unchanged type from RF01) continues to be carried
through this state but never branched on, per spec.md's resolved Clarification 3 — identical treatment to
RF01's own precedent for the same field.

## `RecognizePhotoUseCase` (`lib/features/capture/domain/usecases/recognize_photo_usecase.dart` — NEW)

```dart
sealed class PhotoRecognitionAttemptFailure {}
class PhotoRecognitionOffline extends PhotoRecognitionAttemptFailure {}
class PhotoRecognitionCallFailed extends PhotoRecognitionAttemptFailure { final Failure failure; }

class RecognizePhotoUseCase {
  Future<Either<PhotoRecognitionAttemptFailure, OcrResult>> call(String imageFilePath) async {
    if (!await connectivityChecker.hasConnection()) return const Left(PhotoRecognitionOffline());
    final result = await recognitionRepository.recognize(imageFilePath);
    return result.match(
      (failure) => Left(PhotoRecognitionCallFailed(failure)),
      (ocrResult) => Right(ocrResult),
    );
  }
}
```

- Replaces the recognition half of RF01's `SavePhotoEntryUseCase` — the connectivity gate RF01 ran *before*
  OCR (research.md R5, specs/003) is preserved here, now scoped to exactly the OCR call it protects (the spec
  Edge Case "device offline when OCR would normally be attempted... MUST resolve to Foto — Erro with a clear,
  offline-appropriate message" — research.md R1 explains why audio's analogous check is removed instead).
- `PhotoRecognitionCallFailed(failure)` where `failure is OcrNoTextFailure` maps to the prototype's "Não foi
  possível reconhecer o texto" copy; any other `Failure` maps to `failure.message` — identical mapping logic
  to RF01's `_photoFailureMessage`, just relocated.
- No equivalent usecase exists for audio: `AudioTranscriptionRepository.transcribe()` is called directly by
  the bloc (research.md R1 removes the only orchestration step — the connectivity check — that would have
  justified wrapping it).

## `ConfirmEntrySaveUseCase` (`lib/features/capture/domain/usecases/confirm_entry_save_usecase.dart` — NEW, replaces `save_audio_entry_usecase.dart` + `save_photo_entry_usecase.dart`)

```dart
sealed class ConfirmEntrySaveFailure {}
class ConfirmEntrySaveOffline extends ConfirmEntrySaveFailure {}
class ConfirmEntrySaveCreationFailed extends ConfirmEntrySaveFailure { final Failure failure; }

class ConfirmEntrySaveUseCase {
  Future<Either<ConfirmEntrySaveFailure, Entry>> call(String content, EntrySource source) async {
    if (!await connectivityChecker.hasConnection()) return const Left(ConfirmEntrySaveOffline());
    final created = await createEntryUseCase(content, source);
    return created.match(
      (failure) => Left(ConfirmEntrySaveCreationFailed(failure)),
      (entry) => Right(entry),
    );
  }
}
```

- The one and only thing `InsertionModalBloc` calls for every explicit "Salvar"/"Salvar só a foto" trigger
  across all three tabs (Texto's own `SaveTextEntryUseCase` is untouched by this unit and keeps its separate,
  simpler shape — it never had a recognition step to remove).
- research.md R7 documents why this single class replaces RF01's two near-identical per-modality usecases.

## `InsertionModalState` — full shape after this unit (see contracts/insertion-modal-bloc.md for the event-by-event contract)

```dart
// Texto — entirely unchanged (FR-012: this unit does not touch it)
class InsertionModalTexto { final String text; }
class InsertionModalTextoSaving { final String text; }
class InsertionModalTextoFailure { final String text; final String message; }

// Áudio
class InsertionModalAudioIdle {}                                          // unchanged
class InsertionModalAudioPermissionDenied {}                              // unchanged
class InsertionModalAudioRecording { final Duration elapsed; }            // unchanged
class InsertionModalAudioProcessing { final Duration duration; }          // NEW — "Áudio — Processando"
class InsertionModalAudioTranscribed { final String text; final Duration duration; }   // NEW — "Áudio — Transcrito"
class InsertionModalAudioSaving { final String text; final Duration duration; }        // REPURPOSED — entries-create in flight
class InsertionModalAudioSaveFailure { final String text; final Duration duration; final String message; }  // NEW (research.md R5)
class InsertionModalAudioFailure { final Duration duration; final String message; }     // REPURPOSED — transcription failed only

// Foto
class InsertionModalFotoCaptura {}                                        // unchanged
class InsertionModalFotoPermissionDenied {}                               // unchanged
class InsertionModalFotoProcessing { final String imagePath; }            // NEW — "Foto — Processando OCR"
class InsertionModalFotoReconhecido { final String imagePath; final String text; }      // NEW — "Foto — Reconhecido"
class InsertionModalFotoSaving { final String imagePath; final String text; }           // REPURPOSED — entries-create in flight (normal Salvar or Salvar só a foto)
class InsertionModalFotoSaveFailure { final String imagePath; final String text; final String message; }  // NEW (research.md R5)
class InsertionModalFotoFailure { final String imagePath; final String message; }       // REPURPOSED — OCR failed only
```

`InsertionModalAudioSaving`/`InsertionModalFotoSaving` and `InsertionModalAudioFailure`/
`InsertionModalFotoFailure` keep their RF01 class names but narrow their meaning now that recognition and save
are separate steps — there is no ambiguity at any call site about which phase a given state instance
represents, since each now carries only the data relevant to its narrower phase.

## `InsertionModalEvent` — additions

```dart
class AudioReviewTextChanged extends InsertionModalEvent { final String text; }   // NEW
class AudioSaveConfirmed extends InsertionModalEvent {}                           // NEW — "Salvar" from Transcrito/AudioSaveFailure
class PhotoReviewTextChanged extends InsertionModalEvent { final String text; }   // NEW
class PhotoSaveConfirmed extends InsertionModalEvent {}                          // NEW — "Salvar" from Reconhecido/FotoSaveFailure
class PhotoSaveWithoutTextRequested extends InsertionModalEvent {}               // NEW — "Salvar só a foto" from Foto — Erro
```

`RetryRequested`, `AudioStopRequested`, `PhotoSourceSelected`, `TabSelected`, `ModalClosed` are reused
unchanged in shape; only their handlers' internal behavior changes (contracts/insertion-modal-bloc.md).

## State transitions (per modality)

```
[Áudio tab]
  AudioStopRequested (from InsertionModalAudioRecording)
    -> path = AudioCaptureRepository.stop(); _pendingAudioPath = path; duration = elapsed at stop
    -> InsertionModalAudioProcessing(duration)                                           # FR-001 — no connectivity gate (research.md R1)
        AudioTranscriptionRepository.transcribe(path)
            [state still AudioProcessing for this path — else discard, research.md R6]
            Left(EmptyRecognitionResult())  -> InsertionModalAudioFailure(duration, noSpeechMessage)
            Left(TranscriptionError())      -> InsertionModalAudioFailure(duration, genericMessage)
            Right(text) -> _audioReviewText = text; InsertionModalAudioTranscribed(text, duration)  # FR-002 — no entry yet

  AudioReviewTextChanged(text) (from InsertionModalAudioTranscribed | InsertionModalAudioSaveFailure)
    -> _audioReviewText = text; re-emit the same state class with the updated text

  AudioSaveConfirmed (from InsertionModalAudioTranscribed | InsertionModalAudioSaveFailure; text non-empty, not already saving)
    -> InsertionModalAudioSaving(_audioReviewText, duration)
        ConfirmEntrySaveUseCase(_audioReviewText, EntrySource.audio)
            Right(entry) -> cached; _pendingAudioPath cleared; modal closes                         (FR-010)
            Left(ConfirmEntrySaveOffline())        -> InsertionModalAudioSaveFailure(text, duration, offlineMessage)
            Left(ConfirmEntrySaveCreationFailed(f)) -> InsertionModalAudioSaveFailure(text, duration, f.message)

  RetryRequested (from InsertionModalAudioFailure, _pendingAudioPath != null)
    -> InsertionModalAudioProcessing(duration); re-run the transcribe branch above against the same path  (FR-003)

  TabSelected(<anything else>) | ModalClosed, from any Áudio sub-state beyond Idle/Recording
    -> _pendingAudioPath = null; _audioReviewText = null; target state emitted (or bloc disposed)    (FR-011)

[Foto tab]
  PhotoSourceSelected(source) -> path = PhotoCaptureRepository.pickImage(source)
    null (cancelled) -> stays InsertionModalFotoCaptura()
    path -> _pendingImagePath = path; InsertionModalFotoProcessing(path)                               # FR-005
        RecognizePhotoUseCase(path)
            [state still FotoProcessing for this path — else discard, research.md R6]
            Left(PhotoRecognitionOffline())            -> InsertionModalFotoFailure(path, offlineMessage)
            Left(PhotoRecognitionCallFailed(f)) where f is OcrNoTextFailure -> InsertionModalFotoFailure(path, noTextMessage)
            Left(PhotoRecognitionCallFailed(f))        -> InsertionModalFotoFailure(path, f.message)
            Right(ocrResult) [confidence ignored — Clarification 3]
                -> _photoReviewText = ocrResult.text; InsertionModalFotoReconhecido(path, ocrResult.text)  # FR-006 — no entry yet

  PhotoReviewTextChanged(text) (from InsertionModalFotoReconhecido | InsertionModalFotoSaveFailure)
    -> _photoReviewText = text; re-emit the same state class with the updated text

  PhotoSaveConfirmed (from InsertionModalFotoReconhecido | InsertionModalFotoSaveFailure; text non-empty, not already saving)
    -> InsertionModalFotoSaving(path, _photoReviewText)
        ConfirmEntrySaveUseCase(_photoReviewText, EntrySource.photo)
            Right(entry) -> cached; _pendingImagePath cleared; modal closes                           (FR-010)
            Left(ConfirmEntrySaveOffline())        -> InsertionModalFotoSaveFailure(path, text, offlineMessage)
            Left(ConfirmEntrySaveCreationFailed(f)) -> InsertionModalFotoSaveFailure(path, text, f.message)

  PhotoSaveWithoutTextRequested (from InsertionModalFotoFailure; no further OCR attempt — FR-008)
    -> InsertionModalFotoSaving(path, _photoNoTextPlaceholder)
        ConfirmEntrySaveUseCase(_photoNoTextPlaceholder, EntrySource.photo)
            Right(entry) -> cached; _pendingImagePath cleared; modal closes
            Left(...) -> InsertionModalFotoSaveFailure(path, _photoNoTextPlaceholder, message)

  RetryRequested (from InsertionModalFotoFailure, _pendingImagePath != null)
    -> InsertionModalFotoProcessing(path); re-run the recognize branch above against the same path   (FR-007)

  TabSelected(<anything else>) | ModalClosed, from any Foto sub-state beyond Idle/Captura
    -> _pendingImagePath = null; _photoReviewText = null; target state emitted (or bloc disposed)     (FR-011)
```

## Backend `Failure` (reused) vs. local-only failure shapes

| Type | Return type | Why |
|---|---|---|
| `RecognizePhotoUseCase.call()` | `Either<PhotoRecognitionAttemptFailure, OcrResult>` | `PhotoRecognitionAttemptFailure` is a new, small local sealed type distinguishing "never called `media-ocr`" (offline) from "the call itself failed" (wraps the existing, unmodified `Failure`) — same shape of decision RF01's research.md R7 (specs/003) already made for its own local-only types. |
| `ConfirmEntrySaveUseCase.call()` | `Either<ConfirmEntrySaveFailure, Entry>` | Same pattern, for the shared save step. |
| `AudioTranscriptionRepository.transcribe()` | `Either<RecognitionFailure, String>` | Unchanged from RF01 — on-device only, no network call, no connectivity concept applies at all (research.md R1). |

No new entry is added to `core/network/failure.dart` itself — `OcrNoTextFailure`/`OCR_NO_TEXT` (present since
F000) still covers the illegible/blank-image case exactly, unchanged. RNF09's running scenario count is
unaffected by this unit (still 6/15, cumulative from RF01 — plan.md's Constitution Check).

## Design Tokens (`lib/core/design_tokens.dart`)

Two additions — research.md R2:

```dart
static const double sizePhotoThumbnail = 64;
static const double sizeStatusIcon = 32;
```

Every other value the new states need (`colorError` for the icon/copy, `colorBorder`/`colorSurfaceElevated`
for the outline "Tentar novamente" button, the existing type scale for "Transcrevendo..."/"Reconhecendo
texto..." captions, `sizeLoadingIndicator`/`strokeWidthLoadingIndicator` for the spinner, `Opacity(0.35)` for
the frozen waveform per RF01's research.md R10) is reused unchanged.
