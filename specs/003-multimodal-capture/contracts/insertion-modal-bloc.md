# Contract: `InsertionModalBloc` (`lib/features/capture/presentation/bloc/`)

One screen-scoped bloc for the whole modal (same "one bloc per screen, flat sealed sub-states"
shape as `VaultBloc` — RF03 research.md R4), created fresh by `BlocProvider` every time
`showModalBottomSheet` opens the modal and disposed when it closes — which is what makes FR-002's
"reset every tab... each time the modal is freshly opened" true without an explicit reset event.

```dart
sealed class InsertionModalState extends Equatable {}

class InsertionModalTexto extends InsertionModalState { final String text; }
class InsertionModalTextoSaving extends InsertionModalState { final String text; }
class InsertionModalTextoFailure extends InsertionModalState { final String text; final String message; }

class InsertionModalAudioIdle extends InsertionModalState {}
class InsertionModalAudioPermissionDenied extends InsertionModalState {}
class InsertionModalAudioRecording extends InsertionModalState { final Duration elapsed; }
class InsertionModalAudioSaving extends InsertionModalState {}
class InsertionModalAudioFailure extends InsertionModalState { final String message; }

class InsertionModalFotoCaptura extends InsertionModalState {}
class InsertionModalFotoPermissionDenied extends InsertionModalState {}
class InsertionModalFotoSaving extends InsertionModalState {}
class InsertionModalFotoFailure extends InsertionModalState { final String message; }

sealed class InsertionModalEvent {}
class TabSelected extends InsertionModalEvent { final CaptureTab tab; }
class TextDraftChanged extends InsertionModalEvent { final String text; }
class SaveTextSubmitted extends InsertionModalEvent {}
class AudioStartRequested extends InsertionModalEvent {}
class AudioTimerTicked extends InsertionModalEvent {}          // internal, drives `elapsed` only
class AudioStopRequested extends InsertionModalEvent {}
class PhotoSourceSelected extends InsertionModalEvent { final PhotoSource source; }
class RetryRequested extends InsertionModalEvent {}
class ModalClosed extends InsertionModalEvent {}

enum CaptureTab { texto, audio, foto }
```

- **Initial state**: `const InsertionModalTexto(text: '')` — no `ModalOpened`/async-resolution
  event is needed (unlike `VaultBloc`'s `VaultOpened`, which has to await
  `DetermineVaultEntryUseCase` first); the Texto tab's default state is static and synchronous
  (FR-002).
- **`TabSelected(audio)`**: -> `InsertionModalAudioIdle()` unconditionally — a round start control
  with the "Toque para gravar" caption; no permission check and no recording yet (FR-004).
- **`AudioStartRequested`** (ignored unless `state is InsertionModalAudioIdle`): calls
  `AudioCaptureRepository.hasPermission()`; `false` -> `InsertionModalAudioPermissionDenied` (Edge
  Cases: explanatory message, no controls); `true` -> `AudioCaptureRepository.start()` ->
  `InsertionModalAudioRecording(elapsed: Duration.zero)`, and starts a local 1-second ticker that
  dispatches `AudioTimerTicked` to advance `elapsed` (the waveform's own visual animation reads
  `AudioCaptureRepository.amplitudeStream` directly, not through this bloc —
  contracts/audio-capture-repository.md).
- **`TabSelected(foto)`**: -> `InsertionModalFotoCaptura()` unconditionally (camera/gallery
  permission is requested per-button-tap by `image_picker` itself, not up front — Edge Cases'
  permission-denied message is shown by catching that attempt's resulting `null`/exception in
  `PhotoSourceSelected`'s handler, not by a pre-check here).
- **`TabSelected(texto)`**: -> `InsertionModalTexto(text: _textDraft)`, restoring whatever was
  typed before switching away (an ordinary tab-switch convenience, not itself FR-required, but
  consistent with FR-002 only mandating a reset on a *fresh modal open*, not on every tab
  revisit).
- **`TabSelected(<anything>)` while `InsertionModalAudioRecording`**: calls
  `AudioCaptureRepository.discard()` before transitioning to the target tab's state (Edge Cases:
  switching tabs mid-recording discards it).
- **`SaveTextSubmitted`** (ignored if `state is InsertionModalTextoSaving` — double-tap guard,
  Assumptions): `-> InsertionModalTextoSaving(text)` then awaits `SaveTextEntryUseCase(text)`;
  `Right(entry)` closes the modal (the page listens for this via `BlocListener`, pops the sheet);
  `Left(failure)` -> `InsertionModalTextoFailure(text, failure.message)`.
- **`AudioStopRequested`** (ignored unless `state is InsertionModalAudioRecording`): stops the
  ticker, calls `AudioCaptureRepository.stop()` to get the file path (stored in the bloc-private
  `_pendingAudioPath`), emits `InsertionModalAudioSaving()`, then awaits
  `SaveAudioEntryUseCase(path)` and maps its three-way failure (data-model.md's transition table)
  to `InsertionModalAudioFailure` with the matching message, or closes the modal on success.
- **`PhotoSourceSelected(source)`** (ignored if `state is InsertionModalFotoSaving`): calls
  `PhotoCaptureRepository.pickImage(source)`; `null` -> stays `InsertionModalFotoCaptura()`
  (cancelled); a path -> stores it in `_pendingImagePath`, emits `InsertionModalFotoSaving()`, then
  awaits `SavePhotoEntryUseCase(path)`, same failure-mapping shape as audio.
- **`RetryRequested`**: re-dispatches the same saving branch against whichever of
  `_pendingAudioPath`/`_pendingImagePath` is non-null for the tab the failure state belongs to — no
  re-recording, no re-picking (FR-009).
- **`ModalClosed`**: calls `AudioCaptureRepository.discard()` if a recording is in flight; the
  bloc is then disposed by `BlocProvider` as the sheet closes — nothing further to do (FR-008).
- **What the page does, not the bloc**: on any transition into a "success" condition (handled as a
  one-shot side effect, not a state — see `save-usecases.md`), `InsertionModalPage` is the one that
  calls `Navigator.pop` to close the sheet (FR-011: "the modal closes and return[s] the user to
  Home/Chat with no other visible change"). The bloc's own state never needs a dedicated
  `InsertionModalSuccess` case precisely because there is nothing to render for it — the sheet is
  simply gone.

## Who depends on this

`InsertionModalPage` and its three tab widgets (`TextoTabView`, `AudioTabView`, `FotoTabView`) —
each renders only the sub-states relevant to its own tab via `state is InsertionModal<Tab>*`
pattern matching, the same exhaustive-`switch` convention `VaultBloc`/`VaultPage` already use. The
waveform widget additionally reads `AudioCaptureRepository.amplitudeStream` via `get_it` directly
(the one sanctioned bypass of "always through the bloc," justified in
contracts/audio-capture-repository.md).
