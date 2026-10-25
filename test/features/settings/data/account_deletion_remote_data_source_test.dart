import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/settings/data/account_deletion_remote_data_source.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late AccountDeletionRemoteDataSource dataSource;

  setUp(() {
    apiClient = MockApiClient();
    dataSource = AccountDeletionRemoteDataSource(apiClient);
  });

  test('always sends DELETE /account with body {"confirmation": "DELETE"}', () async {
    when(
      () => apiClient.call(
        any(),
        method: any(named: 'method'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => const Right({'ok': true}));

    await dataSource.deleteAccount();

    verify(
      () => apiClient.call(
        'account-delete',
        method: 'DELETE',
        body: const {'confirmation': 'DELETE'},
      ),
    ).called(1);
  });
}
