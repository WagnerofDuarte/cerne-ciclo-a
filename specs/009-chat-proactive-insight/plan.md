# Implementation Plan: P-RF08 — Proactive insights (mechanism)

**Branch**: `009-chat-proactive-insight` (spec directory only — no git branch exists; none of this repo's
extension hooks are configured, per spec.md's own header)

**Date**: 2026-10-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-chat-proactive-insight/spec.md`, `docs/input/requirements.md`
§1 (RF08), §2.2 (prototype's "Tela 1 — Insight" state), §6.3 (`chat-insight-create`'s request/response schema),
§9/§10 (fixed trigger parameters: N=5 messages, T=2 min), §12 (delivery order: RF08 after RF04, before
RF05/RF09), §13; `docs/input/backend/api/openapi.yaml`'s `/chat/sessions/{id}/insight` POST schema (`never an
HTTP error; a failure becomes status='failed'`); `docs/input/backend/error-taxonomy.md`;
`docs/input/prototype/prototype-extract.md` §2.2/§3 and the prototype's own source
(`docs/input/prototype/cerne-prototype.html`, the `msg.isInsight` branch's exact markup/styles); and
`.specify/memory/constitution.md`. Depends on RF04 (`specs/007-chat-memory-rag/`, already implemented) for the
composer/turn state machine (`ChatBloc.awaitingResponse`/`_turnGeneration`), the message list `ChatReady`
already renders, and `ConnectivityChecker` — this unit introduces no separate offline-detection mechanism of
its own. RF10 (`specs/008-chat-message-bookmark/`, already implemented) is the most recent prior extension of
the same `ChatBloc`/`ChatReady`/`ChatRepository` seam this plan extends again.

## Summary

The chat screen gains a fully client-orchestrated, ephemeral suggestion mechanism: two independent,
per-viewing-session trigger conditions — a running count of user messages (fires at every new multiple of 5)
and a 2-minute inactivity timer (paused while backgrounded, re-armed from zero on resume) — each call
`POST /chat/sessions/:id/insight` at most once per crossing, deferred until the current turn is idle and
suspended entirely (neither counted nor timed) while a prior attempt is in flight or its resulting card is
still on screen. A successful response (`status: 'ready'`) renders one ochre-spined "INSIGHT" card interleaved
into the existing message list at the point generation started, with a local-only "x" dismiss control; every
other outcome — a transport failure, a 200 response with `status: 'failed'`, or the device being offline when
a trigger condition is satisfied — produces no card and no indicator of any kind, leaving the rest of the
screen completely unaffected (RF08's own "never disrupts the conversation" scope). Nothing about an insight —
shown, dismissed, failed, or skipped — is ever persisted or reconstructed: every counter and the visible card
itself reset to nothing the instant the conversation is left (switched away, backgrounded past this session, or
the app restarts).

All of this lands inside the two files that already own the chat screen's one flow — `ChatBloc`/`ChatReady`
(RF04) gain three new events/handlers and one new nullable state field, with no new bloc, no new domain
usecase, and no new DI registration beyond nothing (the one new network call, `ChatRepository.createInsight`,
reaches the backend through the already-injected `ChatRepository`). `home_chat_shell_page.dart` gains a
`WidgetsBindingObserver`/`RouteAware` pair (mirroring `VaultLifecycleObserver`'s existing app-lifecycle
precedent) to detect backgrounding and Records/Settings navigation, plus one more line on its existing
`onDrawerChanged` callback, so that opening the drawer or navigating away — without ever tearing down the one
`ChatBloc` instance `/home`'s route already keeps alive underneath — pauses the inactivity timer exactly as
FR-010 requires. One new, small widget (`InsightCard`) renders the card; five new, off-grid-value
`DesignTokens` constants cover its spine/padding/icon, transcribed directly from the prototype's own inline
markup, with both of its text styles reused completely unmodified. No change to `records/`, `export/`,
`dashboard/`, any backend file, or any file under `docs/input/`.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from F000/RF01–RF10.

**Primary Dependencies**: No additions. Reuses `flutter_bloc`, `fpdart`, `get_it`, `equatable`, `dio` (via the
already-registered `chat-insight-create` function, called the same way every other non-streaming `ApiClient`
call already is), `go_router` (its existing `observers` constructor parameter, not previously used); dev-only
`mocktail`, `bloc_test`. No `fake_async`/`clock` package added — `Timer`-based tests use the same injectable-
`Duration` seam `RecordsBloc.debounceDuration` already established for RF06 (research.md R4).

**Storage**: None. Unlike every prior `ChatRepository` method, `createInsight` reads and writes no local
cache at all — `ChatLocalCache` is untouched by this unit (FR-009's "never persisted or reconstructed" is
satisfied by *not having* a storage path, not by a cache that happens to be cleared).

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via
`fvm flutter test --coverage`, same `lib/**/domain/**` lcov filter (RNF07) — now additionally exercising
`insight_trigger.dart`'s `InsightTriggerKeyBuilder`/`InsightTrigger` (pure, directly unit-testable) and
`proactive_insight.dart` (a bare equatable value object). `no_bloc_imports_bloc_test.dart` and
`domain_purity_test.dart` both run unmodified against the extended `lib/features/chat/` — no new bloc, no new
flutter/data import in `chat/domain/`. `test/architecture/no_cross_feature_data_imports_test.dart` is
unaffected (this unit touches no cross-feature boundary at all — everything stays inside `chat/` plus two
`core/` files).

**Target Platform**: iOS, portrait only — unchanged. No native project file touched.

**Project Type**: Same single Flutter mobile app. No new feature folder — every change lands inside the one
already-existing folder this unit depends on (`lib/features/chat/`), plus three `core/` touches
(`design_tokens.dart`, `routing/app_router.dart`) and one already-existing presentation file outside `chat/`
(`home/presentation/pages/home_chat_shell_page.dart`, which already wires `ChatBloc`'s UI). No
backend/server code, no change to `docs/input/backend/api/openapi.yaml` (its `/chat/sessions/{id}/insight`
endpoint already exists and is simply called for the first time).

**Performance Goals**: RNF01 is satisfied by construction rather than by a loading indicator — research.md R9
reasons through why no "generating" placeholder is shown even past 300 ms: the call is unrequested and
invisible-until-successful by design (the prototype documents no such state), and every other screen
affordance (composer, scrolling, other messages) stays fully interactive for the call's entire duration
regardless of how long it takes, so there is no user-perceived wait this standard's loading-indicator duty
would otherwise cover.

**Constraints**:
- No RF05 (export)/RF09 (dashboard), no extension feature, no backend/contract/config change (FR-011) —
  `triggerType`/`triggerKey` are the only two request fields sent, both already declared on
  `chat-insight-create`'s OpenAPI schema; nothing new is sent that the contract doesn't already define.
- The trigger parameters (N=5 messages, T=2 min) are the fixed values from requirements.md §10 — "not to be
  reinterpreted." The one `Duration` constructor parameter added to `ChatBloc` exists purely as a test-speed
  seam (research.md R4), never a product-facing configuration surface; no Settings UI is added for it
  (FR-011).
- Clean Architecture, 3 layers per feature (Principle V) — the two new domain files
  (`insight_trigger.dart`, `proactive_insight.dart`) are plain `Equatable` value objects and a stateless static
  builder: no `package:flutter`, no `chat/data/` import (confirmed against `domain_purity_test.dart`,
  unmodified). `ChatBloc`'s dependency surface is unchanged (zero new constructor dependencies beyond the
  testability-only `Duration`) — no new cross-bloc import, no new cross-feature import.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — two of the
  insight card's text styles are reused completely unmodified (an exact match already existed); five new,
  exact-value tokens cover the spine width and padding/icon values with no match on the existing 4 dp grid
  (`widthInsightSpine`, `spacingInsightPaddingLeft`, `spacingInsightPaddingVertical`,
  `spacingInsightHeaderGap`, `sizeInsightDismissIcon`), mirroring the precedent RF01–RF10 already set for
  off-grid, element-specific values read straight off the prototype.
- Nothing about an insight is ever persisted (FR-009) — `createInsight` touches no cache, and `ChatReady.insight`
  resets to `null` on every fresh `ChatReady` construction (`_onStarted`/`_onConversationSelected`/
  `_onNewConversationRequested`), the same "rebuilt from scratch, never patched forward" discipline RF10's own
  `_seedBookmarks` already established for a different per-session field.
- FR-007's offline pre-check is a deliberate, spec-mandated *difference* from RF10's own bookmark flow
  (which has no pre-check, research.md R8) — this plan does not generalize one unit's precedent onto the other
  where the requirements text itself diverges.

**Scale/Scope**: 0 new feature folders. 2 new domain files (`insight_trigger.dart`, `proactive_insight.dart`),
1 new presentation widget (`insight_card.dart`); 6 existing files extended (`chat_repository.dart`,
`chat_repository_impl.dart`, `chat_remote_data_source.dart`, `chat_event.dart`/`chat_state.dart`/`chat_bloc.dart`
count as one cohesive bloc extension, `home_chat_shell_page.dart`, `app_router.dart`, `design_tokens.dart`); 5
new `DesignTokens` constants; 0 new DI registrations, 0 reordered.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only throughout. Every judgment call below (research.md R1–R13) fills a gap spec.md's own Clarifications leave for "the planning phase" (triggerKey's exact construction, the pending-trigger/anchor-index mechanics) or that neither `requirements.md` nor the prototype addresses at all (the null-session inactivity edge case, R6; whether a loading placeholder exists at all, R9) — none reopens any of spec.md's three already-resolved Clarifications (ephemeral-only state; re-arming/suspension semantics; no failure indicator). |
| II. Fixed Technology Stack | PASS | No new package. `flutter_bloc`/`fpdart`/`get_it`/`go_router` (an already-used constructor parameter) are all already project dependencies. |
| III. Backend Boundary | PASS | Only the already-contracted `chat-insight-create` function is called, with exactly the two fields its OpenAPI schema already declares as required; no AI provider called directly; no OpenAPI/`.env`/config file touched. |
| IV. Design Token Discipline & Visual Fidelity | PASS | Two of the insight card's text styles are reused with zero modification (an exact prototype match already existed); the five new size/spacing tokens are exact values transcribed from the prototype's own inline insight markup (research.md R12), not approximations. |
| V. Clean Architecture Folder Convention | PASS | `insight_trigger.dart`/`proactive_insight.dart` import nothing beyond Dart core + `equatable` — confirmed against `domain_purity_test.dart`, unmodified. `ChatBloc`'s dependency surface is unchanged. |
| RNF01 (latency) | PASS (deviation documented) | See Complexity Tracking — this unit deliberately shows no loading indicator for `createInsight` regardless of call duration, a documented departure from RNF01's literal "any network call >300 ms MUST show a loading indicator" text, justified by the call being unrequested and invisible-by-design (research.md R9); every other screen affordance remains fully interactive throughout, satisfying RNF01's "local action <100 ms" clause for everything the user *does* touch. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF08 directly | The insight's own generation (PII/RAG/model choice) is entirely backend-owned (Claude Haiku 4.5, per requirements.md §9); this unit adds no client-side PII logic, no new retention policy (quite the opposite — FR-009 forbids retention), RLS unaffected. |
| RNF05 (hard delete) | N/A | Belongs to Settings/RNF05's own unit. |
| RNF06 (layer violations) | PASS | `chat/domain/` stays flutter/data-free; `ChatBloc` imports no new cross-feature class at all (its one new repository call is on the already-injected `ChatRepository`) — confirmed by this unit's planned import list touching only `chat/` and two `core/` files. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `insight_trigger.dart`/`proactive_insight.dart` are both directly, trivially unit-testable (no `bloc_test`/`mocktail` needed) — a cleaner coverage contribution than the enum-only additions prior units made. |
| RNF08 (visual fidelity) | PASS | Insight card background/radius/shadow/both text styles/dismiss-icon color all reuse existing tokens verbatim; the five new tokens are exact transcriptions, not approximations (research.md R12). |
| RNF09 (Either + 15/15 error scenarios) | PASS (gate carried into tasks) | `chat-insight-create` is a new write endpoint; this unit gives it full timeout/malformed/no-connection coverage (`contracts/chat-repository-insight-extension.md`) on top of the project's existing cumulative tally, without asserting a specific final fraction this plan cannot verify against units not yet built (research.md R13). |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/009-chat-proactive-insight/
├── plan.md                                          # This file
├── research.md                                      # Phase 0 output
├── data-model.md                                    # Phase 1 output
├── quickstart.md                                     # Phase 1 output
├── contracts/                                        # Phase 1 output
│   ├── chat-repository-insight-extension.md
│   └── chat-bloc-insight-extension.md
└── tasks.md                                          # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
└── lib/
    ├── core/
    │   ├── design_tokens.dart                         # + widthInsightSpine, spacingInsightPaddingLeft,
    │   │                                               #   spacingInsightPaddingVertical, spacingInsightHeaderGap,
    │   │                                               #   sizeInsightDismissIcon (research.md R12)
    │   └── routing/
    │       └── app_router.dart                        # + chatRouteObserver, GoRouter(observers: [...])  (research.md R10)
    └── features/
        ├── chat/
        │   ├── domain/
        │   │   ├── entities/
        │   │   │   ├── insight_trigger.dart            # NEW — InsightTriggerType, InsightTrigger, InsightTriggerKeyBuilder
        │   │   │   └── proactive_insight.dart           # NEW — ProactiveInsight {content, anchorIndex}
        │   │   └── repositories/
        │   │       └── chat_repository.dart              # + createInsight() (research.md R7)
        │   ├── data/
        │   │   ├── chat_remote_data_source.dart          # + createInsight(), status/errorCode parsing
        │   │   └── chat_repository_impl.dart              # + createInsight() (no cache interaction)
        │   └── presentation/
        │       ├── bloc/
        │       │   ├── chat_event.dart                    # + ChatForegroundChanged, InsightInactivityTimerFired, InsightDismissed
        │       │   ├── chat_state.dart                    # + ChatReady.insight, copyWith(clearInsight)
        │       │   └── chat_bloc.dart                      # + insight trigger/suspension state machine (research.md R1–R6)
        │       └── widgets/
        │           └── insight_card.dart                   # NEW — ochre-spine card, dismiss control
        └── home/
            └── presentation/
                └── pages/
                    └── home_chat_shell_page.dart            # + WidgetsBindingObserver/RouteAware, drawer hook, card interleaving
```

**Structure Decision**: No new feature folder. Every change lands inside `chat/`, the one folder this unit's
own depends-on list (RF04/RF10) already lives in, plus the three `core/`-and-adjacent files every unit touches
when it needs a new visual value, a new route observer, or to wire a screen-level lifecycle hook — not because
this unit needs its own `core/` subsystem. `home_chat_shell_page.dart` is touched because it is the one widget
that already owns `ChatBloc`'s UI wiring (the `Scaffold`, the `ListView.builder`, the `onDrawerChanged`
callback) — the same file RF10 already extended for its own bookmark wiring.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified.** The first two rows below document
> design choices, not violations. The third (no loading indicator past RNF01's 300 ms threshold) is a
> deliberate, written deviation from RNF01's literal text, kept here — per Governance's deviation-justification
> requirement — rather than argued away inside the Constitution Check's PASS cell.

| Addition | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A `RouteObserver<PageRoute<void>>` on `GoRouter`, plus `RouteAware` on `_HomeChatShellPageState` | FR-010 requires pausing the inactivity timer when the user pushes to Records/Settings and resuming it on return, and `ChatBloc`'s one instance is kept alive underneath that push (never torn down) — Flutter's standard mechanism for "did another page cover me / did I return to the top" is exactly `RouteObserver`/`RouteAware`, and this codebase has no existing substitute | Tearing down and recreating `ChatBloc` on every navigation away/back so "resume" is just "re-run `_onStarted`" — rejected: not how `app_router.dart` is structured today, and restructuring it would touch RF04's existing, shipped route-provisioning shape for a unit whose own scope is additive only |
| Six private, non-state bookkeeping fields on `ChatBloc` (`_insightMessageCount`, `_insightInFlight`, `_pendingInsightTrigger`, `_insightGeneration`, `_isForegrounded`, `_inactivityTimer`) instead of a dedicated tracker class | Every one of these fields is specific to this one screen's one flow and needs no independent testable contract beyond "did `ChatBloc` emit/call what the scenario says" — the identical judgment RF04's own `_turnGeneration` already represents | A dedicated `InsightTriggerTracker`/`InsightTriggerBloc` — rejected (research.md R1): it would either duplicate `ChatBloc`'s own `awaitingResponse`/`messages.length` reads or import `ChatBloc` directly, which the "no BLoC imports another BLoC" convention forbids for a bloc and which a plain domain class has no clean way around either |
| No "generating" loading-indicator state, even past RNF01's 300 ms threshold | The prototype documents no such state; every other screen affordance stays fully interactive for the call's whole duration, so there is no user-perceived wait to cover, and a placeholder that silently vanishes on failure would itself be the disruption spec.md's Clarification 3 rules out (research.md R9) | A RNF01-literal placeholder bubble shown past 300 ms, removed on failure — rejected: no acceptance criterion describes its appearance/removal, and it contradicts the "no indicator of any kind" Clarification's spirit even if technically a different UI element from the card itself |

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `insight_trigger.dart`/`proactive_insight.dart`'s planned import lists re-checked: `package:equatable` only —
  no `package:flutter`, no `chat/data/` class. RNF06/Principle V confirmed before any code exists.
- `ChatBloc`'s planned constructor re-checked: `ChatRepository` + `ConnectivityChecker` + `CreateEntryUseCase`
  (all unchanged) + one new `Duration` default-valued parameter — no new class dependency, no second bloc, no
  cross-feature import. FR-009's "never persisted" holds by construction: `createInsight` has no cache
  parameter to even thread one through.
- Re-checked `ChatRemoteDataSource.createInsight`'s request-body construction against the OpenAPI schema:
  `triggerType`/`triggerKey` are both already-declared, required, correctly-typed fields — nothing sent that
  the contract doesn't already define (Principle III).
- Re-checked that every existing caller of `ChatRepository`/`ChatRepositoryImpl`/`ChatRemoteDataSource`
  (`ChatBloc`'s own existing handlers, `ChatSessionsBloc`) is unaffected by the new method — it is purely
  additive, called from exactly one new code path (`ChatBloc._startInsightAttempt`).
- Re-checked the five new `DesignTokens` constants against the prototype's own inline insight markup
  (3 dp spine, 20/14/16/14 px padding, 14 dp dismiss icon) — exact transcription, confirmed in research.md R12;
  separately confirmed `textMonoCaption`/`textBodyMd` already match the label/body styles with zero
  modification needed beyond one color override.
- Re-checked that `RouteObserver`/`WidgetsBindingObserver` additions touch only `app_router.dart` (one new
  top-level value, one constructor argument) and `home_chat_shell_page.dart`'s own `State` class — no other
  route's builder, no other screen's lifecycle, is affected.
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file,
  or calls an AI provider directly — Principle III remains intact.

No new violations. Gate remains PASS.
