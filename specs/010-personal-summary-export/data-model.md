# Data Model: P-RF05 — Personal summary export

Source: spec.md §Key Entities/§Requirements; requirements.md §§1 (RF05), 6.5, 8, 13;
`docs/input/backend/api/openapi.yaml`'s `/export/*` schemas; `docs/input/backend/export-screen-states.md`;
`docs/input/backend/error-taxonomy.md`; `docs/input/prototype/prototype-extract.md` §2.5; `research.md`. This
unit adds one new feature folder, `lib/features/export/`, and two small, reused-as-is extensions to existing
`core/` and `records/` code (R1, R8) — it introduces no change to any existing domain entity.

## `ExportJobStatus` / `NarrativeStatus` / `ExportJob` (`lib/features/export/domain/entities/export_job.dart`) — NEW

```dart
enum ExportJobStatus { pending, processing, dataReady, done, error }
enum NarrativeStatus { pending, processing, done, failed, skipped }
enum ExportSheetState { pendente, processando, concluido, erroNarrativa, erroCompleto, periodoVazio }

class ExportJob extends Equatable {
  const ExportJob({
    required this.jobId,
    required this.status,
    required this.narrativeStatus,
    required this.entryCount,
    required this.errorCode,
    required this.narrativeErrorCode,
    required this.downloadAvailable,
  });

  final String jobId;
  final ExportJobStatus status;
  final NarrativeStatus narrativeStatus;
  final int? entryCount;
  final String? errorCode;
  final String? narrativeErrorCode;
  final bool downloadAvailable;

  @override
  List<Object?> get props =>
      [jobId, status, narrativeStatus, entryCount, errorCode, narrativeErrorCode, downloadAvailable];
}

extension ExportJobSheetState on ExportJob {
  /// Pure, total mapping of `export-screen-states.md`'s own table (research.md R4) — the one place this
  /// mapping's correctness is asserted (RNF07). `periodoVazio` and the job-independent branch of
  /// `erroCompleto` are never produced here — see `ExportState` below.
  ExportSheetState get sheetState => switch ((status, narrativeStatus)) {
    (ExportJobStatus.pending, _) => ExportSheetState.pendente,
    (ExportJobStatus.processing, _) => ExportSheetState.processando,
    (ExportJobStatus.dataReady, _) => ExportSheetState.processando,
    (ExportJobStatus.done, NarrativeStatus.done) => ExportSheetState.concluido,
    (ExportJobStatus.done, _) => ExportSheetState.erroNarrativa,
    (ExportJobStatus.error, _) => ExportSheetState.erroCompleto,
  };
}
```

- `status`/`narrativeStatus` parse 1:1 from `GET /export/{jobId}/status`'s own enum values (`pending`/
  `processing`/`data_ready`/`done`/`error`; `pending`/`processing`/`done`/`failed`/`skipped`) — `dataReady` is
  the Dart-cased form of the wire value `data_ready`.
- `downloadAvailable`/`entryCount`/`errorCode`/`narrativeErrorCode` are carried straight through for
  completeness (e.g. future logging) but `sheetState` alone drives every rendering decision this unit needs —
  FR-007 is explicit that `errorCode` is never shown or branched on ("shown the same way regardless of the
  backend's specific error code").

## `ExportRepository` (`lib/features/export/domain/repositories/export_repository.dart`) — NEW

```dart
abstract class ExportRepository {
  Future<Either<Failure, String>> create({
    required DateTime? periodStart,
    required DateTime? periodEnd,
  }); // returns the new jobId

  Future<Either<Failure, ExportJob>> status(String jobId);

  Future<Either<Failure, Uint8List>> download({required String jobId, required ExportFormat format});
}

enum ExportFormat { pdf, raw }
```

- **`create`** → `POST /export/summary` (`export-summary-create`), body `{periodStart, periodEnd,
  includeNarrative: true}` — `periodStart`/`periodEnd` are sent as explicit JSON `null` (not omitted) when the
  period is "all time," since both are in the OpenAPI schema's `required` list despite being `nullable: true`
  (contracts/export-repository.md's exact request shape). `includeNarrative: true` is sent explicitly even
  though it is already the schema's own default, so this unit's one request shape self-documents FR-002's
  "including the narrative by default" rather than relying silently on a default it never asserts.
  `EXPORT_EMPTY_PERIOD` (400) surfaces as `ExportEmptyPeriodFailure` — already defined in `core/network/
  failure.dart` (added as part of this app's shared, closed 13-code taxonomy before this unit existed).
- **`status`** → `GET /export/{jobId}/status` (`export-status-get`), `pathSegments: [jobId]`.
- **`download`** → `ApiClient.downloadFile` (R1), `pathSegments: [jobId]`, `queryParameters: {'format':
  format.name}`.
- All three retry exactly once through `SessionRepository.refresh()` on `AuthExpiredFailure` before giving up
  (research.md R7) — see `contracts/export-repository.md` for the exact sequence, identical in shape to
  `EntriesRepositoryImpl`'s.

### `ExportRemoteDataSource` (`lib/features/export/data/export_remote_data_source.dart`) — NEW

Calls `ApiClient.call`/`ApiClient.downloadFile` and parses `ExportJob` from the status response's `data`
object; `create` parses `data.jobId`; `download` passes bytes through unparsed.

### `ExportRepositoryImpl` (`lib/features/export/data/export_repository_impl.dart`) — NEW

Depends on `ExportRemoteDataSource` + `SessionRepository` (the cross-feature domain interface, same shape
`EntriesRepositoryImpl` already depends on it) — no local cache (Key Entities: "ephemeral... never shown
anywhere outside the export sheet"; unlike `EntriesRepositoryImpl`/`ChatRepositoryImpl`, there is nothing here
worth persisting across a process restart).

## `ExportFileRepository` (`lib/features/export/domain/repositories/export_file_repository.dart`) — NEW

```dart
abstract class ExportFileRepository {
  Future<Either<Failure, Unit>> share({required Uint8List bytes, required ExportFormat format});
}
```

### `ExportFileRepositoryImpl` (`lib/features/export/data/export_file_repository_impl.dart`) — NEW

Writes `bytes` to a temp file (`path_provider`'s `getTemporaryDirectory()`), named
`cerne-resumo.<ext>`/`cerne-dados.<ext>` (`.pdf` for `ExportFormat.pdf`; `.json` for `ExportFormat.raw`,
research.md R2), then calls `Share.shareXFiles([XFile(path)])` (`share_plus`). Any `PlatformException`/I/O
failure (disk full, share sheet dismissed with an error — not a plain user cancel, which `share_plus` reports
as a normal, non-throwing result) maps to a retryable failure the same way R1's storage leg does — never a
new, undocumented `Failure` subtype.

## `ApiClient` — extended (`lib/core/network/api_client.dart`)

```dart
Future<Either<Failure, Uint8List>> downloadFile(
  String function, {
  List<String>? pathSegments,
  Map<String, dynamic>? queryParameters,
  AuthMode authMode = AuthMode.userSession,
})
```

`call()`/`sseStream()` are unchanged. See `contracts/http-client-download-extension.md` for the exact
two-step, no-header-leak sequence (research.md R1).

## `ExportEvent` (`lib/features/export/presentation/bloc/export_event.dart`) — NEW

| Event | When |
|---|---|
| `ExportRequested(periodStart, periodEnd)` | `ExportSheet.initState` — the one and only time a job is requested for that sheet instance. |
| `ExportStatusPollTicked` | Dispatched once immediately after a successful `ExportRequested`, then re-armed by a `Timer` after each non-terminal poll response (research.md R3) — never dispatched directly by any widget. |
| `PdfDownloadRequested` | "Baixar PDF" tapped (`ExportConcluded` only). |
| `RawDataDownloadRequested` | "Baixar dados brutos" tapped (`ExportConcluded` or `ExportNarrativeFailed`). |

## `ExportState` (`lib/features/export/presentation/bloc/export_state.dart`) — NEW

```dart
sealed class ExportState extends Equatable {
  const ExportState();
  @override
  List<Object?> get props => [];
}

class ExportPending extends ExportState {
  const ExportPending();
}

class ExportProcessing extends ExportState {
  const ExportProcessing();
}

class ExportConcluded extends ExportState {
  const ExportConcluded({
    required this.jobId,
    this.isDownloadingPdf = false,
    this.isDownloadingRaw = false,
    this.pdfDownloadFailure,
    this.rawDownloadFailure,
  });

  final String jobId;
  final bool isDownloadingPdf;
  final bool isDownloadingRaw;
  final Failure? pdfDownloadFailure;   // a completed-but-retryable download attempt failed; buttons stay enabled
  final Failure? rawDownloadFailure;

  @override
  List<Object?> get props =>
      [jobId, isDownloadingPdf, isDownloadingRaw, pdfDownloadFailure, rawDownloadFailure];
}

class ExportNarrativeFailed extends ExportState {
  const ExportNarrativeFailed({
    required this.jobId,
    this.isDownloadingRaw = false,
    this.rawDownloadFailure,
  });

  final String jobId;
  final bool isDownloadingRaw;
  final Failure? rawDownloadFailure;

  @override
  List<Object?> get props => [jobId, isDownloadingRaw, rawDownloadFailure];
}

/// FR-007 — the Clarification-resolved sixth state. Reached either from a polled `ExportJob.sheetState ==
/// erroCompleto` (research.md R4) or directly from any non-empty-period `POST` failure (research.md R5) —
/// in the latter case no `jobId` ever existed, so this state carries none.
class ExportFailed extends ExportState {
  const ExportFailed();
}

class ExportEmptyPeriod extends ExportState {
  const ExportEmptyPeriod();
}
```

- `pdfDownloadFailure`/`rawDownloadFailure` are retryable-in-place fields on the two states that can show a
  download button — the same "the entries/data already shown stay intact, only this one thing is retryable"
  shape `RecordsLoaded.pageLoadFailure` already established — never a reason to leave `ExportConcluded`/
  `ExportNarrativeFailed` entirely (Edge Cases: "the corresponding button returns to a retryable state rather
  than leaving the sheet stuck").
- There is deliberately no `ExportState` field or variant for `entryCount`/`errorCode` — FR-007's own wording
  and `sheetState`'s design (above) mean nothing in this unit's UI ever needs to branch on them.

## `ExportBloc` (`lib/features/export/presentation/bloc/export_bloc.dart`) — NEW

```dart
class ExportBloc extends Bloc<ExportEvent, ExportState> {
  ExportBloc({
    required ExportRepository exportRepository,
    required ExportFileRepository exportFileRepository,
  }) : super(const ExportPending());

  Stream<void> get reauthRequired;   // one-shot (research.md R7) — identical shape to RecordsBloc's
}
```

Depends only on `ExportRepository`/`ExportFileRepository` — never `SessionRepository` directly (research.md
R7), never `RecordsBloc` (no cross-bloc import; `RecordsPage`/`_RecordsPageState` is the one mediating widget
that reads `RecordsBloc.state.dateRange` *before* constructing `ExportSheet`, research.md R8 — `ExportBloc`
itself never touches `RecordsBloc`). Internal fields: `String? _jobId`, `Timer? _pollTimer`, cancelled in
`close()` alongside closing `_reauthController` (identical shape to `RecordsBloc._debounceTimer`/
`_reauthController`).

- **`_onExportRequested`**: emits `ExportPending()`; calls `exportRepository.create(...)`. On
  `ExportEmptyPeriodFailure` → emit `ExportEmptyPeriod()`, stop. On any other `Failure` → if
  `AuthExpiredFailure`, fire `reauthRequired`; emit `ExportFailed()` either way (research.md R5), stop. On
  success (`jobId`) → store `_jobId`, dispatch `add(const ExportStatusPollTicked())`.
- **`_onStatusPollTicked`**: calls `exportRepository.status(_jobId!)`. On failure: if `AuthExpiredFailure`,
  fire `reauthRequired`; either way, leave the current `ExportState` unchanged and re-arm the `Timer` for
  another attempt (research.md R7's "no bespoke resume code needed" — a future successful tick simply
  supersedes this one). On success: map `job.sheetState` → `ExportPending`/`ExportProcessing` (not yet
  terminal — re-arm the `Timer`) or `ExportConcluded(jobId)`/`ExportNarrativeFailed(jobId)`/`ExportFailed()`
  (terminal — do not re-arm).
- **`_onPdfDownloadRequested`/`_onRawDataDownloadRequested`**: no-op if the matching `isDownloadingX` is
  already `true` (FR-011's per-button in-flight guard) or the current state isn't one that offers that button.
  Otherwise set `isDownloadingX: true`, call `exportRepository.download(jobId, format)`, then
  `exportFileRepository.share(bytes, format)`; on success, clear the matching `...DownloadFailure` and
  `isDownloadingX`; on failure, set `isDownloadingX: false` and the matching `...DownloadFailure` (and fire
  `reauthRequired` if it was `AuthExpiredFailure`) — the sheet stays on `ExportConcluded`/
  `ExportNarrativeFailed` throughout; a download failure never regresses the sheet to `ExportFailed`.

## `_Header` / `_RecordsPageState` — extended (`lib/features/records/presentation/pages/records_page.dart`)

```dart
class _Header extends StatelessWidget {
  const _Header({required this.onExportPressed});
  final VoidCallback onExportPressed;
  // IconButton(onPressed: onExportPressed, icon: Icons.download_outlined, ...) replaces today's
  // `onPressed: () {}` inert placeholder (FR-008's own comment there is superseded by this unit).
}
```

`_RecordsPageState` gains `bool _isOpeningExportSheet = false;` and:

```dart
Future<void> _openExportSheet(BuildContext context) async {
  if (_isOpeningExportSheet) return;              // FR-011 — guards a fast double-tap on the icon itself
  _isOpeningExportSheet = true;
  final state = context.read<RecordsBloc>().state;
  final dateRange = state is RecordsLoaded ? state.dateRange : DateRangeOption.allTime;
  final bounds = dateRange.boundsAt(DateTime.now());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ExportSheet(periodStart: bounds.from, periodEnd: bounds.to),
  );
  _isOpeningExportSheet = false;
}
```

No new `RecordsEvent`/`RecordsState` field — `RecordsBloc` is untouched (research.md R8).

## Widgets (`lib/features/export/presentation/widgets/`) — NEW

Not separately contracted (pure prototype-fidelity rendering, no new state/logic beyond `ExportState` above):

- `export_sheet.dart` — the `StatefulWidget` `showModalBottomSheet` builds. `initState` provides `ExportBloc`
  (`getIt<ExportBloc>()..add(ExportRequested(periodStart, periodEnd))`) and subscribes to its
  `reauthRequired` (research.md R7, same subscribe/dispose shape as `RecordsPage`'s own). `build` switches on
  `ExportState` to pick one of the six state views below, each ending in the same "Fechar" `TextButton`
  (`context.pop()` — FR-010, present and functional in all six).
- `export_pending_view.dart` — spinner (`CircularProgressIndicator`, `DesignTokens.colorAccent`),
  "Preparando exportação...".
- `export_processing_view.dart` — "Gerando resumo com IA...", `LinearProgressIndicator` (indeterminate —
  the backend never reports a percentage; `DesignTokens.colorAccent`).
- `export_concluded_view.dart` — `Icons.check_circle` (`DesignTokens.colorSuccess`), "Resumo pronto", "Baixar
  PDF" (`ElevatedButton`, primary) + "Baixar dados brutos" (`OutlinedButton`) — each disabled while its own
  `isDownloadingX` is true and showing an inline retry affordance when its own `...DownloadFailure` is set
  (same `_RetryBanner`-style inline pattern `records_page.dart` already established, reused via a small shared
  widget rather than copy-pasted).
- `export_narrative_failed_view.dart` — `Icons.warning_amber` (`DesignTokens.colorError`), copy explaining the
  narrative failed but data remains available, exactly one `OutlinedButton` ("Baixar dados brutos").
- `export_failed_view.dart` — `Icons.error_outline` (`DesignTokens.colorError`), generic "não foi possível
  gerar a exportação" copy (distinct text from the narrative-failed view, per the resolved Clarification) —
  no download button at all.
- `export_empty_period_view.dart` — "Nenhum registro nesse período." + the filter-adjustment suggestion — no
  download button.

No new `DesignTokens` entries — every color/icon reuses tokens already added in F000/RF06/RF07
(`colorAccent`/`colorSuccess`/`colorError`/`colorTextPrimary`/`colorTextSecondary`/spacing scale).

## Routing / DI changes

- No `app_router.dart` change — the export sheet is a modal over the existing, unparameterized
  `AppRoutes.records` route (research.md R8), same as RF06's `FilterSheet`.
- `lib/core/di/service_locator.dart`: new registrations —
  `ExportRemoteDataSource`/`ExportFileRepositoryImpl` (`registerLazySingleton`, stateless wrappers, same
  category as `EntriesRemoteDataSource`), `ExportRepository`/`ExportFileRepository`
  (`registerLazySingleton`, depending on `SessionRepository` for the former), `ExportBloc`
  (`registerFactory` — research.md R6, mirroring `InsertionModalBloc`/`VaultBloc`'s own per-open-screen
  shape, never `registerLazySingleton`).
- `pubspec.yaml`: add `share_plus: ^13.3.1` (research.md R2). No other dependency change.
