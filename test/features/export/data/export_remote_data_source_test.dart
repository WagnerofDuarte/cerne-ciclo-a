import 'dart:typed_data';

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/data/export_remote_data_source.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late ExportRemoteDataSource dataSource;

  setUp(() {
    apiClient = MockApiClient();
    dataSource = ExportRemoteDataSource(apiClient);
  });

  group('create()', () {
    test('parses data.jobId from a well-formed response', () async {
      when(
        () => apiClient.call(
          'export-summary-create',
          method: 'POST',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Right({'jobId': 'job-1'}));

      final result = await dataSource.create(periodStart: null, periodEnd: null);

      expect(result, const Right<Failure, String>('job-1'));
    });

    test('sends periodStart/periodEnd as explicit null plus includeNarrative '
        'true', () async {
      when(
        () => apiClient.call(
          'export-summary-create',
          method: 'POST',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Right({'jobId': 'job-1'}));

      await dataSource.create(periodStart: null, periodEnd: null);

      verify(
        () => apiClient.call(
          'export-summary-create',
          method: 'POST',
          body: {'periodStart': null, 'periodEnd': null, 'includeNarrative': true},
        ),
      ).called(1);
    });

    test('a missing jobId maps to ValidationFailure', () async {
      when(
        () => apiClient.call(
          'export-summary-create',
          method: 'POST',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Right({}));

      final result = await dataSource.create(periodStart: null, periodEnd: null);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a Left from ApiClient passes through unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
      when(
        () => apiClient.call(
          'export-summary-create',
          method: 'POST',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Left(failure));

      final result = await dataSource.create(periodStart: null, periodEnd: null);

      expect(result, const Left<Failure, String>(failure));
    });
  });

  group('status()', () {
    test('the data_ready lookup-table case parses to ExportJobStatus.dataReady', () async {
      when(
        () => apiClient.call('export-status-get', method: 'GET', pathSegments: ['job-1']),
      ).thenAnswer(
        (_) async => const Right({
          'jobId': 'job-1',
          'status': 'data_ready',
          'narrativeStatus': 'processing',
          'entryCount': 5,
          'errorCode': null,
          'narrativeErrorCode': null,
          'downloadAvailable': false,
        }),
      );

      final result = await dataSource.status('job-1');

      expect(
        result,
        const Right<Failure, ExportJob>(
          ExportJob(
            jobId: 'job-1',
            status: ExportJobStatus.dataReady,
            narrativeStatus: NarrativeStatus.processing,
            entryCount: 5,
            errorCode: null,
            narrativeErrorCode: null,
            downloadAvailable: false,
          ),
        ),
      );
    });

    test('every other status value parses via .byName', () async {
      when(
        () => apiClient.call('export-status-get', method: 'GET', pathSegments: ['job-1']),
      ).thenAnswer(
        (_) async => const Right({
          'jobId': 'job-1',
          'status': 'done',
          'narrativeStatus': 'done',
          'entryCount': 5,
          'errorCode': null,
          'narrativeErrorCode': null,
          'downloadAvailable': true,
        }),
      );

      final result = await dataSource.status('job-1');

      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable()?.status, ExportJobStatus.done);
      expect(result.getRight().toNullable()?.narrativeStatus, NarrativeStatus.done);
    });

    test('a malformed body (missing a required field) maps to ValidationFailure', () async {
      when(
        () => apiClient.call('export-status-get', method: 'GET', pathSegments: ['job-1']),
      ).thenAnswer((_) async => const Right({'jobId': 'job-1', 'status': 'pending'}));

      final result = await dataSource.status('job-1');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('an unrecognized status wire value maps to ValidationFailure, '
        'never throws', () async {
      when(
        () => apiClient.call('export-status-get', method: 'GET', pathSegments: ['job-1']),
      ).thenAnswer(
        (_) async => const Right({
          'jobId': 'job-1',
          'status': 'something_unknown',
          'narrativeStatus': 'pending',
          'entryCount': null,
          'errorCode': null,
          'narrativeErrorCode': null,
          'downloadAvailable': false,
        }),
      );

      final result = await dataSource.status('job-1');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });
  });

  group('download()', () {
    test('delegates to ApiClient.downloadFile with the jobId/format passed through', () async {
      when(
        () => apiClient.downloadFile(
          'export-download-get',
          pathSegments: ['job-1'],
          queryParameters: {'format': 'pdf'},
        ),
      ).thenAnswer((_) async => Right(Uint8ListFixture.bytes));

      final result = await dataSource.download(jobId: 'job-1', format: ExportFormat.pdf);

      expect(result, Right<Failure, dynamic>(Uint8ListFixture.bytes));
      verify(
        () => apiClient.downloadFile(
          'export-download-get',
          pathSegments: ['job-1'],
          queryParameters: {'format': 'pdf'},
        ),
      ).called(1);
    });
  });
}

class Uint8ListFixture {
  static final bytes = Uint8List.fromList([1, 2, 3]);
}
