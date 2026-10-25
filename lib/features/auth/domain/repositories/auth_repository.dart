import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';

/// Domain-layer interface; `AuthBloc` depends on this and on nothing in
/// `auth/data/` directly (RNF06, contracts/auth-repository.md).
abstract class AuthRepository {
  Future<Either<Failure, Session>> signUp({
    required String email,
    required String password,
  });

  Future<Either<Failure, Session>> login({
    required String email,
    required String password,
  });

  /// `POST /auth/logout` (`auth-logout`). Does **not** clear
  /// `SecureTokenStorage`/`SessionRepository` itself — that stays
  /// `SettingsBloc`'s job (contracts/account-session-actions.md).
  Future<Either<Failure, Unit>> logout();
}
