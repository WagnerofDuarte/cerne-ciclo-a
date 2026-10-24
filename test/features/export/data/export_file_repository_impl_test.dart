import 'dart:io';
import 'dart:typed_data';

import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/data/export_file_repository_impl.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:test/test.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.temporaryPath);

  final String? temporaryPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

class _FakeSharePlatform extends Fake with MockPlatformInterfaceMixin implements SharePlatform {
  List<XFile>? sharedFiles;
  Object? throwOnShare;

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (throwOnShare != null) throw throwOnShare!;
    sharedFiles = params.files;
    // A user-cancelled share — share_plus reports this as a normal,
    // non-throwing ShareResult (research.md, contracts/export-repository.md).
    return const ShareResult('', ShareResultStatus.dismissed);
  }
}

void main() {
  late Directory tempDir;
  late _FakeSharePlatform sharePlatform;
  late ExportFileRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export_file_repository_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    sharePlatform = _FakeSharePlatform();
    SharePlatform.instance = sharePlatform;
    repository = ExportFileRepositoryImpl();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('1: write+share succeeds, including a user-cancelled share, resolving '
      'to Right(unit)', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final result = await repository.share(bytes: bytes, format: ExportFormat.pdf);

    expect(result, const Right<Failure, Unit>(unit));
    expect(sharePlatform.sharedFiles, hasLength(1));
    expect(sharePlatform.sharedFiles!.single.path, endsWith('cerne-resumo.pdf'));
    final written = await File(sharePlatform.sharedFiles!.single.path).readAsBytes();
    expect(written, bytes);
  });

  test('raw format is written as cerne-dados.json', () async {
    final bytes = Uint8List.fromList([4, 5, 6]);

    await repository.share(bytes: bytes, format: ExportFormat.raw);

    expect(sharePlatform.sharedFiles!.single.path, endsWith('cerne-dados.json'));
  });

  test('2: a file-write throw (e.g. disk full) resolves to Left(NetworkTimeoutFailure)', () async {
    // A temp path that cannot be written to (the parent directory does not
    // exist) forces `File.writeAsBytes` to throw.
    PathProviderPlatform.instance = _FakePathProviderPlatform('${tempDir.path}/does-not-exist/nested');

    final result = await repository.share(
      bytes: Uint8List.fromList([1]),
      format: ExportFormat.pdf,
    );

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<NetworkTimeoutFailure>());
  });
}
