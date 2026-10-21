# Implementation Plan: P-RF04 — Interactive chat with memory (RAG)

**Branch**: `007-chat-memory-rag` (spec directory only — no git branch exists; none of this repo's extension
hooks are configured, per spec.md's own header)

**Date**: 2026-10-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-chat-memory-rag/spec.md`, `docs/input/requirements.md` §1
(RF04), §6.3 (`chat-sessions-create`/`chat-sessions-list`/`chat-messages-list`/`chat-messages-send`/
`chat-messages-retry`), §8 (data model reference), §9 (stack), §10 (no new fixed parameter for this unit),
§13; `docs/input/backend/api/openapi.yaml`'s `/chat/sessions*` schemas; `docs/input/backend/error-taxonomy.md`;
`docs/input/backend/README.md`'s function-name mapping; `docs/input/prototype/prototype-extract.md` §§2.2
("Tela 1 — Home/Chat", "Tela 3 — Menu lateral"), 3, 4, 6; and `.specify/memory/constitution.md`. Depends on
F000 (`specs/001-foundation/`) and RF03 (`specs/002-biometric-auth-vault/`), both already implemented — this
is the unit that makes Home/Chat's currently-inert, fully-disabled composer (F000's own scaffold,
`home_chat_shell_page.dart`) and the side menu's currently-static `AppDrawer` actually work.

## Summary

Home/Chat gains a live, persisted conversation with the backend's RAG-grounded agent
(`POST /chat/sessions/:id/messages`, SSE: `message_created -> context -> token* -> done|error`), and the side
menu's `AppDrawer` gains a paginated, offline-cached "CONVERSAS" list (`GET /chat/sessions`) plus a working
"Novo Chat" action. A new feature folder, `lib/features/chat/`, is added with its own three-layer structure:
`ChatSession`/`ChatMessage`/`ChatSessionsPage`/`ChatStreamEvent`/`ChatTitleDeriver` (domain), `ChatRemoteDataSource`/
`ChatLocalCache`/`ChatRepositoryImpl` (data), and two blocs — `ChatBloc` (the one live conversation: streaming,
retry, lazy session creation, composer gating) and `ChatSessionsBloc` (the side menu's own paginated list,
mirroring `RecordsBloc`'s RF07-established shape almost exactly, research.md R7). `core/network/ApiClient`
gains one new, chat-agnostic method, `sseStream()`, built on `dio`'s own `ResponseType.stream` with a
hand-rolled SSE frame parser (research.md R1) — no new package. `core/network/ConnectivityChecker` gains a
live `onConnectivityChanged` stream (research.md R8), layered on top of (not replacing) the existing
synchronous `hasConnection()` pre-check every write path in this app already uses. A new, Keychain-backed
`ChatLocalCache` (mirroring `EntriesLocalCache`'s own pattern) persists the session list, each individually-
opened session's message history, and the last-active session id, satisfying spec.md's Clarification 3
(offline browsing covers every previously-opened conversation, not just the one open at disconnect) and its
own Assumptions (resuming the last conversation on app restart). A new chat message or its own session is
never created eagerly — only lazily, at the moment a first message is actually sent (FR-010) — and the title
sent with that creation call is derived client-side from the message's own text by a new, pure
`ChatTitleDeriver` (research.md R6), since the backend has no auto-titling or rename endpoint of its own. No
new `go_router` route is added: Home/Chat stays the one existing, unparameterized `/home` screen, swapping its
displayed conversation in place via the two blocs it's now provided with (research.md R7) — "Novo Chat" and
selecting a past conversation from the drawer are both in-place state transitions, not navigations.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000/RF01/RF02/RF03/RF06/RF07.

**Primary Dependencies**: No additions. Reuses the full existing stack — `flutter_bloc`, `fpdart`, `get_it`,
`equatable`, `dio` (via `ApiClient`, extended with `sseStream()`), `go_router` (no new route), `flutter_secure_storage`
(for the new `ChatLocalCache`), `connectivity_plus` (its own `onConnectivityChanged` stream, previously
unused — `ConnectivityChecker` only ever called `checkConnectivity()` once per check before this unit); dev-only
`mocktail`, `bloc_test`. SSE is consumed via a ~30-line hand-rolled parser over `dio`'s existing byte-stream
support, explicitly chosen over any third-party SSE package (research.md R1) — the OpenAPI contract's own
schema for both SSE operations is `content: text/event-stream` / `{type: string}`, i.e. genuinely no typed
shape to generate a client from.

**Storage**: One new on-device store, `ChatLocalCache` (research.md R4) — three independent
`flutter_secure_storage` keys (`chatSessionsLocalCache`, `chatMessagesLocalCache`, `chatLastActiveSessionId`),
same Keychain-backed, JSON-encoded mechanism `EntriesLocalCache` (RF01) already established for personal
content. No local database, no new third-party persistence package.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter (RNF07), now additionally exercising
`chat_title_deriver.dart` (pure), `ChatMessage`'s status-transition shape, `ChatRepositoryImpl`'s
silent-refresh-and-retry branches (both the non-streaming shape reused verbatim from `EntriesRepositoryImpl`,
and the new first-frame-only streaming variant, research.md R3), and `ApiClient.sseStream()`'s own frame
parser (a `core/` addition — `test/core/network/`, mirroring where `error_mapper_test.dart`/similar already
live). `no_bloc_imports_bloc_test.dart` and `domain_purity_test.dart` both run unmodified against the new
`lib/features/chat/` folder with no exceptions needed.

**Target Platform**: iOS, portrait only — unchanged. No native project file touched.

**Project Type**: Same single Flutter mobile app. One new feature folder, `lib/features/chat/`
(domain/data/presentation, Principle V), plus two cross-cutting `core/network/` additions
(`ApiClient.sseStream()`/`SseFrame`, `ConnectivityChecker.onConnectivityChanged`) and in-place extensions to
`lib/features/home/` (`home_chat_shell_page.dart`'s composer, `app_drawer.dart`'s "CONVERSAS" section) and
`lib/core/routing/app_router.dart` (`/home`'s builder now wraps `MultiBlocProvider`). No backend/server code,
no change to `docs/input/backend/api/openapi.yaml`. No touch to `entries/`/`records/` — this unit never calls
`POST /entries` (FR-003/FR-014; that wiring belongs to RF10, explicitly out of scope).

**Performance Goals**: RNF01 unchanged. The optimistic local user+assistant placeholder pair (research.md R5)
is what keeps "a local action is reflected in the UI in under 100 ms" true for message-send despite the
network round-trip and SSE latency that necessarily follow it.

**Constraints**:
- No RF08 (proactive insight card)/RF10 (save-as-entry button)/persona-as-an-active-setting (extension) —
  `personaSnapshot` is read and stored exactly as the backend returns it at session creation, with no UI to
  change it (FR-014).
- No backend/contract/config change (FR-014) — `sseStream()`'s request shape and every parsed field name
  (research.md R2) are this app's own typed wrapper around what `docs/input/backend/api/openapi.yaml` and its
  own documented SSE sequence already describe; nothing new is sent the contract doesn't already define, and
  where the contract is silent on exact SSE field names, research.md documents the inferred shape explicitly
  as a judgment call rather than a verified fact.
- Clean Architecture, 3 layers per feature (Principle V) — `chat/domain/` imports only `equatable`/`fpdart`;
  no `package:flutter`, no `chat/data/` class (confirmed against `domain_purity_test.dart`, unmodified).
  `ChatBloc`/`ChatSessionsBloc` depend only on `ChatRepository` (+ `ConnectivityChecker` for `ChatBloc` alone)
  — neither imports the other, nor `SessionBloc` (research.md R7; `no_bloc_imports_bloc_test.dart` unmodified,
  reinforced manually since both blocs sit in the same feature and so aren't mechanically checked against each
  other by that cross-feature-only test).
- "A single conversation never has two responses in flight at once" (FR-007) — the composer disables itself
  while `ChatReady.awaitingResponse` is true; no concurrent-request/generation-counter machinery is needed
  because no second write can even be dispatched while it's disabled (research.md R9).
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — every new widget
  (chat bubbles, offline banner, composer) reuses existing tokens only (data-model.md's mapping table); zero
  new color/spacing/radius tokens needed, since the prototype's own chat-screen palette (`colorChatBubbleUser`,
  `colorInfoOffline`, `colorError`, etc.) was already added to `design_tokens.dart` during F000.

**Scale/Scope**: 1 new feature folder (`chat/`) with 5 domain entities/helpers, 1 repository interface, 2 data
classes + 1 repository impl, 2 blocs (+events/states), 5 new presentation widgets; 2 extended `core/network/`
classes (`ApiClient`, `ConnectivityChecker`); 2 existing `home/` files extended in place
(`home_chat_shell_page.dart`, `app_drawer.dart`); 1 route builder changed (`app_router.dart`'s `/home`); 5 new
DI registrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only. Every spot this plan resolves by reasonable technical judgment rather than reopening one of spec.md's own three already-resolved Clarifications — the SSE transport mechanism and inferred payload shapes (research.md R1/R2), mid-stream auth-expiry handling (R3), the local-cache shape (R4), optimistic local ids (R5), the title-preview length (R6), the two-bloc split and routing (R7), live-vs-synchronous offline handling (R8), single-flight gating (R9), retry's position-matching (R10), the GET-sourced `streaming`-status edge case (R11), the client-side length cap (R12), and why no extra use-case layer is introduced (R13) — is each built directly on spec.md's own FRs/Assumptions/Key Entities wording, never reopening a resolved Clarification. |
| II. Fixed Technology Stack | PASS | No new package. `flutter_bloc`/`fpdart`/`get_it`/Clean Architecture unchanged; SSE and live connectivity are both built on packages already in `pubspec.yaml` (`dio`, `connectivity_plus`). |
| III. Backend Boundary | PASS | Only already-contracted functions called (`chat-sessions-create`, `chat-sessions-list`, `chat-messages-list`, `chat-messages-send`, `chat-messages-retry` — `docs/input/backend/README.md`'s own path→function table); no AI provider called directly by the app (the backend's own Claude Sonnet 5/Voyage AI calls stay entirely server-side, consumed here only as the SSE response). |
| IV. Design Token Discipline & Visual Fidelity | PASS | Every new widget reuses existing `DesignTokens` entries only (data-model.md's mapping table, sourced from prototype-extract.md §§2.2/3/6's own described chat-bubble/offline-banner/send-error-banner components) — zero new tokens. |
| V. Clean Architecture Folder Convention | PASS | `chat/domain/` imports only `equatable`/`fpdart` — confirmed against `domain_purity_test.dart` (unmodified, no exception needed). `ChatBloc`/`ChatSessionsBloc` each depend on exactly the repository (+ `ConnectivityChecker` for the former) they need, no cross-bloc import. |
| RNF01 (latency) | PASS | The optimistic local placeholder pair (research.md R5) is this unit's own mechanism for keeping message-send's *local* reflection under 100 ms despite the necessarily-slower network/SSE round-trip that follows it; any fetch exceeding 300 ms (session/history loads) shows the existing loading-indicator convention. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF04 | Backend-side; this unit's one write surface (`chat-messages-send`/`retry`) sends only the user's own typed text, same as every other authenticated write already does — no PII-detection logic is added here (RNF02 is explicitly backend-only, and chat messages are never run through the entries/PII pipeline at all per FR-003). |
| RNF05 (hard delete) | N/A to RF04 | Belongs to Settings/RNF05's own unit. |
| RNF06 (layer violations) | PASS | No `chat/domain/` file imports Flutter or a `chat/data/` class; neither bloc imports the other's file, nor `SessionBloc`'s — `no_bloc_imports_bloc_test.dart`/`domain_purity_test.dart` both continue to pass unmodified. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `chat_title_deriver.dart` is a pure, total function, as directly testable as `date_range_filter.dart` (RF06); `ChatMessage`'s status-transition shape and `ChatStreamEvent`'s sealed variants are plain data, trivially covered; `ChatRepositoryImpl`'s retry branches are testable against the same `mocktail` fakes `EntriesRepositoryImpl`'s own tests already use the pattern for. |
| RNF08 (visual fidelity) | PASS | Chat bubbles (user/assistant/streaming/failed), the offline banner, and the side menu's "CONVERSAS" section match prototype-extract.md §§2.2/6 exactly — no approximated layout or invented component beyond what the prototype already names. |
| RNF09 (Either + 15/15 error scenarios) | PASS (gate carried into tasks) | RF04 adds exactly one write endpoint whose *outcome shape* differs from every prior unit's (`chat-messages-send`'s streaming `Either<Failure, ChatStreamEvent>` per-frame, rather than a single `Either<Failure, T>`) — but it is still fully `Either`-typed throughout (Principle II), and its 3 required failure scenarios (timeout, malformed response, no-connection) are each exercised at the transport layer (`contracts/sse-transport-extension.md`'s own scenario table, implemented by tasks.md's T003) exactly as rigorously as any single-shot write endpoint's. `chat-sessions-create` is this unit's other write endpoint, tested the ordinary single-`Either` way. RNF09's project-wide "5 write endpoints × 3 failures = 15" tally gains these 2 (10/15 cumulative with RF01/RF02's existing 2 already counted — the full 5-endpoint tally completes across RF05/RF08/RF09/RF10's own later units). |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/007-chat-memory-rag/
├── plan.md                                  # This file
├── research.md                              # Phase 0 output
├── data-model.md                            # Phase 1 output
├── quickstart.md                            # Phase 1 output
├── contracts/                               # Phase 1 output
│   ├── sse-transport-extension.md
│   ├── chat-repository.md
│   ├── chat-bloc.md
│   └── chat-sessions-bloc.md
└── tasks.md                                 # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
└── lib/
    ├── core/
    │   ├── network/
    │   │   ├── api_client.dart                          # + sseStream() (research.md R1)
    │   │   ├── sse_frame.dart                            # NEW — SseFrame
    │   │   └── connectivity_checker.dart                 # + onConnectivityChanged (research.md R8)
    │   ├── di/
    │   │   └── service_locator.dart                      # + Chat registrations
    │   └── routing/
    │       └── app_router.dart                           # /home's builder wraps MultiBlocProvider
    └── features/
        ├── chat/
        │   ├── domain/
        │   │   ├── entities/
        │   │   │   ├── chat_session.dart                 # NEW — ChatPersona, ChatSession
        │   │   │   ├── chat_message.dart                 # NEW — ChatRole, ChatMessageStatus, ChatMessage
        │   │   │   ├── chat_sessions_page.dart            # NEW — mirrors EntriesPage
        │   │   │   ├── chat_stream_event.dart             # NEW — sealed ChatStreamEvent
        │   │   │   └── chat_title_deriver.dart            # NEW — pure title-preview function (research.md R6)
        │   │   └── repositories/
        │   │       └── chat_repository.dart               # NEW
        │   ├── data/
        │   │   ├── chat_remote_data_source.dart           # NEW — calls + SSE frame→event mapping
        │   │   ├── chat_local_cache.dart                  # NEW — Keychain-backed (research.md R4)
        │   │   └── chat_repository_impl.dart              # NEW
        │   └── presentation/
        │       ├── bloc/
        │       │   ├── chat_event.dart / chat_state.dart / chat_bloc.dart                  # NEW
        │       │   └── chat_sessions_event.dart / chat_sessions_state.dart / chat_sessions_bloc.dart  # NEW
        │       └── widgets/
        │           ├── chat_message_bubble.dart           # NEW
        │           ├── chat_composer.dart                 # NEW — replaces _ComposerBar
        │           └── chat_offline_banner.dart           # NEW
        └── home/
            └── presentation/
                ├── pages/
                │   └── home_chat_shell_page.dart          # extended — live ChatBloc wiring
                └── widgets/
                    └── app_drawer.dart                     # extended — "CONVERSAS" section + "Novo Chat"
```

**Structure Decision**: One new feature folder, `chat/`, following the exact three-layer convention every
prior unit already established — no deviation. The two `core/network/` additions
(`ApiClient.sseStream()`/`SseFrame`, `ConnectivityChecker.onConnectivityChanged`) live there rather than inside
`chat/` because neither is chat-specific in shape (any future SSE-consuming or connectivity-reactive unit
reuses them as-is, same reasoning RF01 already used placing `ConnectivityChecker` itself in `core/` rather than
inside `capture/`). `home/` is extended rather than folded into `chat/` because `home_chat_shell_page.dart`/
`app_drawer.dart` already exist as F000's own scaffold in that folder — moving them would be a gratuitous
rename with no behavioral benefit.

## Complexity Tracking

| Addition | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Hand-rolled SSE parsing in `ApiClient` (research.md R1) | `chat.messages.send`/`.retry` are this app's first and only streaming endpoints; the OpenAPI contract gives them no typed response shape (`text/event-stream`/`{type: string}`) for `call()`'s existing JSON-only path to handle | A third-party SSE package — rejected: introduces a second HTTP-stack assumption alongside `dio`, for a 5-event-type protocol spoken to exactly one backend (research.md R1) |
| Two blocs (`ChatBloc` + `ChatSessionsBloc`) instead of one | The live conversation (streaming, retry, composer gating) and the side menu's paginated list are independently-failing, independently-paginated concerns — exactly the two-concerns split `RecordsBloc` staying independent of `SessionBloc`/`VaultBloc` already establishes as this codebase's norm | One combined bloc — rejected: conflates two state shapes with genuinely different failure/pagination semantics into one, as reasoned in research.md R7 |
| A new `ChatLocalCache` (3 keys) rather than reusing `EntriesLocalCache`'s shape as-is | Chat needs to cache *two* independent things (a session list and N sessions' individual message histories) plus a small scalar (`lastActiveSessionId`) — `EntriesLocalCache` only ever caches one flat list | Reusing `EntriesLocalCache` directly — rejected: it has no concept of "per-session" keying, and bolting one on would make it do two unrelated jobs for two unrelated features |

*No entry needed beyond these three — each is either this unit's first genuinely new mechanism (SSE) or a
direct, justified extension of an already-proven pattern (two blocs mirroring `RecordsBloc`'s own split; a
cache mirroring `EntriesLocalCache`'s own rationale).*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `chat/domain/entities/*.dart` and `chat/domain/repositories/chat_repository.dart` were re-checked against
  their actual planned imports: `equatable`, `fpdart` (for `ChatRepository`'s `Either`/`Stream` signatures),
  and `core/network/failure.dart` only. No `package:flutter`, no `chat/data/` class — RNF06/Principle V
  confirmed before any code exists.
- `ChatBloc`'s dependency surface was re-checked: exactly `ChatRepository` + `ConnectivityChecker` — no
  `SessionBloc`, no `ChatSessionsBloc` import. `ChatSessionsBloc`'s surface: exactly `ChatRepository` alone.
  Neither file appears in the other's import list (manually confirmed, since `no_bloc_imports_bloc_test.dart`
  only mechanically checks *across* `features/` folders, not within one).
- Re-checked `ApiClient.sseStream()`'s exception handling against `call()`'s existing `_mapException` — reused
  verbatim, no second, divergent failure-mapping implementation introduced.
- Re-checked that `ChatTitleDeriver`, the one domain helper RNF07 specifically needs to be independently
  testable, has zero constructor dependencies and zero I/O — confirmed pure in data-model.md's own listing.
- Re-checked the routing change (`app_router.dart`'s `/home` builder) against Principle V/research.md R7: no
  new `go_router` route, no `sessionId` path parameter — `AppRoutes.home` itself is unchanged.
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file,
  or calls an AI provider directly — Principle III remains intact. No chat code path reaches `POST /entries`
  or any `entries/`-layer class — FR-003/FR-014 hold by construction (confirmed by `chat/`'s own import list
  containing nothing from `features/entries/`).

No new violations. Gate remains PASS.
