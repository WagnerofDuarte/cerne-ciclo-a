import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';

/// Thin pass-through wrapping [AuthRepository.signUp] (contracts/auth-repository.md
/// "Use cases wrapping this repository").
class SignUpUseCase {
  const SignUpUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<Failure, Session>> call({
    required String email,
    required String password,
  }) {
    return _repository.signUp(email: email, password: password);
  }
}
