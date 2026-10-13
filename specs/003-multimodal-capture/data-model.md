# Data Model: P-RF01 — Multimodal capture

Source: spec.md §Key Entities, requirements.md §§1, 6.2, 9 (data model reference), §13, and
`docs/input/backend/api/openapi.yaml`'s `/entries` and `/media/ocr` schemas. This unit introduces
one new backend-shaped entity (`Entry`, read from a contract the backend already defines — no
schema change) and one ephemeral, device-only, non-persisted "entity" (Capture Session, modeled as
presentation state, not a domain type — see research.md R8 for why `Entry`/`EntriesRepository`
live in a new `entries` feature, separate from `capture`).

## Entry (`lib/features/entries/domain/entities/entry.dart`)

The full shape of `POST /entries`' response — every field below is `required` in the OpenAPI
schema on every response, so none is optional to model (research.md R8).

| Field | Type | Notes |
|---|---|---|
| `id` | `String` (uuid) | Server-assigned. |
| `content` | `String` | 1–20000 chars; the text this unit always supplies non-empty (FR-003/Edge Cases — never an empty/near-empty entry). |
| `source` | `EntrySource` | `manual` \| `audio` \| `photo` for this unit (see below — `chat` is RF10's addition). |
| `chatMessageId` | `String?` (uuid) | Always `null` for every entry this unit creates. |
| `occurredAt` | `DateTime` | Server-assigned; this unit never sends its own value in the request. |
| `tags` | `List<EntryTag>` | Always empty for a freshly created entry (tags are the manual-tagging extension, out of scope — requirements.md §2); modeled so later units reading an `Entry` don't need a second type. |
| `piiStatus` | `PiiStatus` (`pending`\|`clean`\|`flagged`\|`failed`) | Backend-computed; this unit does not branch on it. |
| `piiSpans` | `List<PiiSpan>` | As returned; not rendered by this unit. |
| `embeddingStatus` | `EmbeddingStatus` (`pending`\|`ready`\|`failed`) | Backend-computed; not rendered by this unit. |
| `mediaDurationSeconds` | `int?` | This unit never sends it in the request, so it is always `null` on the response to an entry this unit creates. |
| `serverRevision` | `int` | Opaque; not used by this unit. |
| `createdAt` | `DateTime` | — |
| `updatedAt` | `DateTime` | — |

```dart
enum EntrySource { manual, audio, photo }         // `chat` added by RF10, not here (research.md R8)
enum PiiStatus { pending, clean, flagged, failed }
enum EmbeddingStatus { pending, ready, failed }

class EntryTag { final String id; final String name; }
class PiiSpan { final int start; final int end; final String type; }
```

**Validation rule**: `content` is never sent empty or whitespace-only — enforced before any of the
three save usecases ever calls `CreateEntryUseCase` (Texto: the "Salvar" action is itself disabled
on an empty field, FR-003; Audio/Photo: an empty/whitespace recognized result is treated as a
recognition failure, not forwarded to entry creation — Edge Cases).

## `EntriesRepository` (`lib/features/entries/domain/repositories/entries_repository.dart`)

```dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({required String content, required EntrySource source});
  List<Entry> get cachedEntries;   // FR-011's "local entries store/cache" — in-memory, this process's lifetime
}
```

- `create()` posts to `entries-create` via the existing, unmodified `ApiClient`/`Failure` hierarchy
  — no new `Failure` subtype (every backend error this call can realistically return —
  `VALIDATION_ERROR`, `PII_CHECK_FAILED`, `EMBEDDING_FAILED`, `NETWORK_TIMEOUT`,
  `NETWORK_OFFLINE`, `RATE_LIMITED` — already exists in `core/network/failure.dart`).
- `EntriesRepositoryImpl` is registered as a `get_it` `lazySingleton` (the same pattern
  `VaultRepository` uses for its own in-memory, process-lifetime state — RF03 research.md R3) so
  `cachedEntries` survives across modal opens/closes without a local database. On a successful
  `create()`, the returned `Entry` is appended to this in-memory list before the `Either` is
  returned to the caller. Nothing in this unit ever *reads* `cachedEntries` back out for display —
  it exists purely so RF07 (the first unit that reads entries for a screen) has something to read
  from day one, per FR-011's explicit forward reference to "Meus Registros, RF07."

## `CreateEntryUseCase` (`lib/features/entries/domain/usecases/create_entry_usecase.dart`)

```dart
class CreateEntryUseCase {
  Future<Either<Failure, Entry>> call(String content, EntrySource source) =>
      repository.create(content: content, source: source);
}
```

The one and only sanctioned way any other feature creates an entry (research.md R8) — `capture`'s
three save usecases below depend on this, never on `EntriesRepository` directly.

## Capture Session (presentation-only state — not a domain entity, not persisted)

Spec.md's Key Entities names this as "ephemeral, device-only state that exists only while the
Insertion Modal is open" — in this codebase's existing convention (mirrors RF03's "Presentation-
only state" section: `VaultMode`, the in-progress first PIN entry), this is `InsertionModalBloc`'s
own state plus two bloc-private fields, not a type any other layer sees:

| Held where | What | Lifetime |
|---|---|---|
| `InsertionModalState` (public, see contracts/insertion-modal-bloc.md) | active tab + that tab's own idle/recording/saving/failure sub-state + the Texto draft text | One `InsertionModalBloc` instance per modal open; discarded (never persisted) when the modal closes, satisfying FR-002's "reset every tab... each time the modal is freshly opened" by construction — a fresh bloc is created on every `showModalBottomSheet` call. |
| `_pendingAudioPath` (bloc-private `String?`) | The WAV file path `AudioCaptureRepository` wrote to, kept only so a failed transcribe-or-save can retry (FR-009) without re-recording. Cleared on successful save, on modal close, or on switching away from the Áudio tab (Edge Cases: switching tabs mid-recording discards it). | Same as above. |
| `_pendingImagePath` (bloc-private `String?`) | The JPEG file path `PhotoCaptureRepository` returned, kept for the same FR-009 retry-without-recapture reason. | Same as above. |

No field here is ever written to disk or to the backend as its own record — only a *successful*
recognition's resulting text ever becomes part of an `Entry` via `CreateEntryUseCase`.

## State transitions (per modality, per research.md R6: "confirming Save" is a different trigger each time)

```
Modal opens (showModalBottomSheet, fresh InsertionModalBloc)
  -> InsertionModalTexto(text: '')                              # FR-002 default tab

[Texto tab]
  TextDraftChanged(text) -> InsertionModalTexto(text)            # Salvar enabled iff text.trim().isNotEmpty (FR-003)
  SaveTextSubmitted (text non-empty, not already in flight)
    -> InsertionModalTextoSaving(text)
        ConnectivityChecker.hasConnection() == false -> InsertionModalTextoFailure(text, offlineMessage)   (FR-010)
        CreateEntryUseCase(text, manual)
            Right(entry)  -> entry appended to EntriesRepository.cachedEntries -> modal closes (FR-011)
            Left(failure) -> InsertionModalTextoFailure(text, failure.message)                              (FR-009)

[Áudio tab — opens idle; recording starts only once the user taps the start control, FR-004]
  TabSelected(audio) -> InsertionModalAudioIdle()                                                # round start control, "Toque para gravar", no permission check yet
  AudioStartRequested (from InsertionModalAudioIdle)
    -> AudioCaptureRepository.hasPermission() == false -> InsertionModalAudioPermissionDenied
    -> else: AudioCaptureRepository.start() -> InsertionModalAudioRecording(elapsed: 0:00)      # waveform widget subscribes directly to the amplitude stream (research.md R6/contracts)
  (timer ticks update `elapsed` only — no network, no recognition yet)
  AudioStopRequested
    -> path = AudioCaptureRepository.stop(); _pendingAudioPath = path
    -> InsertionModalAudioSaving()                                                               # plain generic loading indicator (FR-007)
        ConnectivityChecker.hasConnection() == false -> InsertionModalAudioFailure(offlineMessage)   (FR-010 — checked before transcribing at all, research.md R5)
        AudioTranscriptionRepository.transcribe(path, lang: 'pt')
            Left(EmptyRecognitionResult()) -> InsertionModalAudioFailure(noSpeechMessage)   (Edge Cases: silence — the repository itself guarantees this, never Right(''))
            Left(TranscriptionError())     -> InsertionModalAudioFailure(genericMessage)     (FR-009)
            Right(text) -> CreateEntryUseCase(text, audio)
                Right(entry) -> cached; _pendingAudioPath cleared; modal closes
                Left(failure) -> InsertionModalAudioFailure(failure.message)     # audio file still held — RetryRequested re-enters AudioStopRequested's saving branch without a fresh recording
  RetryRequested (from InsertionModalAudioFailure, _pendingAudioPath != null)
    -> re-run the InsertionModalAudioSaving branch above against the same _pendingAudioPath
  TabSelected(<anything else>) while InsertionModalAudioRecording
    -> AudioCaptureRepository.discard(); _pendingAudioPath = null; emit the target tab's idle state   (Edge Cases)

[Foto tab]
  TabSelected(photo) -> InsertionModalFotoCaptura()                                               # two buttons, no image yet (FR-005)
  PhotoSourceSelected(camera | gallery)
    -> PhotoCaptureRepository.pickImage(source)
        null (user cancelled the OS picker) -> stays InsertionModalFotoCaptura()                   (Edge Cases/User Story 4)
        path -> _pendingImagePath = path; InsertionModalFotoSaving()                                # plain generic loading indicator (FR-007)
            ConnectivityChecker.hasConnection() == false -> InsertionModalFotoFailure(offlineMessage)   (FR-010)
            PhotoRecognitionRepository.recognize(path)
                Left(OcrNoTextFailure) -> InsertionModalFotoFailure(noTextMessage)   (Edge Cases: illegible/blank image — the repository normalizes a blank-text 200 response to this same failure, never Right(''))
                Left(otherFailure) -> InsertionModalFotoFailure(failure.message)
                Right(text) [confidence ignored — Clarification 3] -> CreateEntryUseCase(text, photo)
                    Right(entry) -> cached; _pendingImagePath cleared; modal closes
                    Left(failure) -> InsertionModalFotoFailure(failure.message)   # image still held — RetryRequested re-enters this branch
  RetryRequested (from InsertionModalFotoFailure, _pendingImagePath != null)
    -> re-run the recognize+create branch above against the same _pendingImagePath

[Any tab, any sub-state] ModalClosed (close button, scrim tap, system back)
  -> AudioCaptureRepository.discard() if a recording is in progress; bloc disposed; nothing persisted  (FR-008, User Story 4)
```

## Backend `Failure` (reused, not redefined) vs. the new local `RecognitionFailure`

| Repository | Return type | Why |
|---|---|---|
| `EntriesRepository.create()` | `Either<Failure, Entry>` | Real network call; reuses F000's closed 13-code hierarchy unchanged. |
| `PhotoRecognitionRepository.recognize()` | `Either<Failure, OcrResult>` | Real network call to `media-ocr`; `OcrNoTextFailure`/`OCR_NO_TEXT` already exists in `failure.dart` from F000 and covers the illegible/blank-image Edge Case directly. |
| `AudioTranscriptionRepository.transcribe()` | `Either<RecognitionFailure, String>` | On-device only, no network call — `RecognitionFailure` (`emptyResult`\|`transcriptionError`) is a new, small sealed type local to `capture/domain/`, not added to `core/network/failure.dart` (research.md R7). |

Three write-endpoint failure scenarios this unit's own `mocktail` tests cover, toward RNF09's
running 15-scenario total (`entries-create` and `media-ocr` are two of the spec's five write
endpoints):

| Endpoint | Scenario | Expected `Failure` |
|---|---|---|
| `entries-create` | Timeout / No connection / Malformed response | `NetworkTimeoutFailure` / `NetworkOfflineFailure` / `ValidationFailure` |
| `media-ocr` | Timeout / No connection / Malformed response | `NetworkTimeoutFailure` / `NetworkOfflineFailure` / `ValidationFailure` |

## Design Tokens (`lib/core/design_tokens.dart`)

No additions — see research.md R10. Every value the three tabs need (primary/outline/text
buttons, text field states, `colorError`, `sizeLoadingIndicator`/`strokeWidthLoadingIndicator`,
spacing, radii, type scale) already exists from F000/RF03.
