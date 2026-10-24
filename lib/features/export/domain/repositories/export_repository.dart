import 'dart:typed_data';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/domain/entities/export_job.dart';
import 'package:fpdart/fpdart.dart';

enum ExportFormat { pdf, raw }

/// `lib/features/export/data/export_repository_impl.dart` (contracts/export-repository.md).
/// Every method retries exactly once through `SessionRepository.refresh()` on
/// a first-attempt `AuthExpiredFailure` (research.md R7), identical in shape
/// to `EntriesRepositoryImpl`'s.
abstract class ExportRepository {
  /// `POST /export/summary` (`export-summary-create`). Returns the new jobId.
  Future<Either<Failure, String>> create({
    required DateTime? periodStart,
    required DateTime? periodEnd,
  });

  /// `GET /export/{jobId}/status` (`export-status-get`).
  Future<Either<Failure, ExportJob>> status(String jobId);

  /// `ApiClient.downloadFile` (`export-download-get`, research.md R1).
  Future<Either<Failure, Uint8List>> download({
    required String jobId,
    required ExportFormat format,
  });
}
