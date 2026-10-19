import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:test/test.dart';

void main() {
  // A fixed, non-Monday "now" for determinism.
  final now = DateTime(2026, 10, 15, 14, 30); // a Thursday

  group('DateRangeOption.boundsAt', () {
    test('allTime -> both bounds null', () {
      final bounds = DateRangeOption.allTime.boundsAt(now);

      expect(bounds.from, isNull);
      expect(bounds.to, isNull);
    });

    test('thisWeek -> from is the most recent Monday at 00:00:00', () {
      final bounds = DateRangeOption.thisWeek.boundsAt(now);

      expect(bounds.from, DateTime(2026, 10, 12));
      expect(bounds.to, isNull);
    });

    test('thisWeek on a Monday -> from is that same Monday at 00:00:00', () {
      final monday = DateTime(2026, 10, 12, 9);
      final bounds = DateRangeOption.thisWeek.boundsAt(monday);

      expect(bounds.from, DateTime(2026, 10, 12));
    });

    test('thisMonth -> from is the 1st of now\'s month at 00:00:00', () {
      final bounds = DateRangeOption.thisMonth.boundsAt(now);

      expect(bounds.from, DateTime(2026, 10, 1));
      expect(bounds.to, isNull);
    });
  });
}
