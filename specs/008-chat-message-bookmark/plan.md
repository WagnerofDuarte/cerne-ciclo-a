# Implementation Plan: P-RF10 — Save a chat message as an entry

**Branch**: `008-chat-message-bookmark` (spec directory only — no git branch exists; none of this repo's
extension hooks are configured, per spec.md's own header)

**Date**: 2026-10-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-chat-message-bookmark/spec.md`, `docs/input/requirements.md`
§1 (RF10), §6.2/6.3 (`entries-create`'s `chatMessageId`/`occurredAt` fields, already documented as shared
between RF01 and RF10), §8 (data model reference — `entries.chat_message_id`), §12 (delivery order: RF10 after
RF01 and RF04, both already implemented), §13; `docs/input/backend/api/openapi.yaml`'s `/entries` POST schema
(`chatMessageId`/`occurredAt` already accepted, optional, `format: uuid`/`format: date-time`);
`docs/input/backend/error-taxonomy.md` ("Never `409` — the idempotency of RF10 ... always answers `200`");
`docs/input/prototype/prototype-extract.md` §2.2 ("Tela 1 — Bookmark") and its inline component table; the
prototype's own source (`docs/input/prototype/cerne-prototype.html`, the bookmark row's exact markup/styles);
and `.specify/memory/constitution.md`. Depends on RF01 (`specs/003-multimodal-capture/`) and RF04
(`specs/007-chat-memory-rag/`), both already implemented — this is the unit that connects chat's own
messages to the entry-creation seam RF01 built and already annotated for this exact extension
(`create_entry_usecase.dart`: "RF10 will extend this signature, never bypass it").

## Summary

Every user message in Home/Chat gains a bookmark control with the prototype's own four sub-states — `idle`,
`saving` (spinner), `saved` (ochre check), `error` (red warning) — that turns that one message into a
persisted journal entry via the exact same `CreateEntryUseCase` RF01 already established, now extended with
two new optional parameters (`chatMessageId`, `occurredAt`) that thread straight through
`EntriesRepository`/`EntriesRepositoryImpl`/`EntriesRemoteDataSource` to `entries-create`'s already-documented
request fields — no backend change, no new endpoint, no new repository. `ChatBloc` (RF04) gains exactly one
new dependency, `CreateEntryUseCase` itself (a domain usecase, never a repository or data source — the literal
seam FR-009 names), one new event (`BookmarkTapped(messageId)`), and one new `ChatReady` field (`bookmarks: Map<String,
BookmarkStatus>`, keyed by message id) tracking each message's bookmark sub-state in memory for the lifetime of
the bloc. `ChatRepository`/`ChatRepositoryImpl`/`ChatLocalCache` (also RF04) each gain a small, device-local,
Keychain-backed record of "which chat message ids have already produced an entry" (`savedEntryIdFor`/
`recordMessageSaved`) — a convenience for FR-008's "still shows `saved` after reopening/restarting," never the
source of correctness, since the backend's own `entries-create` idempotency (keyed by `chatMessageId`, confirmed
`200` not `409` on a repeat) already guarantees no duplicate regardless of what this local record remembers or
forgets. One new presentation widget, `BookmarkButton`, renders the four sub-states with two new, exact-value
`DesignTokens` (`sizeBookmarkIcon`, `spacingBookmarkGap`) read directly off the prototype's own inline bookmark
markup; `ChatMessageBubble`'s existing user-message branch is extended to lay the bubble and the bookmark
side by side in a row, matching that markup exactly. No change to `records/`, `export/`, `dashboard/`, any
backend file, or any file under `docs/input/`.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000/RF01–RF07.

**Primary Dependencies**: No additions. Reuses `flutter_bloc`, `fpdart`, `get_it`, `equatable`,
`flutter_secure_storage` (for `ChatLocalCache`'s one new key), `dio` (via the already-registered
`entries-create` function, unchanged shape); dev-only `mocktail`, `bloc_test`.

**Storage**: One new key on the existing `ChatLocalCache` (`chatSavedMessageEntryIds` → `Map<String, String>`,
`chatMessageId` → `entryId`), same Keychain-backed, JSON-encoded mechanism `EntriesLocalCache`/`ChatLocalCache`
already use for personal content (research.md R1). No new local-cache class, no new third-party persistence
package.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter (RNF07) — now additionally exercising
`bookmark_status.dart` (a pure enum) and `ChatBloc`'s new `_onBookmarkTapped` branches (testable with the same
`MockChatRepository`/`MockCreateEntryUseCase`-via-`MockEntriesRepository` pattern `chat_bloc_test.dart`/
`create_entry_usecase_test.dart` already establish). `no_bloc_imports_bloc_test.dart` and
`domain_purity_test.dart` both run unmodified against the extended `lib/features/chat/` — no new bloc, no new
flutter/data import in `chat/domain/`. `test/architecture/no_cross_feature_data_imports_test.dart` (new,
already passing against the pre-RF10 codebase) is the one that enforces FR-009's actual constraint — no direct
`EntriesRepository`/`EntriesRemoteDataSource` import from `chat/presentation/bloc/` — which the other two tests
are not scoped to catch.

**Target Platform**: iOS, portrait only — unchanged. No native project file touched.

**Project Type**: Same single Flutter mobile app. No new feature folder — every change lands inside the two
already-existing folders this unit depends on (`lib/features/chat/`, `lib/features/entries/`), plus two
`core/` token additions and one `core/di/` registration update. No backend/server code, no change to
`docs/input/backend/api/openapi.yaml` (its `chatMessageId`/`occurredAt` fields on `entries-create` already
exist and are simply used for the first time).

**Performance Goals**: RNF01 unchanged. The bookmark's `saving` state (shown the instant the tap is handled,
before the network call resolves) is this unit's own "<100 ms local reflection"; the spinner itself is the
required loading indicator for the network call that follows (always well past the 300 ms threshold in
practice for a write endpoint already doing PII-check + embedding server-side).

**Constraints**:
- No RF08 (proactive insight)/RF05 (export)/RF09 (dashboard), no extension feature, no backend/contract/
  config change (FR-010) — `chatMessageId`/`occurredAt` are fields `docs/input/backend/api/openapi.yaml`
  already declares on `entries-create`'s request body; nothing new is sent that the contract doesn't already
  define.
- Entry creation from chat MUST go through `CreateEntryUseCase` only, never `EntriesRepository`/
  `EntriesRemoteDataSource` directly (FR-009) — enforced by construction: `chat_bloc.dart`'s only new import
  from `features/entries/` is `create_entry_usecase.dart` (+ `entry.dart` for the `EntrySource` enum already
  used identically by every other `source` value chat never touches otherwise).
- Clean Architecture, 3 layers per feature (Principle V) — the one new domain file,
  `lib/features/chat/domain/entities/bookmark_status.dart`, is a bare enum: no `package:flutter`, no
  `chat/data/` import (confirmed against `domain_purity_test.dart`, unmodified). `ChatBloc`'s dependency
  surface grows by exactly one domain usecase (`CreateEntryUseCase`) — no new cross-bloc import.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — every bookmark
  color is reused verbatim (`colorTextSecondary`/`colorAccent`/`colorError`, already defined); the icon size
  (16 dp) and the bubble-to-icon gap (6 dp) are new, exact-value tokens (`sizeBookmarkIcon`,
  `spacingBookmarkGap`) because neither matches an existing 4 dp-grid step, mirroring the precedent already set
  by `sizeAudioRecordIcon`/`sizePhotoTileIcon`/`borderWidthFocused` (RF01–RF03) for off-grid, element-specific
  values read straight off the prototype.
- Idempotency (FR-004) is **not** reimplemented client-side — it is the backend's own guarantee
  (`error-taxonomy.md`: "Never `409`... always answers `200`"). The device-local `savedEntryIdFor` record is
  explicitly a convenience for FR-008's UI-continuity requirement, never a correctness mechanism (spec.md's own
  Assumptions already say so) — this plan does not invent a second, client-side dedup guarantee on top of it.

**Scale/Scope**: 0 new feature folders. 1 new domain entity (`bookmark_status.dart`), 1 new presentation widget
(`bookmark_button.dart`); 8 existing files extended (`create_entry_usecase.dart`, `entries_repository.dart`,
`entries_repository_impl.dart`, `entries_remote_data_source.dart`, `chat_repository.dart`,
`chat_repository_impl.dart`, `chat_local_cache.dart`, `chat_event.dart`/`chat_state.dart`/`chat_bloc.dart`,
`chat_message_bubble.dart`, `home_chat_shell_page.dart`); 2 new `DesignTokens` constants; 1 DI registration
updated (no new registration — `CreateEntryUseCase` is already registered by RF01).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only throughout. Every judgment call below (research.md R1–R10) fills a gap spec.md itself already flags as "an implementation decision for the planning phase" (FR-009's shared-interface shape, FR-003's `saved`-state non-tappability) or that neither `requirements.md` nor the prototype addresses (the optimistic-message-id race, R6; the device-local record's exact storage shape, R1) — none reopens a Clarification spec.md already resolved. |
| II. Fixed Technology Stack | PASS | No new package. `flutter_bloc`/`fpdart`/`get_it`/`flutter_secure_storage` all already project dependencies. |
| III. Backend Boundary | PASS | Only the already-contracted `entries-create` function is called, now with two of its already-declared optional request fields (`chatMessageId`/`occurredAt`) populated for the first time; no AI provider called directly; no OpenAPI/`.env`/config file touched. |
| IV. Design Token Discipline & Visual Fidelity | PASS | Every bookmark color reused verbatim; the two new size/spacing tokens are exact values transcribed from the prototype's own inline bookmark markup (research.md R7), not approximations. |
| V. Clean Architecture Folder Convention | PASS | `bookmark_status.dart` imports nothing beyond the Dart core library; `ChatBloc`'s new dependency (`CreateEntryUseCase`) is a domain usecase, not a repository/data source — confirmed against `domain_purity_test.dart`/`no_bloc_imports_bloc_test.dart` (unmodified) and the new, narrowly-scoped `test/architecture/no_cross_feature_data_imports_test.dart`, which is the one that actually catches `chat_bloc.dart` importing `EntriesRepository`/`EntriesRemoteDataSource` directly. |
| RNF01 (latency) | PASS | The `saving` state is this unit's own instant local reflection; the spinner is the loading indicator the network call (always realistically >300 ms for a PII-check+embedding write) requires. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF10 directly | Chat-sourced entries run through the exact same backend `entries-create` pipeline as every other source (spec.md Assumptions) — no new client-side PII logic, no new retention policy, RLS unaffected (same `auth.uid() = user_id` entries table). |
| RNF05 (hard delete) | N/A | Belongs to Settings/RNF05's own unit. |
| RNF06 (layer violations) | PASS | `chat/domain/` stays flutter/data-free; `ChatBloc` never imports `EntriesRepository`/`EntriesRemoteDataSource` (FR-009's own wording is also RNF06's own concern per spec.md: "a violation here also breaks RNF06") — confirmed by `chat_bloc.dart`'s planned import list containing only `create_entry_usecase.dart`/`entry.dart` from `features/entries/`. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `bookmark_status.dart` is a trivial enum (same tier as `EntrySource`/`ChatRole`); the more substantial new logic (`_seedBookmarks`, `_onBookmarkTapped`'s branches, `ChatRepositoryImpl.savedEntryIdFor`/`recordMessageSaved`) is tested the same `mocktail`-driven way every other `ChatBloc`/`ChatRepositoryImpl` branch already is. |
| RNF08 (visual fidelity) | PASS | Bookmark icon/size/color/gap/spin-animation match the prototype's own inline bookmark markup exactly (research.md R7) — transcribed, not approximated. |
| RNF09 (Either + 15/15 error scenarios) | PASS (gate carried into tasks) | No new write endpoint — `entries-create` is already one of RNF09's counted 5 endpoints (its 3 base failure scenarios already covered by RF01's own tests); this unit adds scenario-table rows specific to the bookmark path (idempotent-retry outcome, `AuthExpiredFailure` → `reauthRequired`) on top of, not instead of, that existing coverage (contracts/create-entry-usecase-chat-extension.md). |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/008-chat-message-bookmark/
├── plan.md                                          # This file
├── research.md                                      # Phase 0 output
├── data-model.md                                    # Phase 1 output
├── quickstart.md                                     # Phase 1 output
├── contracts/                                        # Phase 1 output
│   ├── create-entry-usecase-chat-extension.md
│   ├── chat-repository-bookmark-extension.md
│   └── chat-bloc-bookmark-extension.md
└── tasks.md                                          # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
└── lib/
    ├── core/
    │   ├── design_tokens.dart                         # + sizeBookmarkIcon, spacingBookmarkGap (research.md R7)
    │   └── di/
    │       └── service_locator.dart                   # ChatBloc registration + createEntryUseCase param
    └── features/
        ├── entries/
        │   ├── domain/
        │   │   ├── usecases/
        │   │   │   └── create_entry_usecase.dart       # + chatMessageId/occurredAt params (research.md R2)
        │   │   └── repositories/
        │   │       └── entries_repository.dart         # create() signature extended, same params
        │   └── data/
        │       ├── entries_repository_impl.dart        # create() passes the two new params through
        │       └── entries_remote_data_source.dart      # create() sends them in the request body when non-null
        └── chat/
            ├── domain/
            │   ├── entities/
            │   │   └── bookmark_status.dart             # NEW — enum { idle, saving, saved, error }
            │   └── repositories/
            │       └── chat_repository.dart              # + savedEntryIdFor / recordMessageSaved (research.md R1)
            ├── data/
            │   ├── chat_local_cache.dart                 # + chatSavedMessageEntryIds key/methods
            │   └── chat_repository_impl.dart              # + the two new methods, 1 new in-memory field
            └── presentation/
                ├── bloc/
                │   ├── chat_event.dart                    # + BookmarkTapped(messageId)
                │   ├── chat_state.dart                    # + ChatReady.bookmarks, bookmarkStatusFor()
                │   └── chat_bloc.dart                      # + CreateEntryUseCase dep, _onBookmarkTapped, _seedBookmarks
                └── widgets/
                    ├── bookmark_button.dart                # NEW — 4-state icon control
                    └── chat_message_bubble.dart             # extended — bubble+bookmark row for user messages
        └── home/
            └── presentation/
                └── pages/
                    └── home_chat_shell_page.dart            # wires bookmarkStatus/onBookmarkTap into ChatMessageBubble
```

**Structure Decision**: No new feature folder. Every change lands inside `chat/` and `entries/`, the two
folders FR-009 itself names as the ones this unit bridges — `chat/` gains the one new domain enum a bookmark
needs (`BookmarkStatus`) and extends its own repository/bloc/widgets; `entries/` only widens an already-planned
extension point (`CreateEntryUseCase`'s own doc comment has said "RF10 will extend this signature" since RF01
shipped). `core/design_tokens.dart` and `core/di/service_locator.dart` are touched because they are the two
single-source-of-truth files every unit touches when it needs a new visual value or a new DI wire-up — not
because this unit needs its own `core/` subsystem the way RF04's SSE transport did.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified** — no row below is a violation;
> each documents a design choice research.md reasons through in full, kept here for traceability only.

| Addition | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A device-local `savedEntryIdFor`/`recordMessageSaved` pair on `ChatRepository`, instead of deriving "already saved" from `EntriesRepository.cachedEntries` | FR-008 needs a message's bookmark to show `saved` immediately on reopening a conversation/restarting the app; `EntriesRepository.cachedEntries` is a synchronous getter with its own independent, unrelated lazy-load timing (research.md R1) not guaranteed populated by the time `ChatBloc` loads a session | Reading `EntriesRepository.cachedEntries` directly from `ChatBloc` — rejected: couples a chat-local UI concern to a different feature's cache-loading lifecycle, and (per FR-009's own spirit, even though `cachedEntries` is a repository getter, not a creation path) adds a needless second entries-feature dependency to `ChatBloc` for a question `chat/`'s own local cache can already answer on its own |
| No dedicated `SaveChatMessageUseCase` wrapping `CreateEntryUseCase` + `ChatRepository.recordMessageSaved` | `ChatBloc` already has direct, synchronous access to the tapped message's `content`/`createdAt`/`id` — the two calls the bloc's own handler makes have no behavior of their own beyond what `_onBookmarkTapped` already needs inline (research.md R4, the same judgment RF04's own research.md R13 already made for every other `ChatBloc` handler) | A wrapper use case — rejected: zero added testability over mocking `CreateEntryUseCase`/`ChatRepository` directly at the same level `chat_bloc_test.dart` already mocks `ChatRepository`, for one extra file and DI registration |
| Guarding `_onBookmarkTapped` against an optimistic (`isOptimistic == true`) message id as a silent no-op | A message can render its bookmark before the backend assigns its real id (between the optimistic append and `message_created`); sending a `local-<timestamp>` string as `chatMessageId` would violate the OpenAPI field's `format: uuid` and either get rejected or write bad data — neither spec.md nor the prototype (which has no server-roundtrip concept) addresses this race (research.md R6) | Disabling/hiding the bookmark entirely while a message is optimistic — rejected: FR-001 requires the control to appear on every user message with no exceptions; a silent no-op tap, exactly like the already-established "ignore a tap while `saving`" pattern (FR-007), satisfies both FR-001 (always visible) and correctness (never sends a malformed id) without a new visual state |

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `bookmark_status.dart`'s planned import list re-checked: empty beyond Dart core — no `equatable` even needed
  for a plain enum, no `package:flutter`, no `chat/data/` class. RNF06/Principle V confirmed before any code
  exists.
- `ChatBloc`'s planned constructor re-checked: `ChatRepository` + `ConnectivityChecker` (unchanged) +
  `CreateEntryUseCase` (new) — no `EntriesRepository`, no `EntriesRemoteDataSource`, no second bloc. FR-009's
  "never directly import a repository or data source belonging to the entries feature" holds by construction
  and is now also mechanically checked by `test/architecture/no_cross_feature_data_imports_test.dart` (T042).
- Re-checked `EntriesRemoteDataSource.create()`'s extended request-body construction against the OpenAPI
  schema: `chatMessageId`/`occurredAt` are both already-declared, optional, correctly-typed fields — nothing
  sent that the contract doesn't already define (Principle III).
- Re-checked that every existing caller of `CreateEntryUseCase`/`EntriesRepository.create`/
  `EntriesRemoteDataSource.create` (`SaveTextEntryUseCase`, `ConfirmEntrySaveUseCase`, and their manual/audio/
  photo call sites) omits both new named parameters and is therefore byte-for-byte behaviorally unchanged — no
  regression risk to RF01/RF02.
- Re-checked the two new `DesignTokens` constants against the prototype's own inline bookmark styles
  (16 px icon, 6 px gap) — exact transcription, confirmed in research.md R7.
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file,
  or calls an AI provider directly — Principle III remains intact.

No new violations. Gate remains PASS.
