import 'dart:typed_data';

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:fpdart/fpdart.dart';

const _malformedExportFailure = ValidationFailure(
  message: 'Malformed export response',
  requestId: '',
);

/// `status`'s wire value `data_ready` cannot parse via `.byName` (Dart enum
/// names cannot contain an underscore the way the wire value does) — every
/// other value parses via `.byName` as usual (contracts/export-repository.md).
const _statusByWireValue = {
  'pending': ExportJobStatus.pending,
  'processing': ExportJobStatus.processing,
  'data_ready': ExportJobStatus.dataReady,
  'done': ExportJobStatus.done,
  'error': ExportJobStatus.error,
};

/// The only class that calls `ApiClient.call('export-summary-create'/
/// 'export-status-get', ...)`/`ApiClient.downloadFile('export-download-get', ...)`
/// and parses the `jobId`/[ExportJob] response shapes (data-model.md,
/// contracts/export-repository.md).
class ExportRemoteDataSource {
  const ExportRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, String>> create({
    required DateTime? periodStart,
    required DateTime? periodEnd,
  }) async {
    final result = await _apiClient.call(
      'export-summary-create',
      method: 'POST',
      body: {
        'periodStart': periodStart?.toUtc().toIso8601String(),
        'periodEnd': periodEnd?.toUtc().toIso8601String(),
        'includeNarrative': true,
      },
    );

    return result.flatMap(_parseJobId);
  }

  Future<Either<Failure, ExportJob>> status(String jobId) async {
    final result = await _apiClient.call(
      'export-status-get',
      method: 'GET',
      pathSegments: [jobId],
    );

    return result.flatMap(_parseExportJob);
  }

  Future<Either<Failure, Uint8List>> download({
    required String jobId,
    required ExportFormat format,
  }) {
    return _apiClient.downloadFile(
      'export-download-get',
      pathSegments: [jobId],
      queryParameters: {'format': format.name},
    );
  }

  Either<Failure, String> _parseJobId(Map<String, dynamic> data) {
    final jobId = data['jobId'];
    if (jobId is! String) return const Left(_malformedExportFailure);
    return Right(jobId);
  }

  Either<Failure, ExportJob> _parseExportJob(Map<String, dynamic> data) {
    try {
      final status = _statusByWireValue[data['status'] as String];
      if (status == null) return const Left(_malformedExportFailure);
      return Right(
        ExportJob(
          jobId: data['jobId'] as String,
          status: status,
          narrativeStatus: NarrativeStatus.values.byName(data['narrativeStatus'] as String),
          entryCount: data['entryCount'] as int?,
          errorCode: data['errorCode'] as String?,
          narrativeErrorCode: data['narrativeErrorCode'] as String?,
          downloadAvailable: data['downloadAvailable'] as bool,
        ),
      );
    } on TypeError {
      return const Left(_malformedExportFailure);
    } on FormatException {
      return const Left(_malformedExportFailure);
    } on ArgumentError {
      // ExportJobStatus/NarrativeStatus.values.byName throws ArgumentError
      // for an unrecognized wire value — never an unhandled crash (FR-003).
      return const Left(_malformedExportFailure);
    }
  }
}
