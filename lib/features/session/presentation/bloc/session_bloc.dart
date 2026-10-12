import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/session/domain/usecases/check_session_usecase.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SessionBloc extends Bloc<SessionEvent, SessionStatus> {
  SessionBloc({
    required this._checkSessionUseCase,
    required this._sessionRepository,
  })  : super(SessionStatus.checking) {
    on<AppStarted>(_onAppStarted);
    on<AuthExpiredDetected>(_onAuthExpiredDetected);
  }

  final CheckSessionUseCase _checkSessionUseCase;
  final SessionRepository _sessionRepository;

  Future<void> _onAppStarted(AppStarted event, Emitter<SessionStatus> emit) async {
    emit(SessionStatus.checking);
    emit(await _checkSessionUseCase());
  }

  Future<void> _onAuthExpiredDetected(
    AuthExpiredDetected event,
    Emitter<SessionStatus> emit,
  ) async {
    // The overlay is already up — never silently proceed with the stale
    // session by attempting a second concurrent refresh (Edge Cases).
    if (state is SessionStatusExpiredRenewable) return;

    final refreshed = await _sessionRepository.refresh();
    if (refreshed.isLeft()) {
      emit(SessionStatus.expiredRenewable);
    }
    // Right: silent refresh succeeded — stays authenticated, no
    // overlay-triggering state emitted.
  }
}
