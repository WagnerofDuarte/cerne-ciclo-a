import 'package:cerne/features/chat/domain/entities/proactive_insight.dart';
import 'package:test/test.dart';

void main() {
  group('ProactiveInsight', () {
    test('exposes content/anchorIndex as given', () {
      const insight = ProactiveInsight(content: 'Você tem falado bastante sobre X', anchorIndex: 4);
      expect(insight.content, 'Você tem falado bastante sobre X');
      expect(insight.anchorIndex, 4);
    });

    test('two instances with the same fields are equal', () {
      const a = ProactiveInsight(content: 'x', anchorIndex: 1);
      const b = ProactiveInsight(content: 'x', anchorIndex: 1);
      expect(a, b);
    });

    test('a different anchorIndex makes them unequal', () {
      const a = ProactiveInsight(content: 'x', anchorIndex: 1);
      const b = ProactiveInsight(content: 'x', anchorIndex: 2);
      expect(a, isNot(b));
    });

    test('a different content makes them unequal', () {
      const a = ProactiveInsight(content: 'x', anchorIndex: 1);
      const b = ProactiveInsight(content: 'y', anchorIndex: 1);
      expect(a, isNot(b));
    });
  });
}
