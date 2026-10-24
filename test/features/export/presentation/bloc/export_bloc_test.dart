import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:cerne/features/export/domain/repositories/export_file_repository.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/presentation/bloc/export_bloc.dart';
import 'package:cerne/features/export/presentation/bloc/export_event.dart';
import 'package:cerne/features/export/presentation/bloc/export_state.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockExportRepository extends Mock implements ExportRepository {}

class MockExportFileRepository extends Mock implements ExportFileRepository {}

ExportJob _buildJob({
  required ExportJobStatus status,
  required NarrativeStatus narrativeStatus,
  String jobId = 'job-1',
}) => ExportJob(
  jobId: jobId,
  status: status,
  narrativeStatus: narrativeStatus,
  entryCount: 3,
  errorCode: null,
  narrativeErrorCode: null,
  downloadAvailable: status == ExportJobStatus.done,
);

void main() {
  late MockExportRepository exportRepository;
  late MockExportFileRepository exportFileRepository;

  setUpAll(() {
    registerFallbackValue(ExportFormat.pdf);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    exportRepository = MockExportRepository();
    exportFileRepository = MockExportFileRepository();
    when(
      () => exportRepository.create(
        periodStart: any(named: 'periodStart'),
        periodEnd: any(named: 'periodEnd'),
      ),
    ).thenAnswer((_) async => const Right('job-1'));
  });

  ExportBloc buildBloc({Duration pollInterval = Duration.zero}) => ExportBloc(
    exportRepository: exportRepository,
    exportFileRepository: exportFileRepository,
    pollInterval: pollInterval,
  );

  group('ExportRequested (contract scenario 1-4)', () {
    blocTest<ExportBloc, ExportState>(
      '1: create() succeeds -> ExportPending(), then whatever status() maps to',
      setUp: () {
        when(() => exportRepository.status('job-1')).thenAnswer(
          (_) async =>
              Right(_buildJob(status: ExportJobStatus.processing, narrativeStatus: NarrativeStatus.processing)),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      expect: () => [const ExportPending(), const ExportProcessing()],
    );

    blocTest<ExportBloc, ExportState>(
      '2: create() returns ExportEmptyPeriodFailure -> ExportPending(), '
      'ExportEmptyPeriod(), no poll ever dispatched',
      setUp: () {
        when(
          () => exportRepository.create(
            periodStart: any(named: 'periodStart'),
            periodEnd: any(named: 'periodEnd'),
          ),
        ).thenAnswer(
          (_) async => const Left(ExportEmptyPeriodFailure(message: 'empty', requestId: 'r1')),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      expect: () => [const ExportPending(), const ExportEmptyPeriod()],
      verify: (_) {
        verifyNever(() => exportRepository.status(any()));
      },
    );

    blocTest<ExportBloc, ExportState>(
      '3: create() returns NetworkOfflineFailure -> ExportPending(), '
      'ExportFailed(), no poll ever dispatched',
      setUp: () {
        when(
          () => exportRepository.create(
            periodStart: any(named: 'periodStart'),
            periodEnd: any(named: 'periodEnd'),
          ),
        ).thenAnswer(
          (_) async => const Left(NetworkOfflineFailure(message: 'offline', requestId: 'r1')),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      expect: () => [const ExportPending(), const ExportFailed()],
      verify: (_) {
        verifyNever(() => exportRepository.status(any()));
      },
    );

    blocTest<ExportBloc, ExportState>(
      '4: create() returns AuthExpiredFailure (post-retry) -> ExportPending(), '
      'ExportFailed(); reauthRequired emits exactly once',
      setUp: () {
        when(
          () => exportRepository.create(
            periodStart: any(named: 'periodStart'),
            periodEnd: any(named: 'periodEnd'),
          ),
        ).thenAnswer(
          (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
        );
      },
      build: buildBloc,
      act: (bloc) async {
        final events = <void>[];
        final sub = bloc.reauthRequired.listen(events.add);
        bloc.add(const ExportRequested(null, null));
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        await sub.cancel();
      },
      expect: () => [const ExportPending(), const ExportFailed()],
    );
  });

  group('ExportStatusPollTicked (contract scenarios 5-8)', () {
    blocTest<ExportBloc, ExportState>(
      '5: pending -> processing -> done/done; _pollTimer armed twice, never '
      'a third time (SC-005)',
      setUp: () {
        var call = 0;
        when(() => exportRepository.status('job-1')).thenAnswer((_) async {
          call++;
          return switch (call) {
            1 => Right(_buildJob(status: ExportJobStatus.pending, narrativeStatus: NarrativeStatus.pending)),
            2 => Right(
              _buildJob(status: ExportJobStatus.processing, narrativeStatus: NarrativeStatus.processing),
            ),
            _ => Right(_buildJob(status: ExportJobStatus.done, narrativeStatus: NarrativeStatus.done)),
          };
        });
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      wait: const Duration(milliseconds: 20),
      // The "pending" status poll result maps to ExportPending() again, but
      // Bloc's own emit() skips re-emitting a state equal to the current one
      // (bloc_base.dart) — so only the status *change*s are observed.
      expect: () => [
        const ExportPending(),
        const ExportProcessing(),
        const ExportConcluded(jobId: 'job-1'),
      ],
      verify: (_) {
        verify(() => exportRepository.status('job-1')).called(3);
      },
    );

    blocTest<ExportBloc, ExportState>(
      '6: processing -> done/failed -> ExportNarrativeFailed(jobId)',
      setUp: () {
        var call = 0;
        when(() => exportRepository.status('job-1')).thenAnswer((_) async {
          call++;
          return call == 1
              ? Right(
                  _buildJob(status: ExportJobStatus.processing, narrativeStatus: NarrativeStatus.processing),
                )
              : Right(_buildJob(status: ExportJobStatus.done, narrativeStatus: NarrativeStatus.failed));
        });
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const ExportPending(),
        const ExportProcessing(),
        const ExportNarrativeFailed(jobId: 'job-1'),
      ],
    );

    blocTest<ExportBloc, ExportState>(
      '7: processing -> error -> ExportFailed()',
      setUp: () {
        var call = 0;
        when(() => exportRepository.status('job-1')).thenAnswer((_) async {
          call++;
          return call == 1
              ? Right(
                  _buildJob(status: ExportJobStatus.processing, narrativeStatus: NarrativeStatus.processing),
                )
              : Right(_buildJob(status: ExportJobStatus.error, narrativeStatus: NarrativeStatus.pending));
        });
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      wait: const Duration(milliseconds: 20),
      expect: () => [const ExportPending(), const ExportProcessing(), const ExportFailed()],
    );

    blocTest<ExportBloc, ExportState>(
      '8: one tick fails with NetworkTimeoutFailure, the next succeeds and '
      'reaches done/done -> the failed tick produces no state emission at all',
      setUp: () {
        var call = 0;
        when(() => exportRepository.status('job-1')).thenAnswer((_) async {
          call++;
          if (call == 1) {
            return const Left(NetworkTimeoutFailure(message: 'timed out', requestId: 'r1'));
          }
          return Right(_buildJob(status: ExportJobStatus.done, narrativeStatus: NarrativeStatus.done));
        });
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ExportRequested(null, null)),
      wait: const Duration(milliseconds: 20),
      expect: () => [const ExportPending(), const ExportConcluded(jobId: 'job-1')],
      verify: (_) {
        verify(() => exportRepository.status('job-1')).called(2);
      },
    );
  });

  group('PdfDownloadRequested (contract scenarios 9-10)', () {
    blocTest<ExportBloc, ExportState>(
      '9: dispatched twice in a row before the first resolves -> download '
      'called exactly once',
      seed: () => const ExportConcluded(jobId: 'job-1'),
      build: buildBloc,
      setUp: () {
        final completer = Completer<Either<Failure, Uint8List>>();
        when(
          () => exportRepository.download(jobId: 'job-1', format: ExportFormat.pdf),
        ).thenAnswer((_) => completer.future);
      },
      act: (bloc) {
        bloc.add(const PdfDownloadRequested());
        bloc.add(const PdfDownloadRequested());
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [const ExportConcluded(jobId: 'job-1', isDownloadingPdf: true)],
      verify: (_) {
        verify(() => exportRepository.download(jobId: 'job-1', format: ExportFormat.pdf)).called(1);
      },
    );

    blocTest<ExportBloc, ExportState>(
      '10: download() succeeds but share() fails -> ExportConcluded('
      'isDownloadingPdf: false, pdfDownloadFailure: <failure>), jobId '
      'unchanged, rawDownloadFailure untouched',
      seed: () => const ExportConcluded(jobId: 'job-1'),
      build: buildBloc,
      setUp: () {
        when(
          () => exportRepository.download(jobId: 'job-1', format: ExportFormat.pdf),
        ).thenAnswer((_) async => Right(Uint8List.fromList([1, 2, 3])));
        when(
          () => exportFileRepository.share(bytes: any(named: 'bytes'), format: ExportFormat.pdf),
        ).thenAnswer(
          (_) async => const Left(NetworkTimeoutFailure(message: 'share failed', requestId: 'r1')),
        );
      },
      act: (bloc) => bloc.add(const PdfDownloadRequested()),
      expect: () => [
        const ExportConcluded(jobId: 'job-1', isDownloadingPdf: true),
        isA<ExportConcluded>()
            .having((s) => s.jobId, 'jobId', 'job-1')
            .having((s) => s.isDownloadingPdf, 'isDownloadingPdf', false)
            .having((s) => s.pdfDownloadFailure, 'pdfDownloadFailure', isA<NetworkTimeoutFailure>())
            .having((s) => s.rawDownloadFailure, 'rawDownloadFailure', isNull),
      ],
    );
  });

  group('RawDataDownloadRequested (contract scenarios 11-13)', () {
    blocTest<ExportBloc, ExportState>(
      '11: from ExportNarrativeFailed succeeds -> ExportNarrativeFailed('
      'isDownloadingRaw: false, rawDownloadFailure: null) — never transitions '
      'to ExportConcluded',
      seed: () => const ExportNarrativeFailed(jobId: 'job-1'),
      build: buildBloc,
      setUp: () {
        when(
          () => exportRepository.download(jobId: 'job-1', format: ExportFormat.raw),
        ).thenAnswer((_) async => Right(Uint8List.fromList([1])));
        when(
          () => exportFileRepository.share(bytes: any(named: 'bytes'), format: ExportFormat.raw),
        ).thenAnswer((_) async => const Right(unit));
      },
      act: (bloc) => bloc.add(const RawDataDownloadRequested()),
      expect: () => [
        const ExportNarrativeFailed(jobId: 'job-1', isDownloadingRaw: true),
        const ExportNarrativeFailed(jobId: 'job-1'),
      ],
    );

    blocTest<ExportBloc, ExportState>(
      '12: dispatched twice in a row before the first resolves -> download '
      'called exactly once',
      seed: () => const ExportConcluded(jobId: 'job-1'),
      build: buildBloc,
      setUp: () {
        final completer = Completer<Either<Failure, Uint8List>>();
        when(
          () => exportRepository.download(jobId: 'job-1', format: ExportFormat.raw),
        ).thenAnswer((_) => completer.future);
      },
      act: (bloc) {
        bloc.add(const RawDataDownloadRequested());
        bloc.add(const RawDataDownloadRequested());
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [const ExportConcluded(jobId: 'job-1', isDownloadingRaw: true)],
      verify: (_) {
        verify(() => exportRepository.download(jobId: 'job-1', format: ExportFormat.raw)).called(1);
      },
    );

    blocTest<ExportBloc, ExportState>(
      '13: from ExportNarrativeFailed where download() succeeds but share() '
      'fails -> ExportNarrativeFailed(isDownloadingRaw: false, '
      'rawDownloadFailure: <failure>), jobId unchanged',
      seed: () => const ExportNarrativeFailed(jobId: 'job-1'),
      build: buildBloc,
      setUp: () {
        when(
          () => exportRepository.download(jobId: 'job-1', format: ExportFormat.raw),
        ).thenAnswer((_) async => Right(Uint8List.fromList([1])));
        when(
          () => exportFileRepository.share(bytes: any(named: 'bytes'), format: ExportFormat.raw),
        ).thenAnswer(
          (_) async => const Left(NetworkTimeoutFailure(message: 'share failed', requestId: 'r1')),
        );
      },
      act: (bloc) => bloc.add(const RawDataDownloadRequested()),
      expect: () => [
        const ExportNarrativeFailed(jobId: 'job-1', isDownloadingRaw: true),
        isA<ExportNarrativeFailed>()
            .having((s) => s.jobId, 'jobId', 'job-1')
            .having((s) => s.isDownloadingRaw, 'isDownloadingRaw', false)
            .having((s) => s.rawDownloadFailure, 'rawDownloadFailure', isA<NetworkTimeoutFailure>()),
      ],
    );
  });
}
