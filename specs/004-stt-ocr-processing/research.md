# Research: P-RF02 — Speech-to-text / OCR processing

All unknowns this unit raises are implementation judgment calls on top of an already-resolved spec (spec.md's
three Clarifications) and an already-built RF01 pipeline — there is no new package, API, or external service
to evaluate. Each entry below either corrects an RF01 decision that no longer holds once recognition and save
are split apart, or fills a gap spec.md leaves to "reasonable technical decision" (Constitution Principle I).

## R1 — Removing the pre-transcription connectivity gate for audio

- **Decision**: `AudioTranscriptionRepository.transcribe()` is called unconditionally on `AudioStopRequested`,
  with no `ConnectivityChecker` check beforehand. The connectivity gate moves to exactly one place for audio:
  immediately before `ConfirmEntrySaveUseCase`'s `entries-create` call (i.e., when the user taps "Salvar" from
  "Áudio — Transcrito").
- **Rationale**: RF01's research.md R5 (specs/003) checked connectivity *before* transcription too, but that
  was only sound because RF01's single combined usecase would otherwise burn a Whisper inference run for a
  save that could never complete regardless. Now that stopping a recording and tapping "Salvar" are two
  separate user actions (spec.md FR-001 vs. FR-002), gating transcription itself on connectivity would be
  wrong on its own terms: transcription is on-device (Constitution Principle II) and has no network dependency
  to protect; blocking it on "offline" would make an unrelated, free local operation fail for no reason, and
  would contradict FR-001's unconditional "the system MUST automatically begin on-device transcription" on
  stop. The spec's own Edge Cases only ever gate *writes* on connectivity ("'Salvar' ... and 'Salvar só a
  foto' both still require connectivity for the underlying `POST /entries` call") — never recognition itself
  for audio.
- **Alternatives considered**: Keeping RF01's pre-check in front of transcription anyway, "for consistency" —
  rejected: it would fail Story 2's Independent Test (forcing a transcription failure) in an environment
  that's merely offline but otherwise fine, and silently reclassifies "offline" as a transcription failure
  mode it structurally isn't.

## R2 — Two new design tokens: the photo thumbnail and the recurring warning icon

- **Decision**: Add exactly two entries to `lib/core/design_tokens.dart`:
  - `sizePhotoThumbnail = 64` — the "small thumbnail" prototype-extract.md §2.3 names for "Foto — Reconhecido"
    (next to the editable text) and "Foto — Erro" (kept on screen); one value, reused by both states.
  - `sizeStatusIcon = 32` — the red warning icon prototype-extract.md §2.3 names for both "Áudio — Erro" and
    "Foto — Erro"; one value, two call sites.
- **Rationale**: RF01's research.md R10 (specs/003) found no new token was needed because its own failure UI
  was deliberately plain (no icon, no thumbnail — research.md R11). This unit is precisely the one that must
  render the prototype's actual "Erro" states, which do name an icon and (for photo) a thumbnail the existing
  scale has no equivalent size for — the same bar RF03's research.md R3 (specs/002) already used ("a new token
  only when no existing value in the scale fits the exact shape needed, and it's reused at 2+ call sites, not
  a one-off"). Both qualify: two states each, not a single use. `colorError` (already present) is reused for
  the icon's color and the failure copy — no new color token needed.
- **Alternatives considered**: A single shared `sizeWarningIcon`/`sizeThumbnail` combined into one generic
  "status visual" token — rejected as it would conflate two different visual roles (an icon vs. an image
  thumbnail) for no reuse benefit, since they're never substituted for each other.

## R3 — The fixed placeholder content for "Salvar só a foto"

- **Decision**: The literal string `'Foto registrada sem texto reconhecido.'` is sent as `content` whenever
  "Salvar só a foto" is tapped (`EntrySource.photo`, no further OCR attempt for that capture — FR-008).
  Defined as a single `const` in the usecase call site (`InsertionModalBloc`), not duplicated anywhere else.
- **Rationale**: spec.md's own resolved Clarification 2 fixes the shape of this requirement (non-empty,
  backend-contract-compliant, `source: "photo"`) but explicitly leaves the exact wording to implementation
  ("exact wording left to implementation" — spec.md Assumptions). The chosen string is grammatically neutral
  Portuguese, describes exactly what happened (an entry was registered from a photo, no text was recognized),
  stays well under the 20000-char `content` limit, and is unambiguous if a user later sees it in a future
  history/search screen (RF07/RF06) without this unit needing to anticipate that screen's own design.
- **Alternatives considered**: Reusing the OCR failure message itself ("Não foi possível reconhecer o texto")
  as the stored content — rejected: that sentence describes a *process outcome*, not journal content, and
  would read strangely if ever surfaced as an entry's body text in a future timeline view.

## R4 — Rendering the prototype's actual "Erro" states, closing RF01's documented carve-out

- **Decision**: `CaptureFailureBand` (specs/003's deliberately plain placeholder — generic message + one
  outline "Tentar de novo" button, no icon) is removed from `capture_status_views.dart`. A new
  `RecognitionErrorView` widget renders prototype-extract.md §2.3's actual "Erro" shape: a
  `sizeStatusIcon`-sized warning icon in `colorError`, the exact copy ("Não foi possível transcrever" /
  "Não foi possível reconhecer o texto"), an outline "Tentar novamente" button, and — for Foto only — the
  secondary text action "Salvar só a foto". `CaptureLoadingIndicator` and `CapturePermissionDeniedMessage` are
  unchanged and keep serving their existing, still-applicable roles (the former embeds into the new
  "Processando"/"Processando OCR" layouts alongside the frozen waveform/thumbnail; the latter is untouched by
  this unit, since Idle/PermissionDenied/Recording/Captura states are RF01's, not RF02's, to redesign).
- **Rationale**: This is not a new judgment call so much as carrying out RF01's own research.md R11 (specs/
  003) to its stated conclusion: that entry explicitly named the "Erro" states as "RF02's screens to build,"
  not an open design question for this unit to re-litigate. spec.md's resolved Clarification 1 confirms it
  ("this unit replaces RF01's placeholder recognition UX... with the dedicated states the prototype
  defines").
- **Alternatives considered**: Keeping `CaptureFailureBand` around for some other, hypothetical use —
  rejected: nothing else in this codebase renders it once Áudio/Foto failures move to `RecognitionErrorView`,
  and keeping dead code around violates the "don't keep unused code for hypothetical future need" guidance
  this plan is held to; it is deleted outright, not deprecated.

## R5 — A save-call failure after successful recognition gets its own (non-prototype-named) state, not a reuse of "Erro"

- **Decision**: If `ConfirmEntrySaveUseCase` fails (offline, or the `entries-create` call itself fails) after
  the user taps "Salvar" from "Transcrito"/"Reconhecido" — or taps "Salvar só a foto" from "Foto — Erro" — the
  bloc emits a new `*SaveFailure` state (`InsertionModalAudioSaveFailure`/`InsertionModalFotoSaveFailure`,
  data-model.md) that keeps the reviewed/edited text (and, for photo, the thumbnail) on screen with an inline
  error message, rather than falling back to the recognition-failure "Erro" state. Retrying is simply tapping
  "Salvar" (or "Salvar só a foto") again — no re-transcription, no re-OCR.
- **Rationale**: The prototype's "Erro" states (prototype-extract.md §2.3) are defined specifically for a
  *recognition* failure ("Não foi possível transcrever"/"...reconhecer o texto") — spec.md never describes a
  distinct screen for "recognition succeeded but the subsequent save failed," leaving this a genuine gap for
  reasonable technical judgment (Constitution Principle I). Falling back to "Erro" would be actively wrong
  here: it would discard the user's successfully-recognized (and possibly hand-edited) text to show a message
  about transcription/OCR, a step that already succeeded. This exactly mirrors an existing, already-approved
  precedent in this same codebase: the Texto tab's `InsertionModalTextoFailure` keeps the typed text visible
  and treats a second tap of the same "Salvar" button as its own retry (texto_tab_view.dart) — this unit
  applies that identical shape to Audio/Foto's post-review save step instead of inventing something new.
- **Alternatives considered**: Falling back silently to "Transcrito"/"Reconhecido" with no visible error (just
  re-enabling "Salvar") — rejected: FR-009's "Erro" precedent and RNF09's "every write endpoint... handled" bar
  both imply the user must see *some* failure signal, not a silent no-op. Reusing "Erro" with its recognition
  copy substituted for a save-specific message — rejected as a confusing hybrid for the same reason RF01's own
  research.md R11 (specs/003) rejected partially borrowing a named state's look.

## R6 — Guarding against a stale recognition result after abandonment

- **Decision**: Before applying a `transcribe()`/`recognize()` result, the bloc re-checks that its *current*
  state is still the matching `*Processing` state for the same held file path (`_pendingAudioPath`/
  `_pendingImagePath` unchanged since the call started). If the user has since switched tabs, closed the
  modal, or (for photo) retried onto a different in-flight attempt, a late-arriving result is discarded
  outright — no state transition, no entry creation.
- **Rationale**: spec.md's User Story 5 / Edge Cases requires "no entry is created, regardless of how the
  in-flight recognition call eventually resolves," and FR-011 requires discarding "any in-progress
  recognition... held for that capture" on abandonment. Switching away from the Áudio/Foto tab already resets
  the *visible* state to that tab's idle state (mirroring RF01's existing tab-switch behavior), but without
  this explicit guard, a `transcribe()` call that resolves after the switch could still emit
  `InsertionModalAudioTranscribed`/`...Failure` and silently clobber whatever the user has navigated to since
  — a correctness bug even though `flutter_bloc` v9's post-`close()` emit is already a safe no-op (that only
  covers the modal-closed case, not the still-open-but-switched-tabs case).
- **Alternatives considered**: Cancelling the underlying `Future` itself (e.g., via a cancellation token passed
  into `whisper_ggml`/the OCR call) — rejected as disproportionate: neither `whisper_ggml` nor the OCR HTTP
  call exposes a cancellation hook, and the state-match guard achieves the same observable guarantee (no
  stray state/entry) without needing one.

## R7 — Consolidating `SaveAudioEntryUseCase`/`SavePhotoEntryUseCase` into one `ConfirmEntrySaveUseCase`

- **Decision**: Once recognition is removed from each (R1, and photo's OCR step moving into the new
  `RecognizePhotoUseCase`, R-nothing-new beyond what data-model.md documents), `SaveAudioEntryUseCase` and
  `SavePhotoEntryUseCase` become identical in every line except the hardcoded `EntrySource` they pass to
  `CreateEntryUseCase`. Both are deleted and replaced by one `ConfirmEntrySaveUseCase(content, source)` —
  connectivity check, then `CreateEntryUseCase(content, source)` — used for Audio-Salvar, Foto-Salvar, and
  Foto-"Salvar só a foto" alike (the last simply supplies R3's placeholder string as `content`).
- **Rationale**: This is the one place in this unit where two call sites really would be pure duplication of
  each other, which is exactly the case where collapsing them is the right amount of abstraction (not a
  premature one) — "three similar lines is better than a premature abstraction" cuts the other way once the
  lines are not merely similar but identical modulo one parameter already present in the call signature.
- **Alternatives considered**: Keeping two thin per-modality usecases "for clarity/discoverability" —
  rejected: there is no behavioral difference left to name separately once `EntrySource` is just a parameter,
  and two near-identical classes are harder to keep in sync (e.g., a future RNF09 fix applied to one and
  missed in the other) than one.
