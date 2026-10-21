import 'package:cerne/features/chat/domain/entities/chat_session_timestamp_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('ChatSessionTimestampFormatter.format', () {
    final now = DateTime(2026, 3, 11, 18, 0); // a Wednesday

    test('earlier today -> hour:minute only', () {
      final timestamp = DateTime(2026, 3, 11, 9, 5);
      expect(ChatSessionTimestampFormatter.format(timestamp, now: now), '09:05');
    });

    test('1 day ago (within the last 6 days) -> weekday abbreviation + middle dot + time', () {
      final timestamp = DateTime(2026, 3, 10, 23, 20); // Tuesday
      expect(ChatSessionTimestampFormatter.format(timestamp, now: now), 'ter · 23:20');
    });

    test('6 days ago (still within the week) -> weekday abbreviation + middle dot + time', () {
      final timestamp = DateTime(2026, 3, 5, 8, 0); // Thursday
      expect(ChatSessionTimestampFormatter.format(timestamp, now: now), 'qui · 08:00');
    });

    test('7 days ago (no longer "this week") -> day + abbreviated month', () {
      final timestamp = DateTime(2026, 3, 4, 8, 0);
      expect(ChatSessionTimestampFormatter.format(timestamp, now: now), '04 mar');
    });

    test('months ago -> day + abbreviated month', () {
      final timestamp = DateTime(2026, 1, 1, 10, 30);
      expect(ChatSessionTimestampFormatter.format(timestamp, now: now), '01 jan');
    });

    test(
      'a UTC timestamp converts to local before formatting — same result as '
      'passing the equivalent local DateTime directly, regardless of host '
      'timezone',
      () {
        final asLocal = DateTime(2026, 3, 10, 23, 20); // Tuesday
        final asUtc = asLocal.toUtc();

        expect(
          ChatSessionTimestampFormatter.format(asUtc, now: now),
          ChatSessionTimestampFormatter.format(asLocal, now: now),
        );
      },
    );

    test('a future timestamp (clock skew) falls back to hour:minute, never throws', () {
      final timestamp = DateTime(2026, 3, 12, 10, 0);
      expect(ChatSessionTimestampFormatter.format(timestamp, now: now), '10:00');
    });
  });
}
