import 'package:cerne/features/chat/domain/entities/insight_trigger.dart';
import 'package:test/test.dart';

void main() {
  group('InsightTriggerKeyBuilder.forMessageCount', () {
    test('formats as "message_count:<count>"', () {
      expect(InsightTriggerKeyBuilder.forMessageCount(5), 'message_count:5');
      expect(InsightTriggerKeyBuilder.forMessageCount(10), 'message_count:10');
    });
  });

  group('InsightTriggerKeyBuilder.forInactivity', () {
    test('formats as "inactivity:<ISO-8601 UTC>"', () {
      final firedAt = DateTime.utc(2026, 1, 1, 12, 30);
      expect(
        InsightTriggerKeyBuilder.forInactivity(firedAt),
        'inactivity:2026-01-01T12:30:00.000Z',
      );
    });

    test('converts a local DateTime to UTC before formatting', () {
      final local = DateTime(2026, 1, 1, 9).toLocal();
      final utc = local.toUtc();
      expect(
        InsightTriggerKeyBuilder.forInactivity(local),
        'inactivity:${utc.toIso8601String()}',
      );
    });
  });

  group('InsightTrigger equality', () {
    test('two instances with the same type/triggerKey are equal', () {
      const a = InsightTrigger(
        type: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );
      const b = InsightTrigger(
        type: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );
      expect(a, b);
    });

    test('a different triggerKey makes them unequal', () {
      const a = InsightTrigger(
        type: InsightTriggerType.messageCount,
        triggerKey: 'message_count:5',
      );
      const b = InsightTrigger(
        type: InsightTriggerType.messageCount,
        triggerKey: 'message_count:10',
      );
      expect(a, isNot(b));
    });

    test('a different type makes them unequal even with the same triggerKey', () {
      const a = InsightTrigger(
        type: InsightTriggerType.messageCount,
        triggerKey: 'same',
      );
      const b = InsightTrigger(
        type: InsightTriggerType.inactivity,
        triggerKey: 'same',
      );
      expect(a, isNot(b));
    });
  });
}
