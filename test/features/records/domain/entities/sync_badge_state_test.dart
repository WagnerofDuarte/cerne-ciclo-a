import 'package:cerne/features/records/domain/entities/sync_badge_state.dart';
import 'package:test/test.dart';

void main() {
  group('SyncBadge.derive', () {
    test('null -> synchronized', () {
      expect(SyncBadge.derive(null), SyncBadgeState.synchronized);
    });

    test('LocalWriteOutcome.pending -> synchronizing', () {
      expect(SyncBadge.derive(LocalWriteOutcome.pending), SyncBadgeState.synchronizing);
    });

    test('LocalWriteOutcome.failed -> error', () {
      expect(SyncBadge.derive(LocalWriteOutcome.failed), SyncBadgeState.error);
    });
  });
}
