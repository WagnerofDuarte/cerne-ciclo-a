# Research: P-RF01 — Multimodal capture

F000's research.md left "local cache" open generically and named no package for audio/photo
capture at all (neither existed as a concern yet); RF03's research.md R1 already set the precedent
for how this project treats a package that isn't in Principle II's explicit list but is needed to
implement a literal FR. This file resolves every such choice RF01 needs, plus the one structural
decision (R8) that reconciles this unit's scope with RF10's forward-looking wording in
`requirements.md`.

## R1 — Audio recording package

- **Decision**: `record` (`AudioRecorder`), configured with `RecordConfig(encoder:
  AudioEncoder.wav, sampleRate: 16000, numChannels: 1)`.
- **Rationale**: FR-004 needs a start/stop recorder plus a live amplitude signal to drive the
  prototype's "animated 12-bar waveform" (prototype-extract.md §2.3); `record` is the de-facto
  standard Flutter recording plugin (it backs `waveform_recorder` and similar higher-level widgets)
  and exposes both `start`/`stop` and `onAmplitudeChanged(Duration)` directly. Recording straight to
  16 kHz mono WAV — rather than the plugin's AAC/`m4a` default — means the file hitting
  `whisper_ggml` (R2) never needs its bundled FFmpeg conversion step, matching the exact format of
  the backend's own test fixture (`docs/input/backend/fixtures/media/audio_fixture_01.wav`) and
  keeping the record→transcribe path format-deterministic end to end.
- **Alternatives considered**: `flutter_sound` — a larger, more general-purpose audio toolkit
  (playback, streaming, effects) where this unit only ever needs record+stop+amplitude; rejected as
  more surface than the requirement calls for. Recording in the default AAC encoder and relying on
  `whisper_ggml`'s bundled FFmpeg to convert — rejected as an avoidable extra step and a dependency
  on an implicit, undocumented-in-this-project conversion path when the recorder can just emit the
  target format directly.
- **Permission handling**: `record`'s own `AudioRecorder.hasPermission()` requests the OS
  microphone permission itself (no separate `permission_handler` dependency needed). A `false`
  result, or recording start throwing on a since-revoked permission, is what the Audio tab's
  permission-denied explanatory message (Edge Cases) reacts to.
- **Native project note**: requires `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist` —
  the App Store requires this string before any mic access is even attempted, mirroring how RF03
  added `NSFaceIDUsageDescription` for `local_auth` (research.md R1 there).

## R2 — On-device transcription package

- **Decision**: `whisper_ggml` (Constitution Principle II — fixed, not a choice), using
  `WhisperController.transcribe(model: WhisperModel.tiny, audioPath: ..., lang: 'pt')` against the
  WAV file R1 produces. The `ggml-tiny` model (quantized `q5_1` variant preferred for size) ships as
  a bundled Flutter asset — copied once, on first use, to a writable app-support directory (via
  `path_provider`) because the plugin's native loader needs a filesystem path, not an asset handle —
  rather than downloaded over the network on first launch.
- **Rationale**: Principle II names `whisper_ggml` outright, so the only open questions are model
  size/delivery and language. Bundling the model keeps transcription fully on-device and
  network-independent from first launch, consistent with "audio content MUST NEVER be sent to the
  backend" (Principle II) and with this unit's own offline-write boundary (R5) — a model that had
  to be *downloaded* before the first transcription would make an on-device feature secretly
  depend on connectivity, undermining the reason it's on-device at all. `lang: 'pt'` is set
  explicitly because every UI string and the backend's fixture audio (`expected-transcription.md`)
  are Portuguese, and Whisper's multilingual `tiny` model supports it directly — no language
  auto-detection step is needed or wanted here.
- **Alternatives considered**: Auto-downloading the model from the package's own CDN on first
  launch — rejected per the rationale above. A larger model (`base`/`small`) — rejected as an
  unrequested accuracy/size trade-off the spec never asks for; `tiny` is the package's own
  documented fast/good-accuracy recommendation and keeps the app bundle smaller.
- **Native project note**: `whisper_ggml` documents iOS 15.6+ as its minimum; this project's
  current `IPHONEOS_DEPLOYMENT_TARGET` is `15.0` (set by `flutter create`, per F000 research.md R8,
  which deliberately left it at the SDK default because nothing until now needed a floor). This
  unit raises it to `15.6` across all three build configurations in
  `ios/Runner.xcodeproj/project.pbxproj` — a package-forced native change in the same category as
  RF03's `Info.plist` addition, not a product decision.

## R3 — Photo capture package

- **Decision**: `image_picker`, called as `pickImage(source: ImageSource.camera | ImageSource.gallery,
  imageQuality: 90)` for both of the Foto tab's two buttons. The non-null `imageQuality` is a
  deliberate choice beyond "a reasonable compression value": it forces the plugin's iOS
  implementation through its JPEG re-encoding path regardless of the source asset's original
  format, which is what makes `mimeType: image/jpeg` always correct for the backend call (R4) even
  for the common case of an iOS Photos-library image stored as HEIC — a format `POST /media/ocr`'s
  contract does not accept at all (R4).
- **Rationale**: FR-005 requires exactly the camera-or-gallery choice the prototype's "Captura"
  state shows (two large buttons); `image_picker` is the official Flutter-team plugin for this,
  already the de-facto standard, and returns a plain `XFile` (a file path) either way — no
  source-specific branching needed past the initial `ImageSource` argument.
- **Alternatives considered**: Picking without `imageQuality` and inspecting/transcoding HEIC
  output manually (e.g. via the `image` package) — rejected as strictly more code to reach the same
  guaranteed-JPEG outcome `imageQuality` already gives for free as a side effect of the plugin's own
  documented compression behavior.
- **Native project note**: requires `NSCameraUsageDescription` (camera button) and
  `NSPhotoLibraryUsageDescription` (gallery button) in `Info.plist`, same category as R1's
  microphone string.

## R4 — Backend OCR call shape

- **Decision**: `PhotoRecognitionRepository` base64-encodes the JPEG bytes R3 produces
  (`base64Encode` from `dart:convert`, no new package) and calls `media-ocr`
  (`POST /media/ocr`) with `{"image": "<base64>", "mimeType": "image/jpeg"}`, reusing `ApiClient`
  unmodified. The response's `confidence` field is read into the result but never branched on
  (spec.md Clarifications: confidence-based gating is explicitly RF02's concern).
- **Rationale**: `docs/input/backend/api/openapi.yaml`'s `/media/ocr` schema requires `image`
  (a string) and `mimeType` (enum `image/jpeg`/`image/png`/`image/webp` only — no HEIC) with no
  separate multipart path; R3's `imageQuality` choice is what guarantees the app only ever sends
  one of the three accepted MIME types.
- **Alternatives considered**: None — the request shape is dictated entirely by the frozen
  contract (Principle III); the only real decision here was R3's upstream format guarantee.

## R5 — Blocking Save while offline (FR-010)

- **Decision**: A new `core/network/connectivity_checker.dart` (`ConnectivityChecker`, wrapping
  `connectivity_plus`'s `Connectivity().checkConnectivity()`) exposes a plain `Future<bool>
  hasConnection()` — true unless the result is `ConnectivityResult.none`. Every Save path (text,
  audio, photo) checks this *first*, before any transcription/OCR/entry-creation work, and if it is
  `false`, fails immediately with `NetworkOfflineFailure` without calling `ApiClient` at all.
- **Rationale**: FR-010/SC-005 and the Edge Cases explicitly want the block to happen "without
  attempting a network call that cannot succeed" — a reactive catch of `ApiClient`'s own
  `NetworkOfflineFailure` (which already exists and already fires on a real failed call) would
  satisfy the *error-handling* half of RNF09 but not this specific "don't even try" requirement, so
  a proactive, synchronous-feeling pre-check is needed in addition. Checking before transcription
  too (not just before the `entries-create` call) gives the snappier "blocked immediately" behavior
  FR-010 asks for, and avoids running on-device Whisper inference or an OCR round-trip for a save
  that cannot complete regardless. `connectivity_plus` lives in `core/` (not inside the `capture`
  feature) because it is the same cross-cutting, interface-level connectivity concern
  spec.md's own Assumptions say "already established elsewhere in the product (chat, search)" —
  later units (RF04, RF06) blocking their own writes/sends while offline will reuse this exact
  checker rather than each growing its own.
- **Known limitation, accepted**: `connectivity_plus` reports OS-level interface state (Wi-Fi/
  cellular/none), not actual internet reachability — a device on Wi-Fi with no upstream internet
  still reads as "connected." Adding a live reachability probe (e.g. pinging the backend) would be
  disproportionate machinery for a check whose whole purpose is to avoid an extra network round
  trip; the existing reactive `NetworkOfflineFailure` path (R-nothing-new) still catches that
  residual case when the real `entries-create` call is attempted.
- **Alternatives considered**: Relying solely on `ApiClient`'s existing reactive mapping — rejected
  per the "without attempting a network call" wording above. A full reachability ping before every
  save — rejected as disproportionate for the stated requirement.

## R6 — "Confirming Save" is a different user action per modality

- **Decision**: There is no second, explicit "Salvar" tap for the Áudio or Foto tabs. Per spec.md's
  own Acceptance Scenarios: for **Texto**, "confirming Save" is the user tapping the tab's "Salvar"
  button (User Story 1, FR-003). For **Áudio**, it is the user tapping the stop control (User Story
  2 Scenario 2: "the user taps stop... the system automatically transcribes it and completes the
  save"). For **Foto**, it is the picker returning a selected/captured image (User Story 3 Scenario
  2: "that image is provided... the system automatically extracts its text and completes the
  save"). None of the three needs or gets an intermediate editable-text review screen with its own
  "Salvar" button — that reviewable state (prototype's "Transcrito"/"Reconhecido") is exactly what
  spec.md's Clarification 1 reserves for RF02.
- **Rationale**: Re-building a second confirmation tap for audio/photo would recreate the
  editable-review step FR-007 explicitly forbids, and would contradict the Acceptance Scenarios'
  own wording ("completes the save" as the direct, same-step outcome of stopping/providing — not a
  precursor to a later explicit save action). This is the detail most likely to be
  over-engineered by accident during implementation, so it is called out here explicitly rather
  than left implicit in data-model.md's transition tables alone.
- **Alternatives considered**: Adding a plain (non-RF02-styled) "Salvar" button after recognition
  succeeds, before creating the entry — rejected: it would be an invented intermediate step with no
  basis in the Acceptance Scenarios, and would reintroduce exactly the kind of extra tap SC-003
  ("no required intermediate screens") argues against.

## R7 — Local recognition failures are not backend `Failure`s

- **Decision**: `AudioTranscriptionRepository.transcribe(...)` returns
  `Either<RecognitionFailure, String>`, where `RecognitionFailure` is a small new sealed type local
  to the `capture` feature's domain layer (`emptyResult | transcriptionError`) — **not** a new
  subtype added to `core/network/failure.dart`. `PhotoRecognitionRepository.recognize(...)`, by
  contrast, *does* return `Either<Failure, OcrResult>` using the existing, unmodified `Failure`
  hierarchy, because it is a real network call to `media-ocr` and the backend's closed taxonomy
  already has the exact code this path needs (`OcrNoTextFailure` / `OCR_NO_TEXT`, already present in
  `failure.dart` since F000).
- **Rationale**: This mirrors RF03's research.md R5 precedent exactly: `core/network/failure.dart`
  is scoped to the backend's 13-code closed taxonomy (a *server* response can say
  `NETWORK_TIMEOUT`; it cannot say "the microphone recording was silent"). On-device Whisper
  returning an empty/whitespace transcript, or throwing internally, is a purely local condition
  with no corresponding backend code — forcing it through `Either<Failure, T>` would mean either
  inventing a fake backend-shaped code for something the backend never sees, or diluting the
  "closed" taxonomy's scope. OCR, conversely, is a real backend round trip whose own contract
  already names this exact failure mode — no new type needed there at all.
- **Alternatives considered**: One shared `Either<Failure, T>` surface for both audio and photo
  recognition, adding a new local-only `Failure` subtype for the audio case — rejected for the same
  reason RF03 rejected modeling PIN/biometric outcomes that way: it would grow a taxonomy the
  spec and RNF09 treat as backend-defined with a code no network response will ever actually send.

## R8 — A shared entry-creation seam, because RF10 already names it

- **Decision**: `Entry` (full response shape), `EntriesRepository` (create today; later units add
  list/search), and a new `CreateEntryUseCase(content, source)` all live in a new, dedicated
  `lib/features/entries/` feature — separate from `lib/features/capture/`, which owns only the
  Insertion Modal UI and the audio/photo recognition pipeline. This unit's three save usecases
  (`SaveTextEntryUseCase`/`SaveAudioEntryUseCase`/`SavePhotoEntryUseCase`, living in `capture/domain/`)
  each depend on `CreateEntryUseCase` from `entries/domain/`, never on `EntriesRepository` or any
  `entries/data/` class directly.
- **Rationale**: `requirements.md` §RF10 says, verbatim, "The chat feature triggers the creation of
  the entry through a shared interface / use case, never by directly importing a repository or data
  source **of the entries feature** — a violation here also breaks RNF06." That sentence names "the
  entries feature" as something that already exists by the time RF10 is built, and prescribes the
  exact shape of how another feature is allowed to reach it (a shared usecase, not its repository).
  RF01 is the unit that actually creates that feature for the first time — building `entries/` now,
  with exactly the seam RF10's own requirement text describes, means RF10 (and RF07, which also
  reads `entries/domain` types) never has to retrofit this boundary later or reach into `capture/`'s
  internals. `Entry` is modeled against the *entire* `entries-create` response schema (`id`,
  `content`, `source`, `chatMessageId`, `occurredAt`, `tags`, `piiStatus`, `piiSpans`,
  `embeddingStatus`, `mediaDurationSeconds`, `serverRevision`, `createdAt`, `updatedAt`) rather than
  only the fields this unit reads, because every one of those fields is `required` in the frozen
  response the backend *always* sends — this is faithfully representing today's contract, not
  speculative modeling of a future requirement.
- **What this unit does NOT add**: `EntrySource` is defined with exactly the three values this
  unit uses (`manual`, `audio`, `photo`) — not `chat`. `CreateEntryUseCase.call()` takes only
  `(content, source)` — no `chatMessageId` parameter. Both are left for RF10 to add additively when
  it arrives (FR-012: this unit must not implement RF10's behavior); what RF01 commits to is only
  that RF10 will *extend* this one usecase rather than invent a second path into `EntriesRepository`.
- **Alternatives considered**: Putting `EntriesRepository`/`Entry` inside `capture/` (since RF01 is
  the only unit using them so far) — rejected, directly contradicts RF10's "entries feature" wording
  and would force a disruptive move later. Having `capture/`'s save usecases call
  `EntriesRepository.create()` directly, with `CreateEntryUseCase` deferred to whenever RF10 is
  built — rejected: RF10's requirement explicitly bans exactly this shape ("never... directly
  importing a repository... of the entries feature"), and building the usecase now costs nothing
  extra since RF01 needs the same orchestration either way.

## R9 — The "+" button does not exist yet

- **Decision**: `HomeChatShellPage`'s `_ComposerBar` (`lib/features/home/presentation/pages/
  home_chat_shell_page.dart`) gains a real, enabled leading icon button that opens the Insertion
  Modal via `showModalBottomSheet`. Nothing else in the composer (text field, send icon) changes —
  both stay disabled, exactly as F000 research.md R10 left them, since RF04 (chat sending) remains
  out of scope here.
- **Rationale**: F000's own research.md R10 explicitly scoped the composer as "rendered but fully
  **disabled**... no RF04 wiring," with no mention of a "+" affordance at all — confirmed by reading
  the current file, which has only a `TextField` and a send `IconButton`. FR-001 requires the modal
  to be "opened by the '+' button on Home/Chat," so this unit is the one that must add it; a plain
  `IconButton` in the composer `Row`, wired only to open the modal, is the minimal change that
  satisfies FR-001 without touching the still-disabled text field/send icon next to it.
- **Alternatives considered**: A floating action button overlaying the chat area instead of a
  composer-bar icon — rejected, the prototype's own composer description (prototype-extract.md
  §2.2: "composer with '+', placeholder..., send icon") places the "+" inline in the composer, not
  as a separate FAB.

## R10 — New design tokens

- **Decision**: Reuse everything already in `design_tokens.dart` — F000/RF03 already added
  `sizeLoadingIndicator`/`strokeWidthLoadingIndicator` (the plain generic loading indicator FR-007
  needs), `colorError` (stop button, failure text/icon), `colorPrimary` (waveform bars, filled tab
  background, primary buttons), `colorBorder`/`colorSurfaceElevated` (outline buttons for "Câmera"/
  "Galeria" and the generic "Tentar novamente" retry action), and the full type scale. The "frozen
  and faded" look of a processing waveform (prototype: opacity `.35`) is applied with a plain
  `Opacity` widget around the (already-tokenized-color) bars, not a new token — an opacity
  multiplier is not itself a color/typography/spacing/radius value under RNF08's enumeration, the
  same reasoning that already lets `elevation1`/`elevation2` bake their own alpha into the token
  file without every *use* of alpha elsewhere needing a dedicated token.
- **No new tokens needed.** Unlike RF03 (which needed `sizeKeypadTapTarget`,
  `sizeBiometricIconContainer`, `sizeBiometricIcon` for a shape the existing scale had no
  equivalent for), RF01's three tabs — a plain multiline field, a timer/waveform/stop-button row,
  and two large buttons — are all composed from F000's existing spacing/radius/typography scale and
  the component-library entries already named in prototype-extract.md §6 ("Primary button",
  "Secondary button (outline)", "Text field").

## R11 — Why this unit's own failure/retry UI is allowed to look different from the prototype's named "Erro" states

- **Decision**: The audio/photo failure UI this unit builds (FR-009) is a plain message plus one
  generic retry action, styled from existing tokens (`colorError` text, a ghost/outline button) —
  it does **not** reproduce the prototype's specific "Áudio — Erro" / "Foto — Erro" component specs
  verbatim (prototype-extract.md §2.3: the red warning icon treatment, the exact copy "Não foi
  possível transcrever"/"Não foi possível reconhecer o texto", the specific outline button styled
  as that named state, or Foto-Erro's second action "Salvar só a foto").
- **Rationale**: This looks, at first glance, like an RNF08 violation ("every screen MUST be
  faithful to the prototype") — but RNF08's fidelity obligation applies to states this unit actually
  implements. The "Erro" states as named in the prototype are explicitly, by spec.md's own
  Clarification 1, RF02's screens to build ("this unit MUST NOT present... a dedicated multi-state
  screen... or modality-specific retry affordances such as 'Tentar novamente' or 'Salvar só a
  foto'" — FR-007). FR-009 still requires *some* failure-and-retry behavior to exist for this unit's
  own narrower pipeline (transcription-or-save failing), so this unit necessarily renders its own,
  undocumented-by-the-prototype failure view — one the spec's Clarification already pre-approved as
  not needing to match RF02's specific look. This is not a new judgment call; it is carrying the
  spec's own already-resolved Clarification 1 through to its concrete UI consequence, called out
  here so a later reviewer does not mistake the deliberately plainer failure view for an
  overlooked fidelity gap.
- **Alternatives considered**: Reusing the prototype's exact "Erro" copy/iconography now and simply
  omitting the "Tentar novamente"/"Salvar só a foto" *buttons* — rejected: the copy and icon
  treatment are as much a part of the named, RF02-reserved state as its buttons are; partially
  borrowing its look while structurally not being that state would be a confusing hybrid, not a
  faithful implementation of either unit's scope.

## R12 — Correction: the "Áudio" tab has its own idle state, it does not auto-start recording

- **Decision**: FR-004 and this unit's implementation are corrected so the "Áudio" tab opens on an
  idle state — a round start control with the caption "Toque para gravar" — and only requests
  microphone permission and starts real-time recording once the user taps that control. The
  previous reading (recording starts the instant the tab becomes active) is wrong and is removed.
- **Rationale**: prototype-extract.md §2.3's summary table for this screen lists only "Gravando",
  "Processando", "Transcrito", "Erro" for Áudio, with no idle/start row, which is what led the
  original spec to assume (spec.md's since-corrected Assumptions bullet) that "Gravando" was this
  tab's default state. Direct inspection of the prototype's Tela 2 on a device shows an idle state
  with a round start button precedes "Gravando" — the extract's table omitted it. `docs/input/` is
  frozen and is not edited to reflect this (Constitution Principle I); this unit's own spec and
  implementation are corrected instead, since RNF08's fidelity obligation is to the actual
  prototype, not to a summary table that under-documented one of its states.
- **Alternatives considered**: Leaving FR-004 as "starts recording immediately" and treating the
  idle state as an extension — rejected: auto-starting the microphone without an explicit user tap
  is also the wrong UX default for a sensitive permission like audio recording, independent of the
  prototype question, and the correction's own report confirms no part of FR-004's existing scope
  (stop control, waveform, timer) is affected other than what precedes "Gravando."
