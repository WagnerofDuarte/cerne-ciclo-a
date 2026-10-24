import 'dart:async';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:cerne/features/export/domain/repositories/export_file_repository.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/presentation/bloc/export_event.dart';
import 'package:cerne/features/export/presentation/bloc/export_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One new instance per `showModalBottomSheet` call (`registerFactory`,
/// research.md R6) — never reused across sheet opens. Depends only on
/// [ExportRepository]/[ExportFileRepository] — never `SessionRepository`,
/// never `RecordsBloc` or any of its event/state types.
class ExportBloc extends Bloc<ExportEvent, ExportState> {
  ExportBloc({
    required ExportRepository exportRepository,
    required ExportFileRepository exportFileRepository,
    // Not part of the public contract's constructor shape (data-model.md) —
    // overridable only for test speed, the same role `RecordsBloc`'s own
    // `debounceDuration` plays (research.md R3).
    Duration pollInterval = const Duration(seconds: 2),
  }) : _exportRepository = exportRepository, // ignore: prefer_initializing_formals
       _exportFileRepository = exportFileRepository, // ignore: prefer_initializing_formals
       _pollInterval = pollInterval, // ignore: prefer_initializing_formals
       super(const ExportPending()) {
    on<ExportRequested>(_onExportRequested);
    on<ExportStatusPollTicked>(_onStatusPollTicked);
    on<PdfDownloadRequested>(_onPdfDownloadRequested);
    on<RawDataDownloadRequested>(_onRawDataDownloadRequested);
  }

  final ExportRepository _exportRepository;
  final ExportFileRepository _exportFileRepository;
  final Duration _pollInterval;
  final _reauthController = StreamController<void>.broadcast();

  String? _jobId;
  Timer? _pollTimer;

  /// A one-shot side effect, not a state (research.md R7) — `ExportSheet`
  /// listens to this to raise the "Sessão expirada" overlay.
  Stream<void> get reauthRequired => _reauthController.stream;

  Future<void> _onExportRequested(ExportRequested event, Emitter<ExportState> emit) async {
    emit(const ExportPending());
    final result = await _exportRepository.create(
      periodStart: event.periodStart,
      periodEnd: event.periodEnd,
    );
    result.match(
      (failure) {
        if (failure is ExportEmptyPeriodFailure) {
          emit(const ExportEmptyPeriod());
          return;
        }
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
        }
        // Every other failure shape (research.md R5) — no job/jobId exists,
        // so "no data was produced" is true by construction.
        emit(const ExportFailed());
      },
      (jobId) {
        _jobId = jobId;
        add(const ExportStatusPollTicked());
      },
    );
  }

  Future<void> _onStatusPollTicked(ExportStatusPollTicked event, Emitter<ExportState> emit) async {
    final result = await _exportRepository.status(_jobId!);
    result.match(
      (failure) {
        // A transient poll failure (including a non-recoverable
        // AuthExpiredFailure) never itself transitions the sheet to
        // ExportFailed — only a job whose own status is "error" does
        // (research.md R4/R7). State is left unchanged; the timer re-arms.
        if (failure is AuthExpiredFailure) {
          _reauthController.add(null);
        }
        _armPollTimer();
      },
      (job) {
        switch (job.sheetState) {
          case ExportSheetState.pendente:
            emit(const ExportPending());
            _armPollTimer();
          case ExportSheetState.processando:
            emit(const ExportProcessing());
            _armPollTimer();
          case ExportSheetState.concluido:
            emit(ExportConcluded(jobId: job.jobId));
          case ExportSheetState.erroNarrativa:
            emit(ExportNarrativeFailed(jobId: job.jobId));
          case ExportSheetState.erroCompleto:
            emit(const ExportFailed());
          case ExportSheetState.periodoVazio:
            // Unreachable: ExportJob.sheetState never produces this value
            // (research.md R4/R6) — periodoVazio only ever comes from a
            // POST failure, handled in _onExportRequested.
            emit(const ExportFailed());
        }
      },
    );
  }

  void _armPollTimer() {
    _pollTimer = Timer(_pollInterval, () => add(const ExportStatusPollTicked()));
  }

  Future<void> _onPdfDownloadRequested(
    PdfDownloadRequested event,
    Emitter<ExportState> emit,
  ) async {
    final current = state;
    if (current is! ExportConcluded || current.isDownloadingPdf) return;
    emit(current.copyWith(isDownloadingPdf: true, clearPdfDownloadFailure: true));

    final failure = await _downloadAndShare(jobId: current.jobId, format: ExportFormat.pdf);

    final latest = state;
    if (latest is ExportConcluded && latest.jobId == current.jobId) {
      emit(
        latest.copyWith(
          isDownloadingPdf: false,
          pdfDownloadFailure: failure,
          clearPdfDownloadFailure: failure == null,
        ),
      );
    }
  }

  Future<void> _onRawDataDownloadRequested(
    RawDataDownloadRequested event,
    Emitter<ExportState> emit,
  ) async {
    final current = state;
    final String jobId;
    if (current is ExportConcluded && !current.isDownloadingRaw) {
      jobId = current.jobId;
      emit(current.copyWith(isDownloadingRaw: true, clearRawDownloadFailure: true));
    } else if (current is ExportNarrativeFailed && !current.isDownloadingRaw) {
      jobId = current.jobId;
      emit(current.copyWith(isDownloadingRaw: true, clearRawDownloadFailure: true));
    } else {
      return;
    }

    final failure = await _downloadAndShare(jobId: jobId, format: ExportFormat.raw);

    final latest = state;
    if (latest is ExportConcluded && latest.jobId == jobId) {
      emit(
        latest.copyWith(
          isDownloadingRaw: false,
          rawDownloadFailure: failure,
          clearRawDownloadFailure: failure == null,
        ),
      );
    } else if (latest is ExportNarrativeFailed && latest.jobId == jobId) {
      emit(
        latest.copyWith(
          isDownloadingRaw: false,
          rawDownloadFailure: failure,
          clearRawDownloadFailure: failure == null,
        ),
      );
    }
  }

  /// Shared by both download buttons: download then share, returning the
  /// first `Failure` encountered (from either step), or `null` on success.
  /// Fires `reauthRequired` on an `AuthExpiredFailure` but never regresses
  /// the sheet to `ExportFailed` — the caller stays on `ExportConcluded`/
  /// `ExportNarrativeFailed` throughout.
  Future<Failure?> _downloadAndShare({
    required String jobId,
    required ExportFormat format,
  }) async {
    final downloadResult = await _exportRepository.download(jobId: jobId, format: format);
    return downloadResult.match(
      (failure) {
        if (failure is AuthExpiredFailure) _reauthController.add(null);
        return Future<Failure?>.value(failure);
      },
      (bytes) async {
        final shareResult = await _exportFileRepository.share(bytes: bytes, format: format);
        return shareResult.match<Failure?>((failure) => failure, (_) => null);
      },
    );
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    unawaited(_reauthController.close());
    return super.close();
  }
}
