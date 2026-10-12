import 'package:cerne/features/vault/domain/usecases/evaluate_background_resume_usecase.dart';
import 'package:test/test.dart';

void main() {
  const useCase = EvaluateBackgroundResumeUseCase();
  final backgroundedAt = DateTime(2026, 1, 1, 12);

  test('backgroundedAt: null -> false', () {
    final result = useCase(
      backgroundedAt: null,
      resumedAt: DateTime(2026, 1, 1, 12, 10),
    );

    expect(result, isFalse);
  });

  test('gap of 4:59 -> false', () {
    final result = useCase(
      backgroundedAt: backgroundedAt,
      resumedAt: backgroundedAt.add(const Duration(minutes: 4, seconds: 59)),
    );

    expect(result, isFalse);
  });

  test('gap of exactly 5:00 -> true', () {
    final result = useCase(
      backgroundedAt: backgroundedAt,
      resumedAt: backgroundedAt.add(const Duration(minutes: 5)),
    );

    expect(result, isTrue);
  });

  test('gap over 5:00 -> true', () {
    final result = useCase(
      backgroundedAt: backgroundedAt,
      resumedAt: backgroundedAt.add(const Duration(minutes: 6)),
    );

    expect(result, isTrue);
  });
}
