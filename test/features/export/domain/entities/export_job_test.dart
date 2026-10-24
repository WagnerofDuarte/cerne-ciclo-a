import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:test/test.dart';

ExportJob _buildJob({
  required ExportJobStatus status,
  required NarrativeStatus narrativeStatus,
}) => ExportJob(
  jobId: 'job-1',
  status: status,
  narrativeStatus: narrativeStatus,
  entryCount: null,
  errorCode: null,
  narrativeErrorCode: null,
  downloadAvailable: false,
);

void main() {
  group('ExportJob.sheetState (export-screen-states.md\'s table, research.md R4)', () {
    test('pending -> pendente, regardless of narrativeStatus', () {
      for (final narrativeStatus in NarrativeStatus.values) {
        final job = _buildJob(status: ExportJobStatus.pending, narrativeStatus: narrativeStatus);
        expect(job.sheetState, ExportSheetState.pendente);
      }
    });

    test('processing -> processando, regardless of narrativeStatus', () {
      for (final narrativeStatus in NarrativeStatus.values) {
        final job = _buildJob(status: ExportJobStatus.processing, narrativeStatus: narrativeStatus);
        expect(job.sheetState, ExportSheetState.processando);
      }
    });

    test('dataReady -> processando, regardless of narrativeStatus (Assumption: '
        'no early download link)', () {
      for (final narrativeStatus in NarrativeStatus.values) {
        final job = _buildJob(status: ExportJobStatus.dataReady, narrativeStatus: narrativeStatus);
        expect(job.sheetState, ExportSheetState.processando);
      }
    });

    test('done + done -> concluido', () {
      final job = _buildJob(status: ExportJobStatus.done, narrativeStatus: NarrativeStatus.done);
      expect(job.sheetState, ExportSheetState.concluido);
    });

    test('done + failed -> erroNarrativa', () {
      final job = _buildJob(status: ExportJobStatus.done, narrativeStatus: NarrativeStatus.failed);
      expect(job.sheetState, ExportSheetState.erroNarrativa);
    });

    test('done + skipped -> erroNarrativa', () {
      final job = _buildJob(status: ExportJobStatus.done, narrativeStatus: NarrativeStatus.skipped);
      expect(job.sheetState, ExportSheetState.erroNarrativa);
    });

    test('done + pending/processing (should never occur in practice, but the '
        'function is total) -> erroNarrativa, the catch-all branch for '
        '"done" + anything other than "done"', () {
      for (final narrativeStatus in [NarrativeStatus.pending, NarrativeStatus.processing]) {
        final job = _buildJob(status: ExportJobStatus.done, narrativeStatus: narrativeStatus);
        expect(job.sheetState, ExportSheetState.erroNarrativa);
      }
    });

    test('error -> erroCompleto, regardless of narrativeStatus', () {
      for (final narrativeStatus in NarrativeStatus.values) {
        final job = _buildJob(status: ExportJobStatus.error, narrativeStatus: narrativeStatus);
        expect(job.sheetState, ExportSheetState.erroCompleto);
      }
    });
  });
}
