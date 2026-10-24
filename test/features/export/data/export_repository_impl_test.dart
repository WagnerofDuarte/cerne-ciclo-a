import 'dart:typed_data';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/export/data/export_remote_data_source.dart';
import 'package:cerne/features/export/data/export_repository_impl.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockExportRemoteDataSource extends Mock implements ExportRemoteDataSource {}

class MockSessionRepository extends Mock implements SessionRepository {}

Session _buildSession() => const Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresAt: 0,
  tokenType: 'bearer',
  account: Account(id: 'acc-1', email: 'test@example.com'),
);

ExportJob _buildJob() => const ExportJob(
  jobId: 'job-1',
  status: ExportJobStatus.dataReady,
  narrativeStatus: NarrativeStatus.processing,
  entryCount: 3,
  errorCode: null,
  narrativeErrorCode: null,
  downloadAvailable: false,
);

void main() {
  late MockExportRemoteDataSource remoteDataSource;
  late MockSessionRepository sessionRepository;
  late ExportRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockExportRemoteDataSource();
    sessionRepository = MockSessionRepository();
    repository = ExportRepositoryImpl(remoteDataSource, sessionRepository: sessionRepository);
  });

  group('create()', () {
    test('1: backend returns 202 {jobId} -> Right(jobId)', () async {
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async => const Right('abc'));

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result, const Right<Failure, String>('abc'));
    });

    test('2: EXPORT_EMPTY_PERIOD passes through unchanged', () async {
      const failure = ExportEmptyPeriodFailure(message: 'empty period', requestId: 'r1');
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async => const Left(failure));

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result, const Left<Failure, String>(failure));
      verifyNever(() => sessionRepository.refresh());
    });

    test('3: NETWORK_TIMEOUT passes through unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async => const Left(failure));

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result, const Left<Failure, String>(failure));
    });

    test('4: malformed body (ValidationFailure) passes through unchanged', () async {
      const failure = ValidationFailure(message: 'malformed', requestId: 'r1');
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async => const Left(failure));

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result, const Left<Failure, String>(failure));
    });

    test('5: no connection (NetworkOfflineFailure) passes through unchanged', () async {
      const failure = NetworkOfflineFailure(message: 'offline', requestId: 'r1');
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async => const Left(failure));

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result, const Left<Failure, String>(failure));
    });

    test('8/9: AuthExpiredFailure then a successful refresh retries exactly '
        'once and returns the retried call\'s Right', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
      var callCount = 0;
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? const Left(authExpired) : const Right('abc');
      });
      when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildSession()));

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result, const Right<Failure, String>('abc'));
      expect(callCount, 2);
      verify(() => sessionRepository.refresh()).called(1);
    });

    test('9: AuthExpiredFailure then a refresh that itself fails returns '
        'Left(AuthExpiredFailure), no loop', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
      when(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).thenAnswer((_) async => const Left(authExpired));
      when(() => sessionRepository.refresh()).thenAnswer(
        (_) async => const Left(AuthInvalidFailure(message: 'no token', requestId: '')),
      );

      final result = await repository.create(periodStart: null, periodEnd: null);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<AuthExpiredFailure>());
      verify(() => sessionRepository.refresh()).called(1);
      verify(
        () => remoteDataSource.create(
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
        ),
      ).called(1);
    });
  });

  group('status()', () {
    test('6: data_ready+processing parses straight through', () async {
      final job = _buildJob();
      when(() => remoteDataSource.status('job-1')).thenAnswer((_) async => Right(job));

      final result = await repository.status('job-1');

      expect(result, Right<Failure, ExportJob>(job));
    });

    test('7: malformed body (ValidationFailure) passes through unchanged', () async {
      const failure = ValidationFailure(message: 'malformed', requestId: 'r1');
      when(() => remoteDataSource.status('job-1')).thenAnswer((_) async => const Left(failure));

      final result = await repository.status('job-1');

      expect(result, const Left<Failure, ExportJob>(failure));
    });

    test('AuthExpiredFailure then a successful refresh retries and returns Right', () async {
      final job = _buildJob();
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
      var callCount = 0;
      when(() => remoteDataSource.status('job-1')).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? const Left(authExpired) : Right(job);
      });
      when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildSession()));

      final result = await repository.status('job-1');

      expect(result, Right<Failure, ExportJob>(job));
      expect(callCount, 2);
    });
  });

  group('download()', () {
    test('10: ApiClient.downloadFile (via the data source) returns Right(bytes) unchanged', () async {
      final bytes = Uint8List.fromList([9, 9, 9]);
      when(
        () => remoteDataSource.download(jobId: 'job-1', format: ExportFormat.pdf),
      ).thenAnswer((_) async => Right(bytes));

      final result = await repository.download(jobId: 'job-1', format: ExportFormat.pdf);

      expect(result, Right<Failure, Uint8List>(bytes));
    });

    test('AuthExpiredFailure then a refresh that itself fails returns '
        'Left(AuthExpiredFailure), no loop', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
      when(
        () => remoteDataSource.download(jobId: 'job-1', format: ExportFormat.raw),
      ).thenAnswer((_) async => const Left(authExpired));
      when(() => sessionRepository.refresh()).thenAnswer(
        (_) async => const Left(AuthInvalidFailure(message: 'no token', requestId: '')),
      );

      final result = await repository.download(jobId: 'job-1', format: ExportFormat.raw);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<AuthExpiredFailure>());
      verify(() => sessionRepository.refresh()).called(1);
      verify(() => remoteDataSource.download(jobId: 'job-1', format: ExportFormat.raw)).called(1);
    });
  });
}
