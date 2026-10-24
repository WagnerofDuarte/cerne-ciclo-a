import 'dart:io';
import 'dart:typed_data';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/domain/repositories/export_file_repository.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// Writes [bytes] to the OS temp directory, then summons the platform's
/// share sheet (research.md R2) via `SharePlatform.instance` directly —
/// `SharePlus.instance` caches its platform in a `static final` field on
/// first access, which would make it invisible to a test that reassigns
/// `SharePlatform.instance` afterward; going straight to the platform
/// interface (the same one `SharePlus`/`Share` ultimately delegate to)
/// avoids that. A user-cancelled share is reported by `share_plus` as a
/// normal, non-throwing `ShareResult` — never reaches the `catch` below,
/// and is treated as success: the file *was* produced and offered.
class ExportFileRepositoryImpl implements ExportFileRepository {
  @override
  Future<Either<Failure, Unit>> share({
    required Uint8List bytes,
    required ExportFormat format,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final extension = format == ExportFormat.pdf ? 'pdf' : 'json';
      final name = format == ExportFormat.pdf ? 'cerne-resumo' : 'cerne-dados';
      final file = File('${dir.path}/$name.$extension');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlatform.instance.share(ShareParams(files: [XFile(file.path)]));
      return const Right(unit);
    } catch (_) {
      return const Left(
        NetworkTimeoutFailure(message: 'Falha ao salvar/compartilhar o arquivo.', requestId: ''),
      );
    }
  }
}
