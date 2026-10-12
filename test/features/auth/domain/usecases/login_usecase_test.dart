import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/usecases/login_usecase.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late LoginUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = LoginUseCase(repository);
  });

  const email = 'person@example.com';
  const password = 'correct-horse';

  final session = Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: 1234567890,
    tokenType: 'bearer',
    account: const Account(id: 'user-1', email: email),
  );

  const allFailures = <Failure>[
    AuthExpiredFailure(message: 'expired', requestId: 'r1'),
    AuthInvalidFailure(message: 'invalid', requestId: 'r2'),
    NetworkTimeoutFailure(message: 'timeout', requestId: 'r3'),
    NetworkOfflineFailure(message: 'offline', requestId: 'r4'),
    ValidationFailure(message: 'validation', requestId: 'r5'),
    PiiCheckFailedFailure(message: 'pii', requestId: 'r6'),
    EmbeddingFailedFailure(message: 'embedding', requestId: 'r7'),
    AiGenerationTimeoutFailure(message: 'ai-timeout', requestId: 'r8'),
    NotFoundFailure(message: 'not-found', requestId: 'r9'),
    RateLimitedFailure(message: 'rate-limited', requestId: 'r10'),
    ExportEmptyPeriodFailure(message: 'empty-period', requestId: 'r11'),
    PayloadTooLargeFailure(message: 'too-large', requestId: 'r12'),
    OcrNoTextFailure(message: 'no-text', requestId: 'r13'),
  ];

  test('delegates to repository.login and returns Right(Session) unchanged', () async {
    when(() => repository.login(email: email, password: password))
        .thenAnswer((_) async => Right(session));

    final result = await useCase(email: email, password: password);

    expect(result, Right<Failure, Session>(session));
    verify(() => repository.login(email: email, password: password)).called(1);
  });

  for (final failure in allFailures) {
    test('returns Left(${failure.code}) unchanged', () async {
      when(() => repository.login(email: email, password: password))
          .thenAnswer((_) async => Left(failure));

      final result = await useCase(email: email, password: password);

      expect(result, Left<Failure, Session>(failure));
    });
  }
}
