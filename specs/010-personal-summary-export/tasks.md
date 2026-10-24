---

description: "Task list for P-RF05 — Personal summary export"
---

# Tasks: P-RF05 — Personal summary export

**Input**: Design documents from `/specs/010-personal-summary-export/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. RNF07 (≥80% domain coverage) and RNF09 (Either + full error-scenario coverage) are
gates this plan explicitly carries into tasks, and every contract in `contracts/` enumerates its own numbered
test-scenario table — these are treated as required deliverables, not optional extras.

**Organization**: `ExportState` is a single Dart `sealed class` with six variants, and the one widget that
renders it (`export_sheet.dart`) must switch over all six exhaustively from the moment it compiles — so the
full domain/data/bloc/widget implementation is **one indivisible unit** (Phase 2, Foundational) rather than
something that can be built one user story at a time. Each user story phase (3–5) instead adds the
**automated tests and manual verification that specifically prove that story's acceptance scenarios**,
independently of the other stories' tests — this is this feature's actual "independently testable" seam,
given its architecture.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3, per spec.md's priorities (US1 and US2 are both P1; US3 is P2)

## Path Conventions

Single Flutter app. `lib/features/export/` (new, 3-layer), `lib/core/network/api_client.dart` (extended),
`lib/core/di/service_locator.dart` (extended), `lib/features/records/presentation/pages/records_page.dart`
(extended). Tests mirror `lib/` under `test/`, matching this repo's existing `entries/`/`chat`/`records`
layout.

---

## Phase 1: Setup

- [X] T001 Add `share_plus: ^13.3.1` to `pubspec.yaml`'s dependencies (research.md R2) and run
  `fvm flutter pub get` — `path_provider: ^2.1.5` is already present, no other dependency change.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The complete `export/` feature (domain → data → bloc → widgets) plus the two cross-cutting
extensions (`ApiClient.downloadFile()`, `records_page.dart`'s icon wiring) that every user story depends on.
No user story's acceptance scenario is observable, through the UI or a bloc test, until this phase is done.

### Domain layer

- [X] T002 [P] Create `ExportJobStatus` (`pending`/`processing`/`dataReady`/`done`/`error`), `NarrativeStatus`
  (`pending`/`processing`/`done`/`failed`/`skipped`) and `ExportSheetState`
  (`pendente`/`processando`/`concluido`/`erroNarrativa`/`erroCompleto`/`periodoVazio`) enums; the `ExportJob`
  `Equatable` entity (`jobId` `String`, `status` `ExportJobStatus`, `narrativeStatus` `NarrativeStatus`,
  `entryCount` `int?`, `errorCode` `String?`, `narrativeErrorCode` `String?`, `downloadAvailable` `bool`); and
  the pure `ExportJobSheetState.sheetState` extension implementing `export-screen-states.md`'s table verbatim
  (`pending`→`pendente`; `processing`→`processando`; `dataReady`→`processando` regardless of
  `narrativeStatus`; `done`+`done`→`concluido`; `done`+(`failed`|`skipped`)→`erroNarrativa`; `error`→
  `erroCompleto`) in `lib/features/export/domain/entities/export_job.dart` (data-model.md, research.md R4).
- [X] T003 [P] Write unit tests covering `ExportJob.sheetState`'s full 6-row mapping as a total, pure
  function (zero constructor dependencies, zero I/O) in
  `test/features/export/domain/entities/export_job_test.dart` (research.md R4, RNF07).
- [X] T004 [P] Create the `ExportFormat` enum (`pdf`, `raw`) and the `ExportRepository` abstract interface —
  `Future<Either<Failure, String>> create({required DateTime? periodStart, required DateTime? periodEnd})`,
  `Future<Either<Failure, ExportJob>> status(String jobId)`,
  `Future<Either<Failure, Uint8List>> download({required String jobId, required ExportFormat format})` — in
  `lib/features/export/domain/repositories/export_repository.dart` (contracts/export-repository.md).
- [X] T005 [P] Create the `ExportFileRepository` abstract interface —
  `Future<Either<Failure, Unit>> share({required Uint8List bytes, required ExportFormat format})` — in
  `lib/features/export/domain/repositories/export_file_repository.dart` (contracts/export-repository.md).

### Core network

- [X] T006 [P] Add `Future<Either<Failure, Uint8List>> downloadFile(String function, {List<String>?
  pathSegments, Map<String, dynamic>? queryParameters, AuthMode authMode = AuthMode.userSession})` to
  `lib/core/network/api_client.dart` (`call()`/`sseStream()` unchanged): leg 1 is a `GET` to `function` with
  `followRedirects: false` and `validateStatus: (status) => status != null && status < 400`, sending the same
  `apikey`/`Authorization` headers `call()` already sends; a non-`302` status or a missing `location` header
  returns `Left(ValidationFailure(message: 'Malformed response: expected a 302 redirect', requestId: ''))`;
  leg 2 is a header-less `GET` of the `location` URL with `responseType: ResponseType.bytes`, returning
  `Right(Uint8List.fromList(...))` on success; both legs' `DioException`s map through the existing
  `_mapException` (contracts/http-client-download-extension.md, research.md R1).
- [X] T007 [P] Write tests for `ApiClient.downloadFile()`'s 7 contract scenarios — 302+bytes success;
  leg-1 `200` (no redirect) → `ValidationFailure`; `302` with no `location` header → `ValidationFailure`;
  leg-1 `DioException` with `{code: 'AUTH_EXPIRED'}` → `AuthExpiredFailure`; leg-2 `connectionTimeout` →
  `NetworkTimeoutFailure`; leg-2 exception with no `response` at all → `NetworkOfflineFailure`; `queryParameters:
  {'format': 'raw'}` reaches leg 1's URL verbatim — in `test/core/network/api_client_download_test.dart`
  (contracts/http-client-download-extension.md).

### Data layer

- [X] T008 Create `ExportRemoteDataSource` in `lib/features/export/data/export_remote_data_source.dart`,
  calling `ApiClient.call('export-summary-create', method: 'POST', body: {periodStart, periodEnd,
  includeNarrative: true})` and parsing `data.jobId`; calling `ApiClient.call('export-status-get', method:
  'GET', pathSegments: [jobId])` and parsing the full `ExportJob` (`status`'s wire value `data_ready` parses
  to `ExportJobStatus.dataReady` via an explicit lookup table, not `.byName`; every other enum value parses via
  `.byName`); delegating `download` to `ApiClient.downloadFile('export-download-get', pathSegments: [jobId],
  queryParameters: {'format': format.name})` unparsed (depends on T002, T004, T006) (data-model.md,
  contracts/export-repository.md).
- [X] T009 [P] Write unit tests for `ExportRemoteDataSource`'s three parse paths, including the `data_ready`
  lookup-table case, in `test/features/export/data/export_remote_data_source_test.dart` (depends on T008).
- [X] T010 Create `ExportRepositoryImpl` in `lib/features/export/data/export_repository_impl.dart`,
  implementing `create`/`status`/`download` via `ExportRemoteDataSource`, each wrapped in the
  `_retryAfterSilentRefresh` shape copied verbatim from `EntriesRepositoryImpl` (exactly one retry via
  `SessionRepository.refresh()` on a first-attempt `AuthExpiredFailure`; a second `AuthExpiredFailure` after
  that retry is returned as-is, no loop); `EXPORT_EMPTY_PERIOD` (400) maps through the existing, shared
  `ErrorMapper.fromResponse` to `Left(ExportEmptyPeriodFailure)` — already defined in
  `lib/core/network/failure.dart` (depends on T004, T008) (contracts/export-repository.md, research.md R7).
- [X] T011 [P] Write tests for `ExportRepositoryImpl`'s 10 contract scenarios — `create()` success /
  `EXPORT_EMPTY_PERIOD` / timeout / malformed body / no-connection; `status()` `data_ready`+`processing` parse /
  malformed body; silent-refresh retry success / retry-also-fails (exactly one retry, no loop); `download()`
  bytes passthrough — in `test/features/export/data/export_repository_impl_test.dart` (depends on T010).
- [X] T012 [P] Create `ExportFileRepositoryImpl.share` in
  `lib/features/export/data/export_file_repository_impl.dart`: writes `bytes` to
  `(await getTemporaryDirectory()).path` as `cerne-resumo.pdf` (`ExportFormat.pdf`) or `cerne-dados.json`
  (`ExportFormat.raw`), then calls `Share.shareXFiles([XFile(file.path)])`; any write/share exception maps to
  `Left(NetworkTimeoutFailure(message: 'Falha ao salvar/compartilhar o arquivo.', requestId: ''))`; a
  user-cancelled share (a non-throwing `ShareResult` from `share_plus`) is treated as `Right(unit)` (depends on
  T005) (contracts/export-repository.md, research.md R2).
- [X] T013 [P] Write tests for `ExportFileRepositoryImpl.share`'s 2 contract scenarios — write+share success
  including a user-cancelled share resolving to `Right(unit)`; a file-write throw resolving to
  `Left(NetworkTimeoutFailure)` — in `test/features/export/data/export_file_repository_impl_test.dart`
  (depends on T012).

### Presentation — bloc

- [X] T014 [P] Create the `ExportEvent` sealed classes — `ExportRequested(DateTime? periodStart, DateTime?
  periodEnd)`, `ExportStatusPollTicked`, `PdfDownloadRequested`, `RawDataDownloadRequested` — in
  `lib/features/export/presentation/bloc/export_event.dart` (data-model.md).
- [X] T015 [P] Create the `ExportState` sealed classes — `ExportPending`, `ExportProcessing`,
  `ExportConcluded({required jobId, isDownloadingPdf = false, isDownloadingRaw = false, pdfDownloadFailure,
  rawDownloadFailure})`, `ExportNarrativeFailed({required jobId, isDownloadingRaw = false,
  rawDownloadFailure})`, `ExportFailed`, `ExportEmptyPeriod` — in
  `lib/features/export/presentation/bloc/export_state.dart` (data-model.md).
- [X] T016 Create `ExportBloc extends Bloc<ExportEvent, ExportState>` (constructor takes `ExportRepository` +
  `ExportFileRepository` only — never `SessionRepository`, never any `RecordsBloc` type) in
  `lib/features/export/presentation/bloc/export_bloc.dart`, implementing contracts/export-bloc.md's full
  event→state sequence: `_onExportRequested` emits `ExportPending()`, calls `exportRepository.create(...)` —
  `ExportEmptyPeriodFailure` → emit `ExportEmptyPeriod()` (terminal); `AuthExpiredFailure` → fire
  `reauthRequired`, emit `ExportFailed()` (terminal); any other `Failure` → emit `ExportFailed()` (terminal);
  success → store `_jobId`, `add(const ExportStatusPollTicked())`. `_onStatusPollTicked` calls
  `exportRepository.status(_jobId!)` — on failure, fire `reauthRequired` if `AuthExpiredFailure`, leave state
  unchanged, re-arm `Timer(const Duration(seconds: 2), () => add(const ExportStatusPollTicked()))`; on success,
  map `job.sheetState` to `ExportPending`/`ExportProcessing` (re-arm timer, not terminal) or
  `ExportConcluded(jobId)`/`ExportNarrativeFailed(jobId)`/`ExportFailed()` (terminal, do not re-arm).
  `_onPdfDownloadRequested`/`_onRawDataDownloadRequested` no-op if the matching `isDownloadingX` is already
  `true` or the current state doesn't offer that button; otherwise set `isDownloadingX: true`, call
  `download()` then `share()`, clearing or setting the matching `...DownloadFailure` on completion (firing
  `reauthRequired` on an `AuthExpiredFailure`) — never regressing to `ExportFailed`. Exposes a one-shot
  `Stream<void> get reauthRequired` (`StreamController<void>.broadcast()`); `close()` cancels `_pollTimer` and
  closes the controller (depends on T004, T005, T010, T012, T014, T015) (contracts/export-bloc.md, research.md
  R3/R5/R6/R7).

### DI wiring

- [X] T017 In `lib/core/di/service_locator.dart`, register `ExportRemoteDataSource` and
  `ExportFileRepositoryImpl` (`registerLazySingleton`, same category as `EntriesRemoteDataSource`),
  `ExportRepository`/`ExportFileRepository` (`registerLazySingleton`, the former depending on
  `getIt<SessionRepository>()`), and `ExportBloc` (`registerFactory` — a fresh instance per
  `getIt<ExportBloc>()` call, never `registerLazySingleton`, mirroring `InsertionModalBloc`/`VaultBloc`)
  (depends on T006, T008, T010, T012, T016) (research.md R6).

### Presentation — widgets

- [X] T018 [P] Create `export_pending_view.dart`: spinner (`CircularProgressIndicator`,
  `DesignTokens.colorAccent`), "Preparando exportação...", a "Fechar" `TextButton` (`context.pop()`) in
  `lib/features/export/presentation/widgets/export_pending_view.dart` (FR-004, FR-010).
- [X] T019 [P] Create `export_processing_view.dart`: "Gerando resumo com IA...", an indeterminate
  `LinearProgressIndicator` (`DesignTokens.colorAccent`), a "Fechar" `TextButton` in
  `lib/features/export/presentation/widgets/export_processing_view.dart` (FR-004, FR-010).
- [X] T020 [P] Create `export_concluded_view.dart`: `Icons.check_circle` (`DesignTokens.colorSuccess`),
  "Resumo pronto", a primary `ElevatedButton` "Baixar PDF" dispatching `PdfDownloadRequested`, an outline
  `OutlinedButton` "Baixar dados brutos" dispatching `RawDataDownloadRequested` — each disabled while its own
  `isDownloadingX` is `true`, each showing a small shared inline retry affordance (message + "Tentar
  novamente", mirroring `records_page.dart`'s own private `_RetryBanner` shape but defined locally to this
  widget since that class is private to its own file) when its own `...DownloadFailure` is set, plus a
  "Fechar" `TextButton` in `lib/features/export/presentation/widgets/export_concluded_view.dart` (FR-005,
  FR-008, FR-009, FR-010, FR-011, data-model.md).
- [X] T021 [P] Create `export_narrative_failed_view.dart`: `Icons.warning_amber` (`DesignTokens.colorError`),
  copy explaining the AI summary failed but the data remains available, exactly one `OutlinedButton` "Baixar
  dados brutos" dispatching `RawDataDownloadRequested` (same disabled/retry shape as T020's raw button), a
  "Fechar" `TextButton` — no "Baixar PDF" control at all — in
  `lib/features/export/presentation/widgets/export_narrative_failed_view.dart` (FR-006, FR-009, FR-010).
- [X] T022 [P] Create `export_failed_view.dart`: `Icons.error_outline` (`DesignTokens.colorError`), a
  generic "não foi possível gerar a exportação" copy that is textually distinct from T021's narrative-only
  copy and shown the same way regardless of `errorCode`, no download control of any kind, only a "Fechar"
  `TextButton` in `lib/features/export/presentation/widgets/export_failed_view.dart` (FR-007, resolved
  Clarification, Complexity Tracking).
- [X] T023 [P] Create `export_empty_period_view.dart`: "Nenhum registro nesse período." plus a suggestion to
  adjust the filter, no download control, a "Fechar" `TextButton` in
  `lib/features/export/presentation/widgets/export_empty_period_view.dart` (FR-003).
- [X] T024 Create `export_sheet.dart` — the `StatefulWidget` `showModalBottomSheet` builds, taking
  `periodStart`/`periodEnd`: `initState` provides `BlocProvider<ExportBloc>(create: (_) =>
  getIt<ExportBloc>()..add(ExportRequested(periodStart, periodEnd)))` and subscribes to its `reauthRequired`
  stream (dispatching `context.read<SessionBloc>().add(const AuthExpiredDetected())` on each event, mirroring
  `RecordsPage`'s own subscribe/dispose shape), unsubscribing in `dispose()`; `build` switches exhaustively on
  `ExportState` to render one of T018–T023's six views in
  `lib/features/export/presentation/widgets/export_sheet.dart` (depends on T014, T015, T016, T017, T018, T019,
  T020, T021, T022, T023) (data-model.md, research.md R7, contracts/export-bloc.md).

### Records page wiring

- [X] T025 In `lib/features/records/presentation/pages/records_page.dart`, extend `_Header` with a
  `required VoidCallback onExportPressed` constructor field and wire the download `IconButton`'s `onPressed`
  to it, removing the inert `() {}` placeholder and its "no export behavior in this unit" comment; extend
  `_RecordsPageState` with `bool _isOpeningExportSheet = false` and `Future<void> _openExportSheet(BuildContext
  context)` — returns immediately if `_isOpeningExportSheet` is already `true` (FR-011); otherwise reads
  `context.read<RecordsBloc>().state`'s `dateRange` (falling back to `DateRangeOption.allTime` if the state
  isn't `RecordsLoaded`), converts it via the existing `DateRangeBounds.boundsAt(DateTime.now())` extension,
  and `await`s `showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) =>
  ExportSheet(periodStart: bounds.from, periodEnd: bounds.to))`, resetting the guard to `false` only if still
  `mounted`; wire `_Header(onExportPressed: () => _openExportSheet(context))` in `build()` (depends on T024)
  (research.md R8, contracts/records-header-export-extension.md).
- [X] T026 [P] Write tests for the records-header contract's 5 scenarios — `thisWeek` period bounds passed to
  `ExportSheet` with `periodEnd: null`; `allTime` passes `periodStart: null, periodEnd: null`; a rapid
  double-tap calls `showModalBottomSheet` exactly once; dismissing then tapping again calls it a second time;
  `RecordsBloc`'s own state (`entries`/`dateRange`/scroll position) is bit-for-bit unchanged before and after —
  in `test/features/records/presentation/pages/records_page_test.dart` (depends on T025).

**Checkpoint**: The full export feature compiles, is wired into "Meus Registros", and passes its own
foundational tests. Every user story's acceptance scenario can now be exercised — through `bloc_test`,
`testWidgets`, and manually on a Simulator — independently of the others.

---

## Phase 3: User Story 1 - Getting a narrative PDF of your entries (Priority: P1) 🎯 MVP

**Goal**: A user with at least one entry in the exported period reaches a downloaded, readable narrative PDF,
end-to-end, through "Pendente" → "Processando" → "Concluído".

**Independent Test**: Run the bloc/widget tests below without any of Phase 4/5's tests existing, then open the
export sheet on a Simulator for a period with entries and let it run to completion.

### Tests for User Story 1

- [X] T027 [US1] Add a `bloc_test` for `ExportRequested` where `create()` succeeds: states emitted, in order,
  are `ExportPending()` then (after the first poll tick) whatever `status()`'s first response maps to
  (contract scenario 1) in `test/features/export/presentation/bloc/export_bloc_test.dart`.
- [X] T028 [US1] Add a `bloc_test` for the poll sequence `pending` → `processing` → `done`/`done`: states are
  exactly `ExportPending()`, `ExportProcessing()`, `ExportConcluded(jobId)` — the `_pollTimer` is armed twice
  and never a third time (contract scenario 5, SC-005) — same file as T027.
- [X] T029 [US1] Add a `bloc_test` for `PdfDownloadRequested` dispatched twice in a row before the first
  resolves: `ExportRepository.download` is called exactly once (contract scenario 9, FR-011) — same file.
- [X] T030 [US1] Add a `bloc_test` for `PdfDownloadRequested` where `download()` succeeds but `share()` fails:
  final state is `ExportConcluded(isDownloadingPdf: false, pdfDownloadFailure: <failure>)` with `jobId`
  unchanged and `rawDownloadFailure` untouched (contract scenario 10, Edge Cases retry) — same file.
- [X] T031 [P] [US1] Write a `testWidgets` test for `export_concluded_view.dart` confirming: green check +
  "Resumo pronto" render; "Baixar PDF" (primary) and "Baixar dados brutos" (outline) are both enabled by
  default; each disables while its own `isDownloadingX` flag is `true`; the inline retry affordance appears
  only when its own `...DownloadFailure` is set (FR-005) in
  `test/features/export/presentation/widgets/export_concluded_view_test.dart`.

### Manual verification for User Story 1

- [ ] T032 [US1] Execute quickstart.md's "Story 1" steps 1–6 on a Simulator/device (tap icon → Pendente →
  Processando → Concluído with two buttons → PDF download via OS share sheet produces a readable narrative
  PDF → raw-data download independent of the PDF one → Fechar leaves "Meus Registros" unchanged), per
  `specs/010-personal-summary-export/quickstart.md` (SC-001).

**Checkpoint**: User Story 1 is fully functional and testable independently of US2/US3.

---

## Phase 4: User Story 2 - Your raw data is never held hostage by the AI narrative (Priority: P1)

**Goal**: A narrative-only AI failure still lets the user download their raw data; a full job failure is shown
as a visually and textually distinct state with no download option at all.

**Independent Test**: Run the bloc/widget tests below (none of which touch US1's or US3's own test files)
against the already-foundational bloc/widgets, then force a narrative failure and a full job failure on a
Simulator.

### Tests for User Story 2

- [X] T033 [US2] Add a `bloc_test` for the poll sequence `processing` → `done`/`failed`: states end on
  `ExportNarrativeFailed(jobId)` (contract scenario 6, FR-006) in
  `test/features/export/presentation/bloc/export_bloc_test.dart`.
- [X] T034 [US2] Add a `bloc_test` for the poll sequence `processing` → `error`: states end on
  `ExportFailed()` (contract scenario 7, FR-007) — same file as T033.
- [X] T035 [US2] Add a `bloc_test` for `ExportRequested` where `create()` returns `NetworkOfflineFailure`:
  states are `ExportPending()`, `ExportFailed()`, with no poll ever dispatched (contract scenario 3, research.md
  R5) — same file.
- [X] T036 [US2] Add a `bloc_test` for `ExportRequested` where `create()` returns `AuthExpiredFailure` after
  its silent-refresh retry also fails: states are `ExportPending()`, `ExportFailed()`, and `reauthRequired`
  emits exactly once (contract scenario 4) — same file.
- [X] T037 [US2] Add a `bloc_test` for `RawDataDownloadRequested` dispatched from `ExportNarrativeFailed` that
  succeeds: final state is `ExportNarrativeFailed(isDownloadingRaw: false, rawDownloadFailure: null)` — it
  never transitions to `ExportConcluded` (contract scenario 11, FR-009) — same file.
- [X] T038 [US2] Add a `bloc_test` for one poll tick failing with `NetworkTimeoutFailure` followed by a
  successful tick reaching `done`/`done`: the failed tick produces **no** state emission at all — the sheet
  never flashes `ExportFailed()` for a transient poll failure (contract scenario 8) — same file.
- [X] T039 [P] [US2] Write a `testWidgets` test for `export_narrative_failed_view.dart` confirming the red
  warning icon, the narrative-failed copy, exactly one enabled "Baixar dados brutos" button, no "Baixar PDF"
  control, that the button disables while `isDownloadingRaw` is `true`, and that the inline retry affordance
  appears when `rawDownloadFailure` is set (FR-006, FR-011) in
  `test/features/export/presentation/widgets/export_narrative_failed_view_test.dart`.
- [X] T040 [P] [US2] Write a `testWidgets` test for `export_failed_view.dart` confirming its copy is
  textually distinct from `export_narrative_failed_view.dart`'s (T039), that no download button renders, and
  that only "Fechar" is present (FR-007, resolved Clarification) in
  `test/features/export/presentation/widgets/export_failed_view_test.dart`.
- [X] T049 [US2] Add a `bloc_test` for `RawDataDownloadRequested` dispatched twice in a row before the first
  resolves, from `ExportNarrativeFailed`: `ExportRepository.download` is called exactly once (contract scenario
  12, FR-011) in `test/features/export/presentation/bloc/export_bloc_test.dart`.
- [X] T050 [US2] Add a `bloc_test` for `RawDataDownloadRequested` dispatched from `ExportNarrativeFailed` where
  `download()` succeeds but `share()` fails: final state is `ExportNarrativeFailed(isDownloadingRaw: false,
  rawDownloadFailure: <failure>)` with `jobId` unchanged (contract scenario 13, Edge Cases retry) — same file
  as T049.

### Manual verification for User Story 2

- [ ] T041 [US2] Execute quickstart.md's "Story 2" steps 1–4 on a Simulator/device: force a narrative-only
  failure and confirm the raw-data download still succeeds; separately force a full job failure and screenshot
  both failure states side by side to confirm they are visually and textually distinct; confirm closing and
  retapping the download icon starts a brand-new attempt, per
  `specs/010-personal-summary-export/quickstart.md` (SC-002).

**Checkpoint**: User Stories 1 and 2 both work independently.

---

## Phase 5: User Story 3 - Exporting a period with nothing in it is handled gracefully (Priority: P2)

**Goal**: Requesting an export for a zero-entry period shows "Período vazio" immediately — never "Pendente" or
"Processando" first — with no file ever produced.

**Independent Test**: Run the bloc/widget tests below in isolation, then request an export for a known-empty
period on a Simulator.

### Tests for User Story 3

- [X] T042 [US3] Add a `bloc_test` for `ExportRequested` where `create()` returns `ExportEmptyPeriodFailure`:
  states are `ExportPending()`, `ExportEmptyPeriod()`, with no poll ever dispatched (contract scenario 2,
  FR-003) in `test/features/export/presentation/bloc/export_bloc_test.dart`.
- [X] T043 [P] [US3] Write a `testWidgets` test for `export_empty_period_view.dart` confirming the
  "Nenhum registro nesse período." copy, the filter-adjustment suggestion, and that no download button renders
  (FR-003) in `test/features/export/presentation/widgets/export_empty_period_view_test.dart`.

### Manual verification for User Story 3

- [ ] T044 [US3] Execute quickstart.md's "Story 3" steps 1–3 on a Simulator/device: select a known-zero-entry
  period, confirm "Período vazio" appears immediately with no spinner/progress bar ever shown first, confirm
  no download button appears, and confirm "Fechar" leaves "Meus Registros" unaffected, per
  `specs/010-personal-summary-export/quickstart.md` (SC-003).

**Checkpoint**: All three user stories are independently functional and tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T045 Run `fvm flutter analyze` and resolve any RNF06 import-shape violations surfaced by the new
  `lib/features/export/**` files or the extended `records_page.dart`/`api_client.dart`/`service_locator.dart`.
- [X] T046 Run `dart test/architecture/no_bloc_imports_bloc_test.dart` and
  `dart test/architecture/domain_purity_test.dart`, confirming both pass unmodified against
  `lib/features/export/**` — no `export/domain/` file imports `package:flutter` or an `export/data/` class, and
  neither `ExportBloc` nor `RecordsBloc` appears in the other's import list (RNF06, Principle V).
- [X] T047 Run `fvm flutter test --coverage`, then `lcov --extract coverage/lcov.info 'lib/**/domain/**' -o
  coverage/domain.info` and `genhtml coverage/domain.info -o coverage/domain-html`, confirming ≥80% coverage
  including `export_job.dart`'s `sheetState` mapping and `ExportRepositoryImpl`'s/`ExportFileRepositoryImpl`'s
  retry/share branches (RNF07).
- [ ] T048 Execute quickstart.md's remaining "Edge cases worth exercising manually" checklist on a
  Simulator/device — close-then-reopen during Pendente/Processando; rapid double-tap on the download icon;
  double-tap on a download button mid-request; forced session expiry mid-poll; a post-completion download
  failure returning to a retryable state — per `specs/010-personal-summary-export/quickstart.md` (FR-010,
  FR-011, FR-012, Edge Cases).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup. BLOCKS every user story phase — unlike most features, this
  phase contains the entire feature's implementation (T002–T026), because `ExportState`'s sealed-class switch
  in `export_sheet.dart` must be exhaustive from first compile.
- **User Stories (Phases 3–5)**: All depend on Foundational completion. Each phase's tests are independent of
  the others' and can be written/run in any order or in parallel by different people.
- **Polish (Phase 6)**: Depends on all three user story phases.

### Within Phase 2 (Foundational)

T002 → T003 · T004/T005/T006 independent of T002 · T006 → T007 · (T002,T004,T006) → T008 → T009 ·
(T004,T008) → T010 → T011 · T005 → T012 → T013 · T014/T015 independent · (T004,T005,T010,T012,T014,T015) →
T016 · (T006,T008,T010,T012,T016) → T017 · T018–T023 independent of each other · (T014,T015,T016,T017,
T018–T023) → T024 → T025 → T026.

### Within Each User Story Phase

Bloc test tasks within a phase (T027–T030, T033–T038, T042, T049–T050) share one file
(`export_bloc_test.dart`) and are added sequentially, not in parallel, to avoid conflicting edits. Widget test
tasks (T031, T039, T040, T043) are each their own file and have no dependency on the bloc test tasks.

### Parallel Opportunities

- All of T018–T023 (the six state-view widgets) can be built in parallel — six independent files, no
  cross-dependency.
- T002/T004/T005/T006/T014/T015 (entity, two domain interfaces, `ApiClient` extension, event/state classes)
  have no dependency on each other and can start together once Setup is done.
- Within each user story phase, the widget test task(s) can run in parallel with that phase's bloc test
  tasks, since they touch different files.
- The three manual-verification tasks (T032, T041, T044) can be performed by different people once Phase 2's
  checkpoint is reached.

---

## Parallel Example: Phase 2 widget layer

```bash
Task: "Create export_pending_view.dart"
Task: "Create export_processing_view.dart"
Task: "Create export_concluded_view.dart"
Task: "Create export_narrative_failed_view.dart"
Task: "Create export_failed_view.dart"
Task: "Create export_empty_period_view.dart"
# All six (T018–T023) are independent files — only export_sheet.dart (T024) needs all six done first.
```

---

## Implementation Strategy

### MVP scope

Because spec.md assigns **P1 to both User Story 1 and User Story 2** (US2 is called out explicitly as its own
acceptance criterion, not a nice-to-have), the smallest responsible MVP is **Phase 1 + Phase 2 + Phase 3 (US1)
+ Phase 4 (US2)** — a narrative-failure falling back to raw data is as core to RF05's trust story as the PDF
path itself. User Story 3 (empty-period handling, P2) is the first increment after that.

### Incremental delivery

1. Setup + Foundational (Phases 1–2) → the full feature compiles, is wired into "Meus Registros", passes its
   own tests.
2. Add US1's tests + manual pass (Phase 3) → confident in the narrative-PDF happy path. **MVP checkpoint 1.**
3. Add US2's tests + manual pass (Phase 4) → confident the AI narrative can never block the user's own data.
   **Full MVP.**
4. Add US3's tests + manual pass (Phase 5) → confident the empty-period edge case never shows a spinner.
5. Polish (Phase 6) → `flutter analyze`, architecture tests, RNF07 coverage gate, remaining edge cases.

### Parallel team strategy

With multiple people: one completes Setup + Foundational alone (it's one tightly-coupled unit, hard to split
usefully). Once Phase 2's checkpoint is reached, up to three people can each own one user story phase's
tests + manual verification in parallel — none of Phases 3–5 touch each other's test files except the shared
`export_bloc_test.dart` (coordinate on that one file, or have one person own all bloc-test additions).
