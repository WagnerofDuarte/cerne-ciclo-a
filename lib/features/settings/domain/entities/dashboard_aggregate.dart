import 'package:equatable/equatable.dart';

/// Per-source entry counts, carried for completeness — this unit's chart
/// only ever renders [AggregateBucket.count]/[DashboardTotals.count] (no
/// per-source stacking/legend in scope, data-model.md).
class DashboardSourceCounts extends Equatable {
  const DashboardSourceCounts({
    required this.manual,
    required this.audio,
    required this.photo,
    required this.chat,
  });

  final int manual;
  final int audio;
  final int photo;
  final int chat;

  @override
  List<Object?> get props => [manual, audio, photo, chat];
}

/// One backend-reported day bucket. [date] is parsed from the backend's
/// `YYYY-MM-DD` string, date-only (no time component kept).
class AggregateBucket extends Equatable {
  const AggregateBucket({
    required this.date,
    required this.count,
    required this.sources,
  });

  final DateTime date;
  final int count;
  final DashboardSourceCounts sources;

  @override
  List<Object?> get props => [date, count, sources];
}

/// The account-wide total for the requested period.
class DashboardTotals extends Equatable {
  const DashboardTotals({required this.count, required this.sources});

  final int count;
  final DashboardSourceCounts sources;

  @override
  List<Object?> get props => [count, sources];
}

/// `GET /dashboard/aggregate`'s decoded response (data-model.md,
/// contracts/dashboard-repository.md).
class DashboardAggregate extends Equatable {
  const DashboardAggregate({required this.buckets, required this.totals});

  final List<AggregateBucket> buckets;
  final DashboardTotals totals;

  /// research.md R2's bucketing algorithm: divides the account's full date
  /// range — date of the first entry through [today] — into ten
  /// roughly-equal time slices and sums each bucket's count into the slice
  /// it falls within. Pure and total: no `DateTime.now()` call inside, so
  /// tests can pin [today] for determinism.
  List<int> tenBars({DateTime? today}) {
    final now = today ?? DateTime.now();
    if (buckets.isEmpty) return List.filled(10, 0);

    final start = buckets
        .map((b) => b.date)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final totalDaySpan = now.difference(start).inDays;
    final bars = List.filled(10, 0);

    if (totalDaySpan == 0) {
      // Every entry happened "today" relative to the account's own first
      // entry — a single-day range cannot be divided into 10 meaningful
      // slices, so the whole total lands in the last bar rather than every
      // bar collapsing onto index 0.
      bars[9] = buckets.fold(0, (sum, b) => sum + b.count);
      return bars;
    }

    for (final bucket in buckets) {
      final daysSinceStart = bucket.date.difference(start).inDays;
      final index = (daysSinceStart * 10) ~/ (totalDaySpan + 1);
      bars[index.clamp(0, 9)] += bucket.count;
    }
    return bars;
  }

  @override
  List<Object?> get props => [buckets, totals];
}
