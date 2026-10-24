import 'package:equatable/equatable.dart';

/// `GET /export/{jobId}/status`'s own `status` enum (data-model.md).
enum ExportJobStatus { pending, processing, dataReady, done, error }

/// `GET /export/{jobId}/status`'s own `narrativeStatus` enum.
enum NarrativeStatus { pending, processing, done, failed, skipped }

/// The sheet's own six visual states (`export-screen-states.md`). `erroCompleto`
/// is the Clarification-resolved sixth value, distinct from `erroNarrativa`
/// (research.md R4); `periodoVazio` is never produced by [ExportJobSheetState]
/// — it has no corresponding [ExportJob] (research.md R6).
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
  /// Pure, total mapping of `export-screen-states.md`'s own table (research.md
  /// R4) — the one place this mapping's correctness is asserted (RNF07).
  /// `errorCode`/`narrativeErrorCode` are never branched on here (FR-007).
  ExportSheetState get sheetState => switch ((status, narrativeStatus)) {
    (ExportJobStatus.pending, _) => ExportSheetState.pendente,
    (ExportJobStatus.processing, _) => ExportSheetState.processando,
    (ExportJobStatus.dataReady, _) => ExportSheetState.processando,
    (ExportJobStatus.done, NarrativeStatus.done) => ExportSheetState.concluido,
    (ExportJobStatus.done, _) => ExportSheetState.erroNarrativa,
    (ExportJobStatus.error, _) => ExportSheetState.erroCompleto,
  };
}
