import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';

/// Thin pass-through wrapping [AuthRepository.login] (contracts/auth-repository.md
/// "Use cases wrapping this repository").
class LoginUseCase {
  const LoginUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<Failure, Session>> call({
    required String email,
    required String password,
  }) {
    return _repository.login(email: email, password: password);
  }
}
