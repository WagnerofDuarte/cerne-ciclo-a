import 'dart:io';

import 'package:test/test.dart';

/// Enforces requirements.md RF07's own acceptance criterion ("No BLoC
/// imports another BLoC directly"): no file under any `presentation/bloc/`
/// folder may import another feature's `presentation/bloc/` path. The one
/// sanctioned cross-feature touch point (`records_page.dart` importing
/// `SessionBloc`) lives under `presentation/pages/`, not matched by this scan.
void main() {
  test('no presentation/bloc/ file imports another feature\'s presentation/bloc/ path', () {
    final blocFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.path.contains('${Platform.pathSeparator}presentation${Platform.pathSeparator}bloc${Platform.pathSeparator}'))
        .toList();

    expect(blocFiles, isNotEmpty, reason: 'expected to find presentation/bloc/ files under lib/');

    final importPattern = RegExp(r'''^import\s+['"]([^'"]+)['"]''');
    final violations = <String>[];

    for (final file in blocFiles) {
      final ownFeature = _featureOf(file.path);
      for (final line in file.readAsLinesSync()) {
        final match = importPattern.firstMatch(line.trim());
        if (match == null) continue;
        final target = match.group(1)!;
        if (!target.contains('/presentation/bloc/')) continue;
        final targetFeature = _featureOfImport(target);
        if (targetFeature != null && targetFeature != ownFeature) {
          violations.add('${file.path}: imports another feature\'s bloc ($target)');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

String? _featureOf(String path) {
  final segments = path.split(Platform.pathSeparator);
  final index = segments.indexOf('features');
  if (index == -1 || index + 1 >= segments.length) return null;
  return segments[index + 1];
}

String? _featureOfImport(String importPath) {
  final segments = importPath.split('/');
  final index = segments.indexOf('features');
  if (index == -1 || index + 1 >= segments.length) return null;
  return segments[index + 1];
}
