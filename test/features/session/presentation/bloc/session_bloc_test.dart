import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/session/domain/usecases/check_session_usecase.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockCheckSessionUseCase extends Mock implements CheckSessionUseCase {}

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  late MockCheckSessionUseCase checkSessionUseCase;
  late MockSessionRepository sessionRepository;

  final session = Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: 1234567890,
    tokenType: 'bearer',
    account: const Account(id: 'user-1', email: 'person@example.com'),
  );

  setUp(() {
    checkSessionUseCase = MockCheckSessionUseCase();
    sessionRepository = MockSessionRepository();
  });

  SessionBloc buildBloc() => SessionBloc(
        checkSessionUseCase: checkSessionUseCase,
        sessionRepository: sessionRepository,
      );

  group('AppStarted', () {
    blocTest<SessionBloc, SessionStatus>(
      'checking -> authenticated (routes Home/Chat)',
      setUp: () {
        when(() => checkSessionUseCase())
            .thenAnswer((_) async => SessionStatus.authenticated(session));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [
        SessionStatus.checking,
        isA<SessionStatusAuthenticated>(),
      ],
    );

    blocTest<SessionBloc, SessionStatus>(
      'checking -> unauthenticated (routes Login)',
      setUp: () {
        when(() => checkSessionUseCase())
            .thenAnswer((_) async => SessionStatus.unauthenticated);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [
        SessionStatus.checking,
        SessionStatus.unauthenticated,
      ],
    );

    blocTest<SessionBloc, SessionStatus>(
      'checking -> network-error (keeps splash, retry affordance, no route change)',
      setUp: () {
        when(() => checkSessionUseCase()).thenAnswer(
          (_) async => SessionStatus.networkError(
            const NetworkOfflineFailure(message: 'offline', requestId: 'r1'),
          ),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [
        SessionStatus.checking,
        isA<SessionStatusNetworkError>(),
      ],
    );
  });

  group('AuthExpiredDetected', () {
    blocTest<SessionBloc, SessionStatus>(
      'silent refresh() Right -> stays authenticated, no overlay-triggering state emitted',
      setUp: () {
        when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(session));
      },
      build: buildBloc,
      seed: () => SessionStatus.authenticated(session),
      act: (bloc) => bloc.add(const AuthExpiredDetected()),
      expect: () => <SessionStatus>[],
      verify: (_) {
        verify(() => sessionRepository.refresh()).called(1);
      },
    );

    blocTest<SessionBloc, SessionStatus>(
      'silent refresh() Left -> emits expiredRenewable',
      setUp: () {
        when(() => sessionRepository.refresh()).thenAnswer(
          (_) async => const Left(
            AuthInvalidFailure(message: 'invalid refresh token', requestId: 'r2'),
          ),
        );
      },
      build: buildBloc,
      seed: () => SessionStatus.authenticated(session),
      act: (bloc) => bloc.add(const AuthExpiredDetected()),
      expect: () => [SessionStatus.expiredRenewable],
    );

    blocTest<SessionBloc, SessionStatus>(
      'a second AuthExpiredDetected while already expiredRenewable never proceeds with the stale session',
      build: buildBloc,
      seed: () => SessionStatus.expiredRenewable,
      act: (bloc) => bloc.add(const AuthExpiredDetected()),
      expect: () => <SessionStatus>[],
      verify: (_) {
        verifyNever(() => sessionRepository.refresh());
      },
    );
  });
}
