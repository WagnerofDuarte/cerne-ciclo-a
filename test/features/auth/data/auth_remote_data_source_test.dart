import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/data/auth_remote_data_source.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late AuthRemoteDataSource dataSource;

  const email = 'person@example.com';
  const password = 'correct-horse';

  final validData = {
    'session': {
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
      'expiresAt': 1234567890,
      'tokenType': 'bearer',
    },
    'user': {'id': 'user-1', 'email': email},
  };

  setUpAll(() {
    registerFallbackValue(AuthMode.anonKey);
  });

  setUp(() {
    apiClient = MockApiClient();
    dataSource = AuthRemoteDataSource(apiClient);
  });

  void stubCall(String function, Either<Failure, Map<String, dynamic>> result) {
    when(
      () => apiClient.call(
        function,
        method: any(named: 'method'),
        body: any(named: 'body'),
        pathSegments: any(named: 'pathSegments'),
        authMode: any(named: 'authMode'),
      ),
    ).thenAnswer((_) async => result);
  }

  for (final entry in {
    'auth-login': (String e, String p) => dataSource.login(email: e, password: p),
    'auth-signup': (String e, String p) => dataSource.signUp(email: e, password: p),
  }.entries) {
    final function = entry.key;
    final invoke = entry.value;

    group(function, () {
      test('calls apiClient.call($function, ...) with AuthMode.anonKey', () async {
        stubCall(function, Right(validData));

        await invoke(email, password);

        verify(
          () => apiClient.call(
            function,
            method: 'POST',
            body: {'email': email, 'password': password},
            authMode: AuthMode.anonKey,
          ),
        ).called(1);
      });

      test('parses a valid success body into Session', () async {
        stubCall(function, Right(validData));

        final result = await invoke(email, password);

        expect(result.isRight(), isTrue);
        final session = result.toNullable()!;
        expect(session.accessToken, 'access-token');
        expect(session.refreshToken, 'refresh-token');
        expect(session.expiresAt, 1234567890);
        expect(session.tokenType, 'bearer');
        expect(session.account.id, 'user-1');
        expect(session.account.email, email);
      });

      test('NetworkTimeoutFailure passes through unchanged', () async {
        const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
        stubCall(function, const Left(failure));

        final result = await invoke(email, password);

        expect(result, const Left<Failure, Session>(failure));
      });

      test('NetworkOfflineFailure passes through unchanged', () async {
        const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
        stubCall(function, const Left(failure));

        final result = await invoke(email, password);

        expect(result, const Left<Failure, Session>(failure));
      });

      test('ValidationFailure passes through unchanged (backend rejects submission)', () async {
        const failure = ValidationFailure(message: 'malformed request', requestId: 'r3');
        stubCall(function, const Left(failure));

        final result = await invoke(email, password);

        expect(result, const Left<Failure, Session>(failure));
      });

      test('a malformed success body (missing session/user) becomes ValidationFailure', () async {
        stubCall(function, const Right({'unexpected': true}));

        final result = await invoke(email, password);

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('a success body with wrong field types becomes ValidationFailure', () async {
        stubCall(function, Right({
          'session': {
            'accessToken': 123, // wrong type
            'refreshToken': 'refresh-token',
            'expiresAt': 1234567890,
            'tokenType': 'bearer',
          },
          'user': {'id': 'user-1', 'email': email},
        }));

        final result = await invoke(email, password);

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });
    });
  }
}
