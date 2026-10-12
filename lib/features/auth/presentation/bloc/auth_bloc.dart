import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/usecases/login_usecase.dart';
import 'package:cerne/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_event.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_state.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this._loginUseCase, required this._signUpUseCase})
      : super(const AuthState()) {
    on<LoginSubmitted>(_onLoginSubmitted);
    on<SignUpSubmitted>(_onSignUpSubmitted);
    on<ToggleModeRequested>(_onToggleModeRequested);
  }

  final LoginUseCase _loginUseCase;
  final SignUpUseCase _signUpUseCase;

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    // Guards against a concurrent submit: a backgrounded-resume double-tap
    // never produces a second network call / duplicate session (Edge Cases).
    if (state.status == AuthStatus.loading) return;

    emit(AuthState(status: AuthStatus.loading, formMode: state.formMode));
    final result = await _loginUseCase(email: event.email, password: event.password);
    _emitResult(result, emit);
  }

  Future<void> _onSignUpSubmitted(
    SignUpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    if (state.status == AuthStatus.loading) return;

    emit(AuthState(status: AuthStatus.loading, formMode: state.formMode));
    final result = await _signUpUseCase(email: event.email, password: event.password);
    _emitResult(result, emit);
  }

  void _emitResult(Either<Failure, Session> result, Emitter<AuthState> emit) {
    result.match(
      (failure) => emit(
        AuthState(
          status: AuthStatus.failure,
          formMode: state.formMode,
          failure: failure,
        ),
      ),
      (session) => emit(
        AuthState(
          status: AuthStatus.authenticated,
          formMode: state.formMode,
          session: session,
        ),
      ),
    );
  }

  void _onToggleModeRequested(
    ToggleModeRequested event,
    Emitter<AuthState> emit,
  ) {
    emit(
      AuthState(
        status: state.status,
        formMode: state.formMode == AuthFormMode.login
            ? AuthFormMode.signUp
            : AuthFormMode.login,
        session: state.session,
        failure: state.failure,
      ),
    );
  }
}
