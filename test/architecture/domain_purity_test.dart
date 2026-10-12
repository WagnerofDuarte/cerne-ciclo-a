import 'dart:io';

import 'package:test/test.dart';

/// Enforces RNF06 (0 layer violations): no file under any `domain/` folder may
/// import `package:flutter` or a class from its feature's `data/` layer.
void main() {
  test('no domain/ file imports package:flutter or a data/ layer class', () {
    final domainFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.path.split(Platform.pathSeparator).contains('domain'))
        .toList();

    expect(domainFiles, isNotEmpty,
        reason: 'expected to find domain/ files under lib/');

    final importPattern = RegExp(r'''^import\s+['"]([^'"]+)['"]''');
    final violations = <String>[];

    for (final file in domainFiles) {
      for (final line in file.readAsLinesSync()) {
        final match = importPattern.firstMatch(line.trim());
        if (match == null) continue;
        final target = match.group(1)!;
        if (target.startsWith('package:flutter/')) {
          violations.add('${file.path}: imports Flutter ($target)');
        } else if (target.contains('/data/')) {
          violations.add('${file.path}: imports a data/ layer class ($target)');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
