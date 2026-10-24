import 'dart:typed_data';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:fpdart/fpdart.dart';

/// `lib/features/export/data/export_file_repository_impl.dart`
/// (contracts/export-repository.md, research.md R2) — "trigger the
/// platform's standard way of saving or sharing a downloaded file."
abstract class ExportFileRepository {
  Future<Either<Failure, Unit>> share({
    required Uint8List bytes,
    required ExportFormat format,
  });
}
