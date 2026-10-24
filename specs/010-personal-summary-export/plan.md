# Implementation Plan: P-RF05 — Personal summary export

**Branch**: `010-personal-summary-export` (spec directory only — no git branch exists; none of this repo's
extension hooks are configured, per spec.md's own header)

**Date**: 2026-10-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-personal-summary-export/spec.md`, `docs/input/requirements.md`
§1 (RF05), §6.5 (`export-summary-create`/`export-status-get`/`export-download-get`), §8 (data model
reference), §9 (stack), §13; `docs/input/backend/api/openapi.yaml`'s `/export/*` schemas;
`docs/input/backend/export-screen-states.md`; `docs/input/backend/error-taxonomy.md`;
`docs/input/backend/README.md`'s function-name mapping; `docs/input/prototype/prototype-extract.md` §2.5; and
`.specify/memory/constitution.md`. Depends on RF07 (`specs/005-multi-source-timeline/`), already implemented —
this is the unit that makes "Meus Registros"' currently-inert download icon
(`records_page.dart`'s `_Header`, comment "no export behavior in this unit") actually work.

## Summary

"Meus Registros"' download icon gains a bottom sheet (`ExportSheet`) that requests an async export job for
whatever period the screen's own active date filter represents (`POST /export/summary`), polls its status
(`GET /export/{jobId}/status`) every 2 seconds, and — once the job reaches a terminal state — offers a PDF
narrative download and/or a raw-data download (`GET /export/{jobId}/download`), each saved/shared via the OS
share sheet. A new feature folder, `lib/features/export/`, is added with its own three-layer structure:
`ExportJob`/`ExportFormat`/`ExportSheetState` (domain, plus a pure `sheetState` derivation of
`export-screen-states.md`'s table), `ExportRepository`/`ExportFileRepository` (domain interfaces),
`ExportRemoteDataSource`/`ExportRepositoryImpl`/`ExportFileRepositoryImpl` (data), and one bloc, `ExportBloc`
(one new instance per sheet open, research.md R6). `core/network/ApiClient` gains one new, export-agnostic
method, `downloadFile()` — a two-step fetch (our backend's 302, then a header-less GET of the signed Storage
URL) that never forwards this app's own credentials to the Storage host (research.md R1). A new dependency,
`share_plus`, provides the "save or share" affordance no existing package in this app covers. The spec's own
resolved Clarification — a sixth, generic failure state distinct from the prototype's one narrative-only
"Erro" — is implemented as a sixth `ExportSheetState`/`ExportState` value, `erroCompleto`/`ExportFailed`
(research.md R4). `records_page.dart`'s `_Header`/`_RecordsPageState` are extended in place to wire the icon
to the sheet, deriving the period from `RecordsBloc`'s existing `DateRangeOption` via RF06's own
`DateRangeBounds` extension (research.md R8) — no new `RecordsBloc` event/state, no new `go_router` route.

## Technical Context

**Language/Version**: Dart 3.13.4 / Flutter 3.47.5 (stable), pinned via `.fvmrc` — unchanged from
F000/RF01/RF03/RF06/RF07.

**Primary Dependencies**: One addition — `share_plus: ^13.3.1` (research.md R2), the OS share sheet for the
two downloadable files this unit produces. Everything else reuses the full existing stack —
`flutter_bloc`, `fpdart`, `get_it`, `equatable`, `dio` (via `ApiClient`, extended with `downloadFile()`),
`path_provider` (already present for the audio pipeline, reused here for a temp file), `go_router` (no new
route); dev-only `mocktail`, `bloc_test`.

**Storage**: None new. `export_jobs`/their downloaded files are explicitly ephemeral (Key Entities: "never
shown anywhere outside the export sheet") — unlike `EntriesLocalCache`/`ChatLocalCache`, this unit adds no
on-device persistence; a downloaded file lives only in the OS temp directory for the lifetime of the share
sheet.

**Testing**: `flutter_test` + `bloc_test` + `mocktail`, unchanged tooling. Coverage via `fvm flutter test
--coverage`, same `lib/**/domain/**` lcov filter (RNF07), now additionally exercising `export_job.dart`'s pure
`sheetState` mapping (R4), `ExportRepositoryImpl`'s silent-refresh-and-retry branches (reused verbatim from
`EntriesRepositoryImpl`'s shape), and `ApiClient.downloadFile()`'s two-leg redirect/fetch logic (a `core/`
addition — `test/core/network/`, mirroring where `sse_frame`/`error_mapper` tests already live).

**Target Platform**: iOS, portrait only — unchanged. No native project file touched beyond whatever
`share_plus`'s own iOS integration requires at the `Info.plist`/Podfile level (its own install instructions;
no custom native code written by this unit).

**Project Type**: Same single Flutter mobile app. One new feature folder, `lib/features/export/`
(domain/data/presentation, Principle V), one cross-cutting `core/network/` addition
(`ApiClient.downloadFile()`), and in-place extensions to `lib/features/records/presentation/pages/
records_page.dart` (`_Header`/`_RecordsPageState`, research.md R8) and `lib/core/di/service_locator.dart`. No
backend/server code, no change to `docs/input/backend/api/openapi.yaml`.

**Performance Goals**: RNF01 unchanged. The sheet's "Pendente" state appears synchronously the instant the
download icon is tapped (before the `POST` even resolves), satisfying "a local action is reflected in the UI
in under 100 ms"; the `POST`/polling/download calls themselves are each already covered by the loading-
indicator convention their own sheet states already are (spinner/progress bar), satisfying "any network call
taking longer than 300 ms MUST show a loading indicator" by construction — there is no network call in this
unit's flow that is ever silent.

**Constraints**:
- No manual-tag/category filtering or any other extension feature (FR-013) — the export sheet has no period
  picker, no persona/categorization control of its own.
- No functionality belonging to a unit later than RF05 in the build order (FR-013) — RF09's dashboard
  narrative (`GET /dashboard/narrative`) is a distinct endpoint, never touched here.
- No backend/contract/config change (FR-013) — `downloadFile()`'s two-leg shape and every parsed field name
  (research.md R1/contracts/export-repository.md) are this app's own typed wrapper around what
  `docs/input/backend/api/openapi.yaml` already describes.
- Clean Architecture, 3 layers per feature (Principle V) — `export/domain/` imports only
  `equatable`/`fpdart`; no `package:flutter`, no `export/data/` class. `ExportBloc` depends only on
  `ExportRepository`/`ExportFileRepository` — never `SessionRepository` directly (research.md R7), never
  `RecordsBloc` (no cross-bloc import).
- FR-011's concurrency guard is satisfied by construction, not by a shared/persisted job id: a sheet-scoped,
  `registerFactory`-registered `ExportBloc` (research.md R6) plus a simple tap-guard in
  `_RecordsPageState` (research.md R8/contracts/records-header-export-extension.md) — no second
  `POST /export/summary` can fire for the same tap, and no in-flight job is polled once its sheet is gone.
- Zero visual values hardcoded outside `lib/core/design_tokens.dart` (Principle IV/RNF08) — every new widget
  reuses existing tokens only (data-model.md's widget list) — zero new color/spacing/radius tokens needed,
  since `colorAccent`/`colorSuccess`/`colorError` already exist from F000/RF06/RF07.

**Scale/Scope**: 1 new feature folder (`export/`) with 1 domain entity + 1 pure derivation extension, 2
repository interfaces, 2 data classes + 2 repository impls, 1 bloc (+events/states), 7 new presentation
widgets; 1 extended `core/network/` method (`ApiClient.downloadFile()`); 1 existing `records/` file extended
in place (`records_page.dart`); 1 new dependency (`share_plus`); 5 new DI registrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see bottom of this section.*

| Principle / Standard | Status | Notes |
|---|---|---|
| I. Product Source of Truth | PASS | `docs/input/` read-only. Every spot this plan resolves by reasonable technical judgment rather than reopening spec.md's own already-resolved Clarification (the FR-007 sixth state) — the download-transport mechanism (research.md R1), the file-save/share package (R2), the poll interval (R3), the sheet-state derivation and its sixth value (R4), routing non-empty-period `POST` failures to FR-007 (R5), the sheet-scoped-bloc concurrency shape (R6), the reauth wiring (R7), and period-bounds plumbing (R8) — is each built directly on spec.md's own FRs/Assumptions/Key Entities wording, never reopening the resolved Clarification. |
| II. Fixed Technology Stack | PASS | No change to `flutter_bloc`/`fpdart`/`get_it`/Clean Architecture. One new dependency, `share_plus` — squarely inside Principle II's own "choices not fixed here... local cache... secure storage" open-decision category (no fixed file-share package is named anywhere in `docs/input/`), the same category `image_picker`/`record`/`whisper_ggml` were already added under. |
| III. Backend Boundary | PASS | Only already-contracted functions called (`export-summary-create`, `export-status-get`, `export-download-get` — `docs/input/backend/README.md`'s own path→function table); no AI provider called directly (Claude Haiku 4.5's summary generation stays entirely server-side). `downloadFile()`'s header-less second leg (research.md R1) exists specifically *to protect* this app's own `SUPABASE_ANON_KEY`/bearer token from being forwarded to a host outside the documented contract — reinforcing, not weakening, Principle III's credential-leakage concern. |
| IV. Design Token Discipline & Visual Fidelity | PASS | Every new widget reuses existing `DesignTokens` entries only (data-model.md's widget list, sourced from `prototype-extract.md` §2.5's own five-state description plus the resolved Clarification's sixth) — zero new tokens. UI text ("Preparando exportação...", "Gerando resumo com IA...", "Resumo pronto", "Baixar PDF", "Baixar dados brutos", "Nenhum registro nesse período.", "Fechar") is exactly as the prototype extract and spec.md's own FR wording state it, in Portuguese; the one genuinely new copy this unit must author (FR-007's generic failure text, since the prototype names no sixth state) is written in Portuguese consistent with the other four states' register and tone. |
| V. Clean Architecture Folder Convention | PASS | `export/domain/` imports only `equatable`/`fpdart`/`core/network/failure.dart` — confirmed against `domain_purity_test.dart` (unmodified). `ExportBloc`'s dependency surface is exactly `ExportRepository`/`ExportFileRepository` — no `SessionBloc`, no `RecordsBloc` import. |
| RNF01 (latency) | PASS | See Technical Context's own Performance Goals entry above — every network call in this unit's flow already shows a loading indicator (one of the sheet's own five-or-six states) by construction; "Pendente" itself is the sub-100ms local reflection. |
| RNF02/03/04 (PII, retention, RLS) | N/A to RF05 | Backend-side; this unit sends no new PII-bearing content of its own (the export request carries only a date range, never entry content) and introduces no new on-device retention (Technical Context's own Storage entry: none). |
| RNF05 (hard delete) | N/A to RF05 | Belongs to Settings/RNF05's own unit. |
| RNF06 (layer violations) | PASS | No `export/domain/` file imports Flutter or an `export/data/` class; `ExportBloc` imports neither `SessionBloc` nor `RecordsBloc` — `no_bloc_imports_bloc_test.dart`/`domain_purity_test.dart` both continue to pass unmodified against the new folder. |
| RNF07 (domain coverage ≥80%) | PASS (gate carried into tasks) | `export_job.dart`'s `sheetState` extension is a pure, total function over a 5×5 enum pair, as directly testable as `date_range_filter.dart` (RF06)/`sync_badge_state.dart` (RF07); `ExportRepositoryImpl`'s retry branches are testable against the same `mocktail` fakes `EntriesRepositoryImpl`'s own tests already use the pattern for. |
| RNF08 (visual fidelity) | PASS | The six sheet states match `prototype-extract.md` §2.5 (five named states) plus the resolved Clarification's sixth exactly — no approximated layout or invented component beyond what spec.md/the prototype already name. |
| RNF09 (Either + 15/15 error scenarios) | PASS (gate carried into tasks) | RF05 adds one new write endpoint to the project-wide tally, `export-summary-create` (`POST`) — its 3 required failure scenarios (timeout, malformed response, no-connection) are exercised exactly as rigorously as every prior write endpoint's, per `contracts/export-repository.md`'s own scenario table (items 3–5). `export-status-get`/`export-download-get` are `GET`s, outside RNF09's "5 write endpoints" tally, but are still fully `Either`-typed and covered by `contracts/export-repository.md`/`contracts/http-client-download-extension.md`'s own scenario tables regardless. |

*Post-Phase-1 re-check: see "Post-Design Constitution Check" at the end of this document.*

## Project Structure

### Documentation (this feature)

```text
specs/010-personal-summary-export/
├── plan.md                                    # This file
├── research.md                                # Phase 0 output
├── data-model.md                               # Phase 1 output
├── quickstart.md                               # Phase 1 output
├── contracts/                                  # Phase 1 output
│   ├── http-client-download-extension.md
│   ├── export-repository.md
│   ├── export-bloc.md
│   └── records-header-export-extension.md
└── tasks.md                                     # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
cerne-ciclo-a/
├── pubspec.yaml                                          # + share_plus (research.md R2)
└── lib/
    ├── core/
    │   ├── network/
    │   │   └── api_client.dart                           # + downloadFile() (research.md R1)
    │   └── di/
    │       └── service_locator.dart                      # + Export registrations
    └── features/
        ├── export/
        │   ├── domain/
        │   │   ├── entities/
        │   │   │   └── export_job.dart                   # NEW — ExportJobStatus, NarrativeStatus,
        │   │   │                                          #   ExportSheetState, ExportJob, ExportFormat
        │   │   └── repositories/
        │   │       ├── export_repository.dart             # NEW
        │   │       └── export_file_repository.dart         # NEW
        │   ├── data/
        │   │   ├── export_remote_data_source.dart         # NEW
        │   │   ├── export_repository_impl.dart             # NEW
        │   │   └── export_file_repository_impl.dart        # NEW
        │   └── presentation/
        │       ├── bloc/
        │       │   └── export_event.dart / export_state.dart / export_bloc.dart   # NEW
        │       └── widgets/
        │           ├── export_sheet.dart                   # NEW
        │           ├── export_pending_view.dart            # NEW
        │           ├── export_processing_view.dart         # NEW
        │           ├── export_concluded_view.dart          # NEW
        │           ├── export_narrative_failed_view.dart   # NEW
        │           ├── export_failed_view.dart              # NEW
        │           └── export_empty_period_view.dart        # NEW
        └── records/
            └── presentation/
                └── pages/
                    └── records_page.dart                   # extended — _Header/_RecordsPageState wiring
```

**Structure Decision**: One new feature folder, `export/`, following the exact three-layer convention every
prior unit already established — no deviation. The one `core/network/` addition (`ApiClient.downloadFile()`)
lives there rather than inside `export/` because it is not export-specific in shape (any future signed-URL-
download unit reuses it as-is, same reasoning RF04's `sseStream()` was placed in `core/network/` rather than
inside `chat/`). `records/` is extended rather than having the export sheet folded into it because the sheet
is its own independently-testable concern (its own bloc, its own repository boundary) that only happens to be
*opened from* "Meus Registros" — exactly the same "extend the opening screen in place, give the new concern
its own feature folder" shape RF06's `FilterSheet` already established within `records/` itself (the one
difference being `FilterSheet` has no bloc of its own, needing no separate feature folder, while the export
sheet's async job/polling/download concern is large enough to warrant one, mirroring `chat/`'s own
`AppDrawer`-extension-plus-new-feature-folder precedent).

## Complexity Tracking

| Addition | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A second `ApiClient` transport primitive, `downloadFile()` (research.md R1) | `export-download-get` is this app's first endpoint whose success response is a 302-to-a-signed-URL, not JSON — `call()`'s existing `Dio.request<Map<String, dynamic>>()` cannot parse a redirect target's binary bytes, and naively letting `dio` auto-follow the redirect would forward this app's own auth headers to a third-party Storage host | Letting `dio` auto-follow redirects and reusing `call()` as-is — rejected: leaks `apikey`/bearer-token headers to a host they were never scoped for (research.md R1) |
| A new dependency, `share_plus` | This app has no existing mechanism for "hand the user a file to save or share" — `path_provider` alone only produces a path, never a UI affordance to do anything with it | Writing to a permanent path with no share prompt — rejected, a dead end with no in-app file viewer in scope (research.md R2) |
| A sixth `ExportSheetState`/`ExportState` value (`erroCompleto`/`ExportFailed`), beyond the prototype's five named states | The resolved Clarification explicitly requires a failure state "visually and functionally distinct" from the prototype's one narrative-only "Erro" — collapsing both into one state with a flag would directly contradict that resolution | One shared `erro` state with a boolean "is this the narrative-only case" flag — rejected per the Clarification's own explicit wording (research.md R4) |

*No entry needed beyond these three — each is either this unit's first genuinely new mechanism (the
redirect-download transport, the file-share dependency) or a direct, required encoding of spec.md's own
already-resolved Clarification (the sixth state).*

## Post-Design Constitution Check

Re-evaluated after Phase 1 (data-model.md, contracts/, quickstart.md):

- `export/domain/entities/export_job.dart` and both `export/domain/repositories/*.dart` were re-checked
  against their actual planned imports: `equatable`, `fpdart` (for `Either`/`Unit` signatures), and
  `core/network/failure.dart` only. No `package:flutter`, no `export/data/` class — RNF06/Principle V
  confirmed before any code exists.
- `ExportBloc`'s dependency surface was re-checked: exactly `ExportRepository` + `ExportFileRepository` — no
  `SessionRepository`, no `RecordsBloc` import. Neither `ExportBloc` nor `RecordsBloc` appears in the other's
  planned import list (`no_bloc_imports_bloc_test.dart` covers this mechanically across `features/` folders).
- Re-checked `ApiClient.downloadFile()`'s exception handling against `call()`'s existing `_mapException` —
  reused verbatim for leg 1; leg 2's storage-host failures fall through the same function's existing no-JSON-
  body branch, so no second, divergent failure-mapping implementation was introduced.
- Re-checked that the second `_dio.request` in `downloadFile()` (the storage leg) sends no
  `apikey`/`Authorization` header at all — confirmed in `contracts/http-client-download-extension.md`'s own
  code listing (Principle III's credential-exposure concern, research.md R1).
- Re-checked that `ExportJob.sheetState`, the one domain helper RNF07 specifically needs to be independently
  testable, has zero constructor dependencies and zero I/O — confirmed pure in data-model.md's own listing.
- Re-checked the `records_page.dart` extension (research.md R8) against Principle V: no new `RecordsEvent`/
  `RecordsState`, no new `go_router` route — `AppRoutes.records` itself is unchanged, and `_Header`'s only
  new dependency is a `VoidCallback` its own parent already owns.
- No change surfaces that touches `docs/input/backend/api/openapi.yaml`, `.env`, any native iOS project file
  beyond `share_plus`'s own documented install step, or calls an AI provider directly — Principle III remains
  intact. No export code path reaches a manual-tag/category filter or any RF09-owned endpoint — FR-013 holds
  by construction (confirmed by `export/`'s own planned import list containing nothing from
  `features/entries/` tag handling or `dashboard`-shaped calls).

No new violations. Gate remains PASS.
