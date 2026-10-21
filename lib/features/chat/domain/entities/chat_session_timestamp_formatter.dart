/// Formats a session's side-menu timestamp per the prototype: today shows
/// just the time, the last 6 days show the weekday abbreviation + middle
/// dot + time ("seg · 09:10"), and anything older shows the day + abbreviated
/// month. Pure, total; no `package:flutter` import, no I/O (Principle V).
class ChatSessionTimestampFormatter {
  const ChatSessionTimestampFormatter._();

  static const _weekdayAbbreviations = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  static const _monthAbbreviations = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  /// [timestamp] is converted to local time before formatting; [now] is
  /// taken as a parameter (never read internally) so callers — and tests —
  /// control "today" explicitly.
  static String format(DateTime timestamp, {required DateTime now}) {
    final local = timestamp.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final daysAgo = today.difference(day).inDays;

    if (daysAgo <= 0) return time;
    if (daysAgo < 7) return '${_weekdayAbbreviations[local.weekday - 1]} · $time';

    final dayLabel = local.day.toString().padLeft(2, '0');
    return '$dayLabel ${_monthAbbreviations[local.month - 1]}';
  }
}
