import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/data/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/auth_repository_impl.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

void main() {
  late MockAuthRemoteDataSource remoteDataSource;
  late MockSecureTokenStorage tokenStorage;
  late AuthRepositoryImpl repository;

  const email = 'person@example.com';
  const password = 'correct-horse';

  final session = Session(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    expiresAt: 1234567890,
    tokenType: 'bearer',
    account: const Account(id: 'user-1', email: email),
  );

  setUp(() {
    remoteDataSource = MockAuthRemoteDataSource();
    tokenStorage = MockSecureTokenStorage();
    repository = AuthRepositoryImpl(
      remoteDataSource: remoteDataSource,
      tokenStorage: tokenStorage,
    );
    when(
      () => tokenStorage.writeSession(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
        expiresAt: any(named: 'expiresAt'),
        tokenType: any(named: 'tokenType'),
      ),
    ).thenAnswer((_) async {});
  });

  group('login', () {
    test('Right(session) is persisted before returning', () async {
      when(() => remoteDataSource.login(email: email, password: password))
          .thenAnswer((_) async => Right(session));

      final result = await repository.login(email: email, password: password);

      expect(result, Right<Failure, Session>(session));
      verify(
        () => tokenStorage.writeSession(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          expiresAt: session.expiresAt,
          tokenType: session.tokenType,
        ),
      ).called(1);
    });

    test('Left(Failure) passes through unchanged with no storage write', () async {
      const failure = AuthInvalidFailure(message: 'wrong credentials', requestId: 'r1');
      when(() => remoteDataSource.login(email: email, password: password))
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.login(email: email, password: password);

      expect(result, const Left<Failure, Session>(failure));
      verifyNever(
        () => tokenStorage.writeSession(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          expiresAt: any(named: 'expiresAt'),
          tokenType: any(named: 'tokenType'),
        ),
      );
    });
  });

  group('signUp', () {
    test('success persists Session the same way as login', () async {
      when(() => remoteDataSource.signUp(email: email, password: password))
          .thenAnswer((_) async => Right(session));

      final result = await repository.signUp(email: email, password: password);

      expect(result, Right<Failure, Session>(session));
      verify(
        () => tokenStorage.writeSession(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          expiresAt: session.expiresAt,
          tokenType: session.tokenType,
        ),
      ).called(1);
    });

    test('Left(AuthInvalidFailure) for an already-registered email passes through unchanged', () async {
      const failure = AuthInvalidFailure(message: 'already registered', requestId: 'r2');
      when(() => remoteDataSource.signUp(email: email, password: password))
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.signUp(email: email, password: password);

      expect(result, const Left<Failure, Session>(failure));
      verifyNever(
        () => tokenStorage.writeSession(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          expiresAt: any(named: 'expiresAt'),
          tokenType: any(named: 'tokenType'),
        ),
      );
    });
  });
}
