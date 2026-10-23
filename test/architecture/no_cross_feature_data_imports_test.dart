import 'dart:io';

import 'package:test/test.dart';

/// Enforces P-RF10's FR-009: entry creation triggered from chat MUST go
/// through the shared `CreateEntryUseCase` seam, never a direct import of
/// `EntriesRepository`/`EntriesRemoteDataSource` from the chat feature.
/// Unlike `no_bloc_imports_bloc_test.dart` (bloc-to-bloc only) and
/// `domain_purity_test.dart` (domain/ folder only, same-feature layer
/// purity), neither of which can see a bloc reaching past a usecase into
/// another feature's repository or data source, this is scoped specifically
/// to `chat/presentation/bloc/` importing from `features/entries/` — not a
/// project-wide rule, since other features (e.g. `RecordsBloc` reading
/// `EntriesRepository` to list entries) legitimately import another
/// feature's repository for reasons FR-009 doesn't restrict.
void main() {
  test(
    "no lib/features/chat/presentation/bloc/ file imports an entries/ data/ or domain/repositories/ class",
    () {
      final chatBlocFiles = Directory(
              'lib/features/chat/presentation/bloc')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      expect(chatBlocFiles, isNotEmpty,
          reason: 'expected to find files under lib/features/chat/presentation/bloc/');

      final importPattern = RegExp(r'''^import\s+['"]([^'"]+)['"]''');
      final violations = <String>[];

      for (final file in chatBlocFiles) {
        for (final line in file.readAsLinesSync()) {
          final match = importPattern.firstMatch(line.trim());
          if (match == null) continue;
          final target = match.group(1)!;
          if (!target.contains('/features/entries/')) continue;

          final isData = target.contains('/data/');
          final isRepositoryInterface = target.contains('/domain/repositories/');
          if (isData || isRepositoryInterface) {
            violations.add(
                '${file.path}: imports entries\' ${isData ? 'data' : 'repository'} class ($target)');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
