import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/settings/data/dashboard_remote_data_source.dart';
import 'package:cerne/features/settings/data/dashboard_repository_impl.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_narrative.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockDashboardRemoteDataSource extends Mock implements DashboardRemoteDataSource {}

class MockSessionRepository extends Mock implements SessionRepository {}

Session _buildSession() => const Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresAt: 0,
  tokenType: 'bearer',
  account: Account(id: 'acc-1', email: 'test@example.com'),
);

const _zeroSources = DashboardSourceCounts(manual: 0, audio: 0, photo: 0, chat: 0);

DashboardAggregate _buildAggregate({bool empty = false}) => DashboardAggregate(
  buckets: empty
      ? const []
      : [AggregateBucket(date: DateTime(2026, 1, 1), count: 3, sources: _zeroSources)],
  totals: DashboardTotals(count: empty ? 0 : 3, sources: _zeroSources),
);

DashboardNarrative _buildNarrative() =>
    DashboardNarrative(text: 'hello', generatedAt: DateTime(2026, 1, 1));

void main() {
  late MockDashboardRemoteDataSource remoteDataSource;
  late MockSessionRepository sessionRepository;
  late DashboardRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockDashboardRemoteDataSource();
    sessionRepository = MockSessionRepository();
    repository = DashboardRepositoryImpl(
      remoteDataSource,
      sessionRepository: sessionRepository,
    );
  });

  group('fetchAggregate', () {
    test('200 zero-entry account returns Right with an empty bucket list', () async {
      final aggregate = _buildAggregate(empty: true);
      when(() => remoteDataSource.fetchAggregate())
          .thenAnswer((_) async => Right(aggregate));

      final result = await repository.fetchAggregate();

      expect(result, Right<Failure, DashboardAggregate>(aggregate));
    });

    test('200 well-formed non-empty payload returns Right', () async {
      final aggregate = _buildAggregate();
      when(() => remoteDataSource.fetchAggregate())
          .thenAnswer((_) async => Right(aggregate));

      final result = await repository.fetchAggregate();

      expect(result, Right<Failure, DashboardAggregate>(aggregate));
    });

    test('Dio timeout surfaces as Left(NetworkTimeoutFailure)', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: '');
      when(() => remoteDataSource.fetchAggregate())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchAggregate();

      expect(result, const Left<Failure, DashboardAggregate>(failure));
    });

    test('no connection surfaces as Left(NetworkOfflineFailure)', () async {
      const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
      when(() => remoteDataSource.fetchAggregate())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchAggregate();

      expect(result, const Left<Failure, DashboardAggregate>(failure));
    });

    test('malformed body surfaces as Left(ValidationFailure)', () async {
      const failure = ValidationFailure(message: 'malformed', requestId: '');
      when(() => remoteDataSource.fetchAggregate())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchAggregate();

      expect(result, const Left<Failure, DashboardAggregate>(failure));
    });

    test('AUTH_EXPIRED then successful silent refresh retries once', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: '');
      final aggregate = _buildAggregate();
      var callCount = 0;
      when(() => remoteDataSource.fetchAggregate()).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? const Left(authExpired) : Right(aggregate);
      });
      when(() => sessionRepository.refresh())
          .thenAnswer((_) async => Right(_buildSession()));

      final result = await repository.fetchAggregate();

      expect(result, Right<Failure, DashboardAggregate>(aggregate));
      expect(callCount, 2);
    });

    test('AUTH_EXPIRED then failed silent refresh returns Left(AuthExpiredFailure)', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: '');
      when(() => remoteDataSource.fetchAggregate())
          .thenAnswer((_) async => const Left(authExpired));
      when(() => sessionRepository.refresh()).thenAnswer(
        (_) async => const Left(AuthExpiredFailure(message: 'nope', requestId: '')),
      );

      final result = await repository.fetchAggregate();

      expect(result.isLeft(), isTrue);
      expect(
        result.match((f) => f, (_) => null),
        isA<AuthExpiredFailure>(),
      );
      verify(() => remoteDataSource.fetchAggregate()).called(1);
    });
  });

  group('fetchNarrative', () {
    test('200 well-formed payload returns Right', () async {
      final narrative = _buildNarrative();
      when(() => remoteDataSource.fetchNarrative())
          .thenAnswer((_) async => Right(narrative));

      final result = await repository.fetchNarrative();

      expect(result, Right<Failure, DashboardNarrative>(narrative));
    });

    test('Dio timeout surfaces as Left(NetworkTimeoutFailure)', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: '');
      when(() => remoteDataSource.fetchNarrative())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchNarrative();

      expect(result, const Left<Failure, DashboardNarrative>(failure));
    });

    test('no connection surfaces as Left(NetworkOfflineFailure)', () async {
      const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
      when(() => remoteDataSource.fetchNarrative())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchNarrative();

      expect(result, const Left<Failure, DashboardNarrative>(failure));
    });

    test('malformed body surfaces as Left(ValidationFailure)', () async {
      const failure = ValidationFailure(message: 'malformed', requestId: '');
      when(() => remoteDataSource.fetchNarrative())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchNarrative();

      expect(result, const Left<Failure, DashboardNarrative>(failure));
    });

    test('AUTH_EXPIRED then successful silent refresh retries once', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: '');
      final narrative = _buildNarrative();
      var callCount = 0;
      when(() => remoteDataSource.fetchNarrative()).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? const Left(authExpired) : Right(narrative);
      });
      when(() => sessionRepository.refresh())
          .thenAnswer((_) async => Right(_buildSession()));

      final result = await repository.fetchNarrative();

      expect(result, Right<Failure, DashboardNarrative>(narrative));
      expect(callCount, 2);
    });

    test('AUTH_EXPIRED then failed silent refresh returns Left(AuthExpiredFailure)', () async {
      const authExpired = AuthExpiredFailure(message: 'expired', requestId: '');
      when(() => remoteDataSource.fetchNarrative())
          .thenAnswer((_) async => const Left(authExpired));
      when(() => sessionRepository.refresh()).thenAnswer(
        (_) async => const Left(AuthExpiredFailure(message: 'nope', requestId: '')),
      );

      final result = await repository.fetchNarrative();

      expect(result.isLeft(), isTrue);
      verify(() => remoteDataSource.fetchNarrative()).called(1);
    });

    test('AI_GENERATION_TIMEOUT surfaces as Left(AiGenerationTimeoutFailure)', () async {
      const failure = AiGenerationTimeoutFailure(message: 'timed out', requestId: '');
      when(() => remoteDataSource.fetchNarrative())
          .thenAnswer((_) async => const Left(failure));

      final result = await repository.fetchNarrative();

      expect(result, const Left<Failure, DashboardNarrative>(failure));
    });
  });
}
