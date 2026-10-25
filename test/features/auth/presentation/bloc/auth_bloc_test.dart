import 'package:bloc_test/bloc_test.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/auth/domain/usecases/login_usecase.dart';
import 'package:cerne/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_event.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_state.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLoginUseCase extends Mock implements LoginUseCase {}

class MockSignUpUseCase extends Mock implements SignUpUseCase {}

class MockEntriesRepository extends Mock implements EntriesRepository {}

class MockChatRepository extends Mock implements ChatRepository {}

void main() {
  late MockLoginUseCase loginUseCase;
  late MockSignUpUseCase signUpUseCase;
  late MockEntriesRepository entriesRepository;
  late MockChatRepository chatRepository;

  const email = 'person@example.com';
  const password = 'correct-horse';

  final session = Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: 1234567890,
    tokenType: 'bearer',
    account: const Account(id: 'user-1', email: email),
  );

  setUp(() {
    loginUseCase = MockLoginUseCase();
    signUpUseCase = MockSignUpUseCase();
    entriesRepository = MockEntriesRepository();
    chatRepository = MockChatRepository();
    when(() => entriesRepository.clearLocalData()).thenAnswer((_) async {});
    when(() => chatRepository.clearLocalData()).thenAnswer((_) async {});
  });

  AuthBloc buildBloc() => AuthBloc(
        loginUseCase: loginUseCase,
        signUpUseCase: signUpUseCase,
        entriesRepository: entriesRepository,
        chatRepository: chatRepository,
      );

  group('LoginSubmitted', () {
    blocTest<AuthBloc, AuthState>(
      'loading -> authenticated for valid credentials',
      setUp: () {
        when(() => loginUseCase(email: email, password: password))
            .thenAnswer((_) async => Right(session));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoginSubmitted(email: email, password: password)),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        AuthState(status: AuthStatus.authenticated, session: session),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'loading -> failure(AuthInvalidFailure) for wrong credentials, non-crashing',
      setUp: () {
        const failure = AuthInvalidFailure(message: 'wrong credentials', requestId: 'r1');
        when(() => loginUseCase(email: email, password: password))
            .thenAnswer((_) async => const Left(failure));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoginSubmitted(email: email, password: password)),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        const AuthState(
          status: AuthStatus.failure,
          failure: AuthInvalidFailure(message: 'wrong credentials', requestId: 'r1'),
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'loading -> failure(NetworkOfflineFailure, retryable) with no network',
      setUp: () {
        const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
        when(() => loginUseCase(email: email, password: password))
            .thenAnswer((_) async => const Left(failure));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoginSubmitted(email: email, password: password)),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        const AuthState(
          status: AuthStatus.failure,
          failure: NetworkOfflineFailure(message: 'no connection', requestId: 'r2'),
        ),
      ],
      verify: (_) {
        expect(const NetworkOfflineFailure(message: '', requestId: '').retryable, isTrue);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'a second LoginSubmitted while already loading is ignored — no second network call',
      setUp: () {
        when(() => loginUseCase(email: email, password: password)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return Right(session);
        });
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const LoginSubmitted(email: email, password: password));
        bloc.add(const LoginSubmitted(email: email, password: password));
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        AuthState(status: AuthStatus.authenticated, session: session),
      ],
      verify: (_) {
        verify(() => loginUseCase(email: email, password: password)).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'a successful login clears this device\'s entries/chat cache so a '
      'previous account\'s data never leaks into the next one',
      setUp: () {
        when(() => loginUseCase(email: email, password: password))
            .thenAnswer((_) async => Right(session));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoginSubmitted(email: email, password: password)),
      verify: (_) {
        verify(() => entriesRepository.clearLocalData()).called(1);
        verify(() => chatRepository.clearLocalData()).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'a failed login never clears the entries/chat cache',
      setUp: () {
        const failure = AuthInvalidFailure(message: 'wrong credentials', requestId: 'r1');
        when(() => loginUseCase(email: email, password: password))
            .thenAnswer((_) async => const Left(failure));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoginSubmitted(email: email, password: password)),
      verify: (_) {
        verifyNever(() => entriesRepository.clearLocalData());
        verifyNever(() => chatRepository.clearLocalData());
      },
    );
  });

  group('SignUpSubmitted', () {
    blocTest<AuthBloc, AuthState>(
      'ToggleModeRequested flips AuthFormMode with no network call',
      build: buildBloc,
      act: (bloc) => bloc.add(const ToggleModeRequested()),
      expect: () => [
        const AuthState(formMode: AuthFormMode.signUp),
      ],
      verify: (_) {
        verifyNever(() => signUpUseCase(email: any(named: 'email'), password: any(named: 'password')));
        verifyNever(() => loginUseCase(email: any(named: 'email'), password: any(named: 'password')));
      },
    );

    blocTest<AuthBloc, AuthState>(
      'loading -> authenticated for a new email',
      setUp: () {
        when(() => signUpUseCase(email: email, password: password))
            .thenAnswer((_) async => Right(session));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SignUpSubmitted(email: email, password: password)),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        AuthState(status: AuthStatus.authenticated, session: session),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'loading -> failure(AuthInvalidFailure) for an already-registered email',
      setUp: () {
        const failure = AuthInvalidFailure(message: 'already registered', requestId: 'r3');
        when(() => signUpUseCase(email: email, password: password))
            .thenAnswer((_) async => const Left(failure));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SignUpSubmitted(email: email, password: password)),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        const AuthState(
          status: AuthStatus.failure,
          failure: AuthInvalidFailure(message: 'already registered', requestId: 'r3'),
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'a second SignUpSubmitted while already loading is ignored — no duplicate account creation',
      setUp: () {
        when(() => signUpUseCase(email: email, password: password)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return Right(session);
        });
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const SignUpSubmitted(email: email, password: password));
        bloc.add(const SignUpSubmitted(email: email, password: password));
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const AuthState(status: AuthStatus.loading),
        AuthState(status: AuthStatus.authenticated, session: session),
      ],
      verify: (_) {
        verify(() => signUpUseCase(email: email, password: password)).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'a new account signing up on this device never inherits a prior '
      'account\'s entries/chat cache',
      setUp: () {
        when(() => signUpUseCase(email: email, password: password))
            .thenAnswer((_) async => Right(session));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const SignUpSubmitted(email: email, password: password)),
      verify: (_) {
        verify(() => entriesRepository.clearLocalData()).called(1);
        verify(() => chatRepository.clearLocalData()).called(1);
      },
    );
  });
}
