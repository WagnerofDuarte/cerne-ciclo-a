import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/session/domain/usecases/check_session_usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  late MockSessionRepository repository;
  late CheckSessionUseCase useCase;

  final session = Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: 1234567890,
    tokenType: 'bearer',
    account: const Account(id: 'user-1', email: 'person@example.com'),
  );

  setUp(() {
    repository = MockSessionRepository();
    useCase = CheckSessionUseCase(repository);
  });

  test('no stored session -> unauthenticated, no checkSession() call made', () async {
    when(() => repository.hasStoredSession()).thenAnswer((_) async => false);

    final status = await useCase();

    expect(status, isA<SessionStatusUnauthenticated>());
    verifyNever(() => repository.checkSession());
  });

  test('checkSession() Right -> authenticated', () async {
    when(() => repository.hasStoredSession()).thenAnswer((_) async => true);
    when(() => repository.checkSession()).thenAnswer((_) async => Right(session));

    final status = await useCase();

    expect(status, isA<SessionStatusAuthenticated>());
    expect((status as SessionStatusAuthenticated).session, session);
  });

  test('checkSession() Left(AuthExpiredFailure) -> refresh() Right -> authenticated', () async {
    when(() => repository.hasStoredSession()).thenAnswer((_) async => true);
    when(() => repository.checkSession()).thenAnswer(
      (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
    );
    when(() => repository.refresh()).thenAnswer((_) async => Right(session));

    final status = await useCase();

    expect(status, isA<SessionStatusAuthenticated>());
    verifyNever(() => repository.clear());
  });

  test('checkSession() Left(AuthExpiredFailure) -> refresh() Left -> clear() then unauthenticated', () async {
    when(() => repository.hasStoredSession()).thenAnswer((_) async => true);
    when(() => repository.checkSession()).thenAnswer(
      (_) async => const Left(AuthExpiredFailure(message: 'expired', requestId: 'r1')),
    );
    when(() => repository.refresh()).thenAnswer(
      (_) async => const Left(AuthInvalidFailure(message: 'invalid refresh token', requestId: 'r2')),
    );
    when(() => repository.clear()).thenAnswer((_) async {});

    final status = await useCase();

    expect(status, isA<SessionStatusUnauthenticated>());
    verify(() => repository.clear()).called(1);
  });

  test('checkSession() Left(AuthInvalidFailure) -> clear() then unauthenticated, no refresh attempted', () async {
    when(() => repository.hasStoredSession()).thenAnswer((_) async => true);
    when(() => repository.checkSession()).thenAnswer(
      (_) async => const Left(AuthInvalidFailure(message: 'token inválido ou expirado', requestId: 'r5')),
    );
    when(() => repository.clear()).thenAnswer((_) async {});

    final status = await useCase();

    expect(status, isA<SessionStatusUnauthenticated>());
    verify(() => repository.clear()).called(1);
    verifyNever(() => repository.refresh());
  });

  for (final failure in const [
    NetworkTimeoutFailure(message: 'timed out', requestId: 'r3'),
    NetworkOfflineFailure(message: 'no connection', requestId: 'r4'),
  ]) {
    test('checkSession() Left(${failure.code}) -> network-error status, not a route change', () async {
      when(() => repository.hasStoredSession()).thenAnswer((_) async => true);
      when(() => repository.checkSession()).thenAnswer((_) async => Left(failure));

      final status = await useCase();

      expect(status, isA<SessionStatusNetworkError>());
      expect((status as SessionStatusNetworkError).failure, failure);
      verifyNever(() => repository.refresh());
    });
  }
}
