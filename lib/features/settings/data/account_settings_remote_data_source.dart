import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

const _malformedFailure = ValidationFailure(
  message: 'Malformed account settings response',
  requestId: '',
);

/// `PATCH account-settings-update` with only `displayName` — never
/// `persona` (FR-015), the same partial-update shape
/// `BiometricsPreferenceRemoteDataSource` already establishes for its own
/// single field.
class AccountSettingsRemoteDataSource {
  const AccountSettingsRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, String>> updateDisplayName(String name) async {
    final result = await _apiClient.call(
      'account-settings-update',
      method: 'PATCH',
      body: {'displayName': name},
    );
    return result.flatMap(_parseDisplayName);
  }

  Either<Failure, String> _parseDisplayName(Map<String, dynamic> data) {
    try {
      return Right(data['displayName'] as String);
    } on TypeError {
      return const Left(_malformedFailure);
    }
  }
}
