import 'package:cerne/core/network/failure.dart';
import 'package:equatable/equatable.dart';

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

  /// A completed-but-retryable download attempt failed; buttons stay enabled
  /// (Edge Cases: "the corresponding button returns to a retryable state").
  final Failure? pdfDownloadFailure;
  final Failure? rawDownloadFailure;

  ExportConcluded copyWith({
    bool? isDownloadingPdf,
    bool? isDownloadingRaw,
    Failure? pdfDownloadFailure,
    bool clearPdfDownloadFailure = false,
    Failure? rawDownloadFailure,
    bool clearRawDownloadFailure = false,
  }) => ExportConcluded(
    jobId: jobId,
    isDownloadingPdf: isDownloadingPdf ?? this.isDownloadingPdf,
    isDownloadingRaw: isDownloadingRaw ?? this.isDownloadingRaw,
    pdfDownloadFailure: clearPdfDownloadFailure ? null : (pdfDownloadFailure ?? this.pdfDownloadFailure),
    rawDownloadFailure: clearRawDownloadFailure ? null : (rawDownloadFailure ?? this.rawDownloadFailure),
  );

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

  ExportNarrativeFailed copyWith({
    bool? isDownloadingRaw,
    Failure? rawDownloadFailure,
    bool clearRawDownloadFailure = false,
  }) => ExportNarrativeFailed(
    jobId: jobId,
    isDownloadingRaw: isDownloadingRaw ?? this.isDownloadingRaw,
    rawDownloadFailure: clearRawDownloadFailure ? null : (rawDownloadFailure ?? this.rawDownloadFailure),
  );

  @override
  List<Object?> get props => [jobId, isDownloadingRaw, rawDownloadFailure];
}

/// FR-007 — the Clarification-resolved sixth state. Reached either from a
/// polled `ExportJob.sheetState == erroCompleto` (research.md R4) or
/// directly from any non-empty-period `POST` failure (research.md R5) — in
/// the latter case no `jobId` ever existed, so this state carries none.
class ExportFailed extends ExportState {
  const ExportFailed();
}

class ExportEmptyPeriod extends ExportState {
  const ExportEmptyPeriod();
}
