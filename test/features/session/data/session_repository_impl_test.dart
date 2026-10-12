import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/data/session_remote_data_source.dart';
import 'package:cerne/features/session/data/session_repository_impl.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockSessionRemoteDataSource extends Mock implements SessionRemoteDataSource {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

void main() {
  late MockSessionRemoteDataSource remoteDataSource;
  late MockSecureTokenStorage tokenStorage;
  late SessionRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockSessionRemoteDataSource();
    tokenStorage = MockSecureTokenStorage();
    repository = SessionRepositoryImpl(
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

  group('checkSession', () {
    test('Right(data) is assembled into a Session using stored tokens', () async {
      when(() => remoteDataSource.checkSession()).thenAnswer(
        (_) async => const Right({
          'user': {'id': 'user-1', 'email': 'person@example.com'},
          'expiresAt': 1234567890,
          'serverRevision': 0,
        }),
      );
      when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => 'stored-access');
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => 'stored-refresh');
      when(() => tokenStorage.readTokenType()).thenAnswer((_) async => 'bearer');

      final result = await repository.checkSession();

      expect(result.isRight(), isTrue);
      final session = result.toNullable()!;
      expect(session.accessToken, 'stored-access');
      expect(session.refreshToken, 'stored-refresh');
      expect(session.tokenType, 'bearer');
      expect(session.expiresAt, 1234567890);
      expect(session.account.id, 'user-1');
    });

    test('Left(Failure) passes through unchanged', () async {
      const failure = AuthExpiredFailure(message: 'expired', requestId: 'r1');
      when(() => remoteDataSource.checkSession())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.checkSession();

      expect(result, const Left<Failure, dynamic>(failure));
    });

    test('a malformed success body becomes ValidationFailure, never throws', () async {
      when(() => remoteDataSource.checkSession())
          .thenAnswer((_) async => const Right({'unexpected': true}));

      final result = await repository.checkSession();

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });
  });

  group('refresh', () {
    test('Right persists the new tokens, then re-checks to recover the account', () async {
      when(() => tokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'old-refresh-token');
      when(() => remoteDataSource.refresh(refreshToken: 'old-refresh-token')).thenAnswer(
        (_) async => const Right({
          'session': {
            'accessToken': 'new-access',
            'refreshToken': 'new-refresh',
            'expiresIn': 3600,
            'expiresAt': 1234599999,
            'tokenType': 'bearer',
          },
        }),
      );
      when(() => remoteDataSource.checkSession()).thenAnswer(
        (_) async => const Right({
          'user': {'id': 'user-1', 'email': 'person@example.com'},
          'expiresAt': 1234599999,
          'serverRevision': 0,
        }),
      );
      // Simulates the just-persisted tokens being read back by checkSession.
      when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => 'new-access');
      when(() => tokenStorage.readTokenType()).thenAnswer((_) async => 'bearer');

      final result = await repository.refresh();

      expect(result.isRight(), isTrue);
      final session = result.toNullable()!;
      expect(session.accessToken, 'new-access');
      verify(
        () => tokenStorage.writeSession(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          expiresAt: 1234599999,
          tokenType: 'bearer',
        ),
      ).called(1);
    });

    test('Left(Failure) passes through unchanged', () async {
      when(() => tokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'old-refresh-token');
      const failure = AuthInvalidFailure(message: 'invalid refresh token', requestId: 'r2');
      when(() => remoteDataSource.refresh(refreshToken: 'old-refresh-token'))
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.refresh();

      expect(result, const Left<Failure, dynamic>(failure));
    });

    test('a malformed success body becomes ValidationFailure, never throws', () async {
      when(() => tokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'old-refresh-token');
      when(() => remoteDataSource.refresh(refreshToken: 'old-refresh-token'))
          .thenAnswer((_) async => const Right({'unexpected': true}));

      final result = await repository.refresh();

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });
  });

  group('persist / clear', () {
    test('persist delegates to SecureTokenStorage', () async {
      final session = Session(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: 1234567890,
        tokenType: 'bearer',
        account: const Account(id: 'user-1', email: 'person@example.com'),
      );

      await repository.persist(session);

      verify(
        () => tokenStorage.writeSession(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          expiresAt: session.expiresAt,
          tokenType: session.tokenType,
        ),
      ).called(1);
    });

    test('clear delegates to SecureTokenStorage.delete', () async {
      when(() => tokenStorage.delete()).thenAnswer((_) async {});

      await repository.clear();

      verify(() => tokenStorage.delete()).called(1);
    });
  });

  group('hasStoredSession', () {
    test('true iff a refreshToken is stored', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => 'a-token');
      expect(await repository.hasStoredSession(), isTrue);
    });

    test('false when no refreshToken is stored', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => null);
      expect(await repository.hasStoredSession(), isFalse);
    });
  });
}
