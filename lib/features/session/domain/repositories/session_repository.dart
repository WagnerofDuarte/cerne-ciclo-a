import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';

/// Domain-layer interface owning the session lifecycle: launch-time check,
/// silent refresh, and reading/clearing the stored session.
/// `SessionBloc` depends on this and on nothing in `session/data/` or
/// `auth/data/` directly (RNF06, contracts/session-repository.md).
abstract class SessionRepository {
  /// GET auth-session, using the stored accessToken.
  Future<Either<Failure, Session>> checkSession();

  /// POST auth-refresh, using the stored refreshToken. On `Right`, calls
  /// [persist] internally before returning.
  Future<Either<Failure, Session>> refresh();

  /// Write-through to secure storage.
  Future<void> persist(Session session);

  /// Logout / failed-refresh cleanup.
  Future<void> clear();

  /// True iff a refreshToken is present on device.
  Future<bool> hasStoredSession();
}
