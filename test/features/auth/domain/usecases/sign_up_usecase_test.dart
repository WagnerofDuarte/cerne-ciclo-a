import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late SignUpUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = SignUpUseCase(repository);
  });

  const email = 'new-person@example.com';
  const password = 'a-new-password';

  final session = Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: 1234567890,
    tokenType: 'bearer',
    account: const Account(id: 'user-2', email: email),
  );

  test('delegates to repository.signUp and returns Right(Session) unchanged', () async {
    when(() => repository.signUp(email: email, password: password))
        .thenAnswer((_) async => Right(session));

    final result = await useCase(email: email, password: password);

    expect(result, Right<Failure, Session>(session));
    verify(() => repository.signUp(email: email, password: password)).called(1);
  });

  test('returns Left(AuthInvalidFailure) unchanged for an already-registered email', () async {
    const failure = AuthInvalidFailure(message: 'already registered', requestId: 'r1');
    when(() => repository.signUp(email: email, password: password))
        .thenAnswer((_) async => const Left(failure));

    final result = await useCase(email: email, password: password);

    expect(result, const Left<Failure, Session>(failure));
  });
}
