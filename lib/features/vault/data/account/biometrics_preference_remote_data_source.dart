import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// `PATCH account-settings-update` with only `biometricEnabled` — a valid
/// partial update since the endpoint's schema treats all three fields as
/// independently optional (contracts/biometrics-preference-repository.md).
class BiometricsPreferenceRemoteDataSource {
  const BiometricsPreferenceRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, Map<String, dynamic>>> update({
    required bool biometricEnabled,
  }) =>
      _apiClient.call(
        'account-settings-update',
        method: 'PATCH',
        body: {'biometricEnabled': biometricEnabled},
      );
}
