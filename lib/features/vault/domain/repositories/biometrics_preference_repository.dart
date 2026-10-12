import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// Domain-layer interface for the one network call this unit makes —
/// deliberately narrow, a single method for a single field, rather than a
/// general-purpose account-settings repository (contracts/biometrics-preference-repository.md).
abstract class BiometricsPreferenceRepository {
  Future<Either<Failure, void>> save(bool enabled);
}
