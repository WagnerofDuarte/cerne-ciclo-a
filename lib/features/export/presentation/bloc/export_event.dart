import 'package:equatable/equatable.dart';

sealed class ExportEvent extends Equatable {
  const ExportEvent();
  @override
  List<Object?> get props => [];
}

/// `ExportSheet.initState` — the one and only time a job is requested for
/// that sheet instance.
class ExportRequested extends ExportEvent {
  const ExportRequested(this.periodStart, this.periodEnd);

  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  List<Object?> get props => [periodStart, periodEnd];
}

/// Dispatched once immediately after a successful [ExportRequested], then
/// re-armed by a `Timer` after each non-terminal poll response (research.md
/// R3) — never dispatched directly by any widget.
class ExportStatusPollTicked extends ExportEvent {
  const ExportStatusPollTicked();
}

/// "Baixar PDF" tapped (`ExportConcluded` only).
class PdfDownloadRequested extends ExportEvent {
  const PdfDownloadRequested();
}

/// "Baixar dados brutos" tapped (`ExportConcluded` or `ExportNarrativeFailed`).
class RawDataDownloadRequested extends ExportEvent {
  const RawDataDownloadRequested();
}
