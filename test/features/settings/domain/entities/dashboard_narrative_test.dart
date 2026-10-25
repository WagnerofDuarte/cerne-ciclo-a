import 'package:cerne/features/settings/domain/entities/dashboard_narrative.dart';
import 'package:test/test.dart';

void main() {
  test('two instances with the same fields are equal', () {
    final a = DashboardNarrative(text: 'hello', generatedAt: DateTime(2026, 1, 1));
    final b = DashboardNarrative(text: 'hello', generatedAt: DateTime(2026, 1, 1));

    expect(a, b);
  });

  test('a different text makes two instances unequal', () {
    final a = DashboardNarrative(text: 'hello', generatedAt: DateTime(2026, 1, 1));
    final b = DashboardNarrative(text: 'goodbye', generatedAt: DateTime(2026, 1, 1));

    expect(a, isNot(b));
  });
}
