# Contract: `ExportBloc`

`lib/features/export/presentation/bloc/export_bloc.dart` (+ `export_event.dart`/`export_state.dart`). One new
instance per `showModalBottomSheet` call (`registerFactory`, research.md R6) — never reused across sheet
opens.

```dart
class ExportBloc extends Bloc<ExportEvent, ExportState> {
  ExportBloc({required ExportRepository exportRepository, required ExportFileRepository exportFileRepository});

  Stream<void> get reauthRequired;   // one-shot, identical shape to RecordsBloc's (research.md R7)
}
```

Depends only on `ExportRepository`/`ExportFileRepository` — never `SessionRepository`, never `RecordsBloc` or
any of its event/state types.

## Event → state sequence

```
ExportRequested(periodStart, periodEnd)
  -> emit ExportPending()
  -> ExportRepository.create(periodStart, periodEnd)
     -> Left(ExportEmptyPeriodFailure)         -> emit ExportEmptyPeriod()                      [terminal]
     -> Left(AuthExpiredFailure)               -> reauthRequired.add(null); emit ExportFailed()  [terminal]
     -> Left(other Failure)                    -> emit ExportFailed()                            [terminal]
     -> Right(jobId)                           -> store _jobId; add(ExportStatusPollTicked())

ExportStatusPollTicked
  -> ExportRepository.status(_jobId!)
     -> Left(AuthExpiredFailure)  -> reauthRequired.add(null); re-arm Timer(2s, add(ExportStatusPollTicked()))
     -> Left(other Failure)       -> re-arm Timer(2s, add(ExportStatusPollTicked())); state unchanged
     -> Right(job) where job.sheetState is:
        pendente     -> emit ExportPending();     re-arm Timer(2s, ...)
        processando   -> emit ExportProcessing();  re-arm Timer(2s, ...)
        concluido     -> emit ExportConcluded(jobId: job.jobId)                                  [terminal]
        erroNarrativa -> emit ExportNarrativeFailed(jobId: job.jobId)                            [terminal]
        erroCompleto  -> emit ExportFailed()                                                     [terminal]

PdfDownloadRequested                             (ExportConcluded only)
  -> no-op if state.isDownloadingPdf
  -> emit state.copyWith(isDownloadingPdf: true, pdfDownloadFailure: null)
  -> ExportRepository.download(jobId, ExportFormat.pdf)
     -> Left(failure) -> (reauthRequired if AuthExpiredFailure) emit state.copyWith(isDownloadingPdf: false, pdfDownloadFailure: failure)
     -> Right(bytes)  -> ExportFileRepository.share(bytes, ExportFormat.pdf)
        -> Left(failure) -> emit state.copyWith(isDownloadingPdf: false, pdfDownloadFailure: failure)
        -> Right(_)      -> emit state.copyWith(isDownloadingPdf: false, pdfDownloadFailure: null)

RawDataDownloadRequested                          (ExportConcluded or ExportNarrativeFailed)
  -> identical shape to PdfDownloadRequested, targeting ExportFormat.raw / isDownloadingRaw / rawDownloadFailure
```

- "Terminal" means `_pollTimer` is **not** re-armed — no further `ExportStatusPollTicked` is ever dispatched
  for that `ExportBloc` instance after reaching one of `ExportConcluded`/`ExportNarrativeFailed`/
  `ExportFailed`/`ExportEmptyPeriod` (SC-005).
- A poll-call failure (any cause, including a non-recoverable `AuthExpiredFailure`) never itself transitions
  the sheet to `ExportFailed` — only a job whose own `status` the backend reports as `error` does (research.md
  R4/R7). This is deliberate: a transient network hiccup mid-poll must not be indistinguishable from the
  job itself having failed.
- `close()` cancels `_pollTimer` and closes `_reauthController` — mirrors `RecordsBloc.close()` exactly.

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `ExportRequested` where `create()` succeeds | states emitted, in order: `ExportPending()`, then (after the first poll) whatever `status()`'s first response maps to |
| 2 | `ExportRequested` where `create()` returns `ExportEmptyPeriodFailure` | states: `ExportPending()`, `ExportEmptyPeriod()` — no poll ever dispatched |
| 3 | `ExportRequested` where `create()` returns `NetworkOfflineFailure` | states: `ExportPending()`, `ExportFailed()` — no poll ever dispatched |
| 4 | `ExportRequested` where `create()` returns `AuthExpiredFailure` (post-retry) | states: `ExportPending()`, `ExportFailed()`; `reauthRequired` emits exactly once |
| 5 | Poll sequence: `pending` → `processing` → `done`/`done` | states: `ExportPending()`, `ExportProcessing()`, `ExportConcluded(jobId)` — exactly 3 terminal-bound emissions, `_pollTimer` armed twice, never a third time |
| 6 | Poll sequence: `processing` → `done`/`failed` | states end on `ExportNarrativeFailed(jobId)` |
| 7 | Poll sequence: `processing` → `error` | states end on `ExportFailed()` |
| 8 | One poll tick fails with `NetworkTimeoutFailure`, the next succeeds and reaches `done`/`done` | the failed tick produces **no** state emission at all; the sheet never flashes `ExportFailed()` for a transient poll failure |
| 9 | `PdfDownloadRequested` dispatched twice in a row before the first resolves | `ExportRepository.download` is called exactly once (the second dispatch is a no-op per `isDownloadingPdf`) |
| 10 | `PdfDownloadRequested` where `download()` succeeds but `share()` fails | final state: `ExportConcluded(isDownloadingPdf: false, pdfDownloadFailure: <failure>)` — `jobId` unchanged, `rawDownloadFailure` untouched |
| 11 | `RawDataDownloadRequested` from `ExportNarrativeFailed` succeeds | final state: `ExportNarrativeFailed(isDownloadingRaw: false, rawDownloadFailure: null)` — never transitions to `ExportConcluded` |
| 12 | `RawDataDownloadRequested` dispatched twice in a row before the first resolves (from either `ExportConcluded` or `ExportNarrativeFailed`) | `ExportRepository.download` is called exactly once (the second dispatch is a no-op per `isDownloadingRaw`) |
| 13 | `RawDataDownloadRequested` from `ExportNarrativeFailed` where `download()` succeeds but `share()` fails | final state: `ExportNarrativeFailed(isDownloadingRaw: false, rawDownloadFailure: <failure>)` — `jobId` unchanged |
