import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/vault/data/account/biometrics_preference_remote_data_source.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:fpdart/fpdart.dart';

/// `save()` discards the decoded body — there is no reason to decode and
/// carry the full updated-account payload the endpoint returns
/// (contracts/biometrics-preference-repository.md).
class BiometricsPreferenceRepositoryImpl
    implements BiometricsPreferenceRepository {
  const BiometricsPreferenceRepositoryImpl(this._remote);

  final BiometricsPreferenceRemoteDataSource _remote;

  @override
  Future<Either<Failure, void>> save(bool enabled) async =>
      (await _remote.update(biometricEnabled: enabled)).map((_) {});
}
