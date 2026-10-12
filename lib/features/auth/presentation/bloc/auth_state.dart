import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:equatable/equatable.dart';

/// Which mode the single login/sign-up screen is toggled to (FR-008).
/// Presentation-only state — reset to [AuthFormMode.login] each time the
/// screen is (re-)entered, since `AuthBloc` is registered as a `get_it`
/// factory and a fresh instance is created per visit (data-model.md).
enum AuthFormMode { login, signUp }

enum AuthStatus { initial, loading, authenticated, failure }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initial,
    this.formMode = AuthFormMode.login,
    this.session,
    this.failure,
  });

  final AuthStatus status;
  final AuthFormMode formMode;
  final Session? session;
  final Failure? failure;

  @override
  List<Object?> get props => [status, formMode, session, failure];
}
