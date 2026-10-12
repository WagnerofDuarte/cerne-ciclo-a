import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/data/session_remote_data_source.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late SessionRemoteDataSource dataSource;

  setUpAll(() {
    registerFallbackValue(AuthMode.anonKey);
  });

  setUp(() {
    apiClient = MockApiClient();
    dataSource = SessionRemoteDataSource(apiClient);
  });

  group('checkSession', () {
    test('calls apiClient.call(auth-session, GET, AuthMode.userSession)', () async {
      when(
        () => apiClient.call(
          'auth-session',
          method: any(named: 'method'),
          body: any(named: 'body'),
          pathSegments: any(named: 'pathSegments'),
          authMode: any(named: 'authMode'),
        ),
      ).thenAnswer((_) async => const Right({'user': {}, 'expiresAt': 0}));

      await dataSource.checkSession();

      verify(
        () => apiClient.call(
          'auth-session',
          method: 'GET',
          authMode: AuthMode.userSession,
        ),
      ).called(1);
    });

    test('passes a raw success body through unchanged (parsed by the repository)', () async {
      const data = {
        'user': {'id': 'user-1', 'email': 'person@example.com'},
        'expiresAt': 1234567890,
        'serverRevision': 0,
      };
      when(
        () => apiClient.call(
          'auth-session',
          method: any(named: 'method'),
          body: any(named: 'body'),
          pathSegments: any(named: 'pathSegments'),
          authMode: any(named: 'authMode'),
        ),
      ).thenAnswer((_) async => const Right(data));

      final result = await dataSource.checkSession();

      expect(result, const Right<Failure, Map<String, dynamic>>(data));
    });
  });

  group('refresh', () {
    const refreshToken = 'stored-refresh-token';

    void stubRefresh(Either<Failure, Map<String, dynamic>> result) {
      when(
        () => apiClient.call(
          'auth-refresh',
          method: any(named: 'method'),
          body: any(named: 'body'),
          pathSegments: any(named: 'pathSegments'),
          authMode: any(named: 'authMode'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('calls apiClient.call(auth-refresh, POST, body, AuthMode.anonKey)', () async {
      stubRefresh(const Right({'session': {}}));

      await dataSource.refresh(refreshToken: refreshToken);

      verify(
        () => apiClient.call(
          'auth-refresh',
          method: 'POST',
          body: {'refreshToken': refreshToken},
          authMode: AuthMode.anonKey,
        ),
      ).called(1);
    });

    test('NetworkTimeoutFailure passes through unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
      stubRefresh(const Left(failure));

      final result = await dataSource.refresh(refreshToken: refreshToken);

      expect(result, const Left<Failure, Map<String, dynamic>>(failure));
    });

    test('NetworkOfflineFailure passes through unchanged', () async {
      const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
      stubRefresh(const Left(failure));

      final result = await dataSource.refresh(refreshToken: refreshToken);

      expect(result, const Left<Failure, Map<String, dynamic>>(failure));
    });

    test('a malformed success body still passes through unchanged (parsed by the repository)', () async {
      const data = {'unexpected': true};
      stubRefresh(const Right(data));

      final result = await dataSource.refresh(refreshToken: refreshToken);

      expect(result, const Right<Failure, Map<String, dynamic>>(data));
    });
  });
}
