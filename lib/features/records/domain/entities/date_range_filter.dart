/// "INTERVALO DE DATA" (prototype-extract.md §2.4). Pure `DateTime`
/// arithmetic — no `package:flutter` import, no I/O (Constitution
/// Principle V/RNF06).
enum DateRangeOption { allTime, thisWeek, thisMonth }

extension DateRangeBounds on DateRangeOption {
  /// Pure, total; `now` is a parameter (not `DateTime.now()` internally) so
  /// tests can fix "today" deterministically (research.md R2, mirroring
  /// `DateGrouper.group(..., {DateTime? now})`'s existing precedent).
  ({DateTime? from, DateTime? to}) boundsAt(DateTime now) => switch (this) {
    DateRangeOption.allTime => (from: null, to: null),
    DateRangeOption.thisWeek => (from: _mostRecentMonday(now), to: null),
    DateRangeOption.thisMonth => (from: DateTime(now.year, now.month), to: null),
  };

  DateTime _mostRecentMonday(DateTime now) {
    final daysSinceMonday = now.weekday - DateTime.monday;
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: daysSinceMonday));
  }
}
