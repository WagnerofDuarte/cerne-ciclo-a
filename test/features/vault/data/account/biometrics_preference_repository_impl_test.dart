import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/vault/data/account/biometrics_preference_remote_data_source.dart';
import 'package:cerne/features/vault/data/account/biometrics_preference_repository_impl.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late BiometricsPreferenceRemoteDataSource remoteDataSource;
  late BiometricsPreferenceRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(AuthMode.userSession);
  });

  setUp(() {
    apiClient = MockApiClient();
    remoteDataSource = BiometricsPreferenceRemoteDataSource(apiClient);
    repository = BiometricsPreferenceRepositoryImpl(remoteDataSource);
  });

  void stubCall(Either<Failure, Map<String, dynamic>> result) {
    when(
      () => apiClient.call(
        'account-settings-update',
        method: any(named: 'method'),
        body: any(named: 'body'),
        pathSegments: any(named: 'pathSegments'),
        authMode: any(named: 'authMode'),
      ),
    ).thenAnswer((_) async => result);
  }

  test('Right({...}) -> Right(unit), discarding the decoded body', () async {
    stubCall(Right({'biometricEnabled': true}));

    final result = await repository.save(true);

    expect(result, const Right<Failure, void>(null));
    verify(
      () => apiClient.call(
        'account-settings-update',
        method: 'PATCH',
        body: {'biometricEnabled': true},
        pathSegments: any(named: 'pathSegments'),
        authMode: any(named: 'authMode'),
      ),
    ).called(1);
  });

  test('Left(NetworkTimeoutFailure) passes through unchanged', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    stubCall(const Left(failure));

    final result = await repository.save(true);

    expect(result, const Left<Failure, void>(failure));
  });

  test('Left(NetworkOfflineFailure) passes through unchanged', () async {
    const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
    stubCall(const Left(failure));

    final result = await repository.save(false);

    expect(result, const Left<Failure, void>(failure));
  });

  test('Left(ValidationFailure) passes through unchanged (malformed response)', () async {
    const failure = ValidationFailure(message: 'malformed response', requestId: 'r3');
    stubCall(const Left(failure));

    final result = await repository.save(true);

    expect(result, const Left<Failure, void>(failure));
  });
}
