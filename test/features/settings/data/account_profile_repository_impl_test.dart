import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/settings/data/account_profile_local_cache.dart';
import 'package:cerne/features/settings/data/account_profile_repository_impl.dart';
import 'package:cerne/features/settings/data/account_settings_remote_data_source.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAccountSettingsRemoteDataSource extends Mock
    implements AccountSettingsRemoteDataSource {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockAccountProfileLocalCache extends Mock implements AccountProfileLocalCache {}

Session _buildSession() => const Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresAt: 0,
  tokenType: 'bearer',
  account: Account(id: 'acc-1', email: 'test@example.com'),
);

void main() {
  late MockAccountSettingsRemoteDataSource remoteDataSource;
  late MockSessionRepository sessionRepository;
  late MockAccountProfileLocalCache localCache;
  late AccountProfileRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockAccountSettingsRemoteDataSource();
    sessionRepository = MockSessionRepository();
    localCache = MockAccountProfileLocalCache();
    when(() => localCache.write(any())).thenAnswer((_) async {});
    when(() => localCache.clear()).thenAnswer((_) async {});
    repository = AccountProfileRepositoryImpl(
      remoteDataSource,
      sessionRepository: sessionRepository,
      localCache: localCache,
    );
  });

  test('readCachedDisplayName returns the cached value', () async {
    when(() => localCache.read()).thenAnswer((_) async => 'Wagner Duarte');

    expect(await repository.readCachedDisplayName(), 'Wagner Duarte');
  });

  test('readCachedDisplayName returns null when never set', () async {
    when(() => localCache.read()).thenAnswer((_) async => null);

    expect(await repository.readCachedDisplayName(), isNull);
  });

  group('updateDisplayName', () {
    test('200 writes the response\'s own displayName to the cache and returns it', () async {
      when(() => remoteDataSource.updateDisplayName('Wagner'))
          .thenAnswer((_) async => const Right('Wagner Duarte'));

      final result = await repository.updateDisplayName('Wagner');

      expect(result, const Right<Failure, String>('Wagner Duarte'));
      verify(() => localCache.write('Wagner Duarte')).called(1);
    });

    test('Dio timeout -> Left(NetworkTimeoutFailure), cache unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: '');
      when(() => remoteDataSource.updateDisplayName(any()))
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.updateDisplayName('Wagner');

      expect(result, const Left<Failure, String>(failure));
      verifyNever(() => localCache.write(any()));
    });

    test('no connection -> Left(NetworkOfflineFailure), cache unchanged', () async {
      const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
      when(() => remoteDataSource.updateDisplayName(any()))
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.updateDisplayName('Wagner');

      expect(result, const Left<Failure, String>(failure));
      verifyNever(() => localCache.write(any()));
    });

    test('malformed response -> Left(ValidationFailure), cache unchanged', () async {
      const failure = ValidationFailure(message: 'malformed', requestId: '');
      when(() => remoteDataSource.updateDisplayName(any()))
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.updateDisplayName('Wagner');

      expect(result, const Left<Failure, String>(failure));
      verifyNever(() => localCache.write(any()));
    });

    test('AUTH_EXPIRED then successful silent refresh retries once', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: '');
      var callCount = 0;
      when(() => remoteDataSource.updateDisplayName(any())).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? const Left(authExpired) : const Right('Wagner Duarte');
      });
      when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildSession()));

      final result = await repository.updateDisplayName('Wagner');

      expect(result, const Right<Failure, String>('Wagner Duarte'));
      expect(callCount, 2);
      verify(() => localCache.write('Wagner Duarte')).called(1);
    });

    test('AUTH_EXPIRED then failed silent refresh -> Left(AuthExpiredFailure), cache unchanged', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: '');
      when(() => remoteDataSource.updateDisplayName(any()))
          .thenAnswer((_) async => const Left(authExpired));
      when(() => sessionRepository.refresh()).thenAnswer(
        (_) async => const Left(AuthExpiredFailure(message: 'nope', requestId: '')),
      );

      final result = await repository.updateDisplayName('Wagner');

      expect(result.isLeft(), isTrue);
      verifyNever(() => localCache.write(any()));
      verify(() => remoteDataSource.updateDisplayName(any())).called(1);
    });
  });

  test('clearCachedDisplayName delegates to the local cache clear()', () async {
    await repository.clearCachedDisplayName();

    verify(() => localCache.clear()).called(1);
  });
}
