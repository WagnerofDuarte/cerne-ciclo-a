import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/usecases/login_usecase.dart';
import 'package:cerne/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_event.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_state.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

/// Depends on [EntriesRepository]/[ChatRepository] (beyond the auth-repository
/// contract's own listed set) so a successful login/sign-up can wipe
/// whichever account's entries/chat data an earlier session on this device
/// left behind — those on-device caches have no account scoping of their
/// own (data-model.md EntriesLocalCache/ChatLocalCache), and logout
/// deliberately leaves them in place for the same-account case
/// (research.md R9). A different account authenticating on this device
/// must never inherit that leftover data.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required this._loginUseCase,
    required this._signUpUseCase,
    required this._entriesRepository,
    required this._chatRepository,
  }) : super(const AuthState()) {
    on<LoginSubmitted>(_onLoginSubmitted);
    on<SignUpSubmitted>(_onSignUpSubmitted);
    on<ToggleModeRequested>(_onToggleModeRequested);
  }

  final LoginUseCase _loginUseCase;
  final SignUpUseCase _signUpUseCase;
  final EntriesRepository _entriesRepository;
  final ChatRepository _chatRepository;

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    // Guards against a concurrent submit: a backgrounded-resume double-tap
    // never produces a second network call / duplicate session (Edge Cases).
    if (state.status == AuthStatus.loading) return;

    emit(AuthState(status: AuthStatus.loading, formMode: state.formMode));
    final result = await _loginUseCase(email: event.email, password: event.password);
    await _emitResult(result, emit);
  }

  Future<void> _onSignUpSubmitted(
    SignUpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    if (state.status == AuthStatus.loading) return;

    emit(AuthState(status: AuthStatus.loading, formMode: state.formMode));
    final result = await _signUpUseCase(email: event.email, password: event.password);
    await _emitResult(result, emit);
  }

  Future<void> _emitResult(
    Either<Failure, Session> result,
    Emitter<AuthState> emit,
  ) async {
    await result.match(
      (failure) async => emit(
        AuthState(
          status: AuthStatus.failure,
          formMode: state.formMode,
          failure: failure,
        ),
      ),
      (session) async {
        // This device may still be holding another account's entries/chat
        // cache from an earlier session (logout never clears it — R9). Wipe
        // it before the authenticated state renders Home/Meus Registros, so
        // that screen never has a frame with someone else's data on it.
        await _entriesRepository.clearLocalData();
        await _chatRepository.clearLocalData();
        emit(
          AuthState(
            status: AuthStatus.authenticated,
            formMode: state.formMode,
            session: session,
          ),
        );
      },
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
