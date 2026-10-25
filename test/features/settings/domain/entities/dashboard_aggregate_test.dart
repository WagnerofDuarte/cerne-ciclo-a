import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:test/test.dart';

const _zeroSources = DashboardSourceCounts(manual: 0, audio: 0, photo: 0, chat: 0);

AggregateBucket _bucket(DateTime date, int count) =>
    AggregateBucket(date: date, count: count, sources: _zeroSources);

void main() {
  group('DashboardAggregate.tenBars', () {
    test('empty input returns 10 zeros', () {
      const aggregate = DashboardAggregate(
        buckets: [],
        totals: DashboardTotals(count: 0, sources: _zeroSources),
      );

      expect(
        aggregate.tenBars(today: DateTime(2026, 1, 10)),
        List.filled(10, 0),
      );
    });

    test('a single bucket dated "today" puts all weight in bar index 9', () {
      final today = DateTime(2026, 1, 1);
      final aggregate = DashboardAggregate(
        buckets: [_bucket(today, 5)],
        totals: const DashboardTotals(count: 5, sources: _zeroSources),
      );

      final bars = aggregate.tenBars(today: today);

      expect(bars[9], 5);
      expect(bars.sublist(0, 9), List.filled(9, 0));
    });

    test('buckets spanning exactly 10 days land one bucket per bar, 1:1', () {
      final start = DateTime(2026, 1, 1);
      final today = start.add(const Duration(days: 9));
      final buckets = [
        for (var i = 0; i < 10; i++) _bucket(start.add(Duration(days: i)), 1),
      ];
      final aggregate = DashboardAggregate(
        buckets: buckets,
        totals: const DashboardTotals(count: 10, sources: _zeroSources),
      );

      final bars = aggregate.tenBars(today: today);

      expect(bars, List.filled(10, 1));
    });

    test('buckets spanning 100 days fold several buckets into the same bar', () {
      final start = DateTime(2026, 1, 1);
      final today = start.add(const Duration(days: 99));
      final buckets = [
        for (var i = 0; i < 100; i++) _bucket(start.add(Duration(days: i)), 1),
      ];
      final aggregate = DashboardAggregate(
        buckets: buckets,
        totals: const DashboardTotals(count: 100, sources: _zeroSources),
      );

      final bars = aggregate.tenBars(today: today);

      expect(bars, List.filled(10, 10));
    });

    test('a bucket dated after today clamps to bar 9 rather than throwing', () {
      final start = DateTime(2026, 1, 1);
      final today = DateTime(2026, 1, 5);
      final afterToday = DateTime(2026, 1, 20);
      final aggregate = DashboardAggregate(
        buckets: [_bucket(start, 1), _bucket(afterToday, 1)],
        totals: const DashboardTotals(count: 2, sources: _zeroSources),
      );

      final bars = aggregate.tenBars(today: today);

      expect(bars.reduce((a, b) => a + b), 2);
      expect(bars[9], greaterThanOrEqualTo(1));
    });
  });
}
