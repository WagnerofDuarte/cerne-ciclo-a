import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/data/entries_repository_impl.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/session/domain/entities/session.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockEntriesRemoteDataSource extends Mock implements EntriesRemoteDataSource {}

class MockSessionRepository extends Mock implements SessionRepository {}

Entry _buildEntry() => Entry(
  id: 'entry-1',
  content: 'hello',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: DateTime(2026, 1, 1),
  tags: const [],
  piiStatus: PiiStatus.pending,
  piiSpans: const [],
  embeddingStatus: EmbeddingStatus.pending,
  mediaDurationSeconds: null,
  serverRevision: 1,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Session _buildSession() => const Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresAt: 0,
  tokenType: 'bearer',
  account: Account(id: 'acc-1', email: 'test@example.com'),
);

void main() {
  late MockEntriesRemoteDataSource remoteDataSource;
  late MockSessionRepository sessionRepository;
  late EntriesRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    remoteDataSource = MockEntriesRemoteDataSource();
    sessionRepository = MockSessionRepository();
    repository = EntriesRepositoryImpl(
      remoteDataSource,
      sessionRepository: sessionRepository,
    );
  });

  test('cachedEntries starts empty', () {
    expect(repository.cachedEntries, isEmpty);
  });

  test('a successful create() appends the entry to cachedEntries', () async {
    final entry = _buildEntry();
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => Right(entry));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, Right<Failure, Entry>(entry));
    expect(repository.cachedEntries, [entry]);
  });

  test('timeout failure passes through unchanged and nothing is cached', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => const Left(failure));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, const Left<Failure, Entry>(failure));
    expect(repository.cachedEntries, isEmpty);
  });

  test('offline failure passes through unchanged and nothing is cached', () async {
    const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => const Left(failure));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, const Left<Failure, Entry>(failure));
    expect(repository.cachedEntries, isEmpty);
  });

  test('malformed-response failure passes through unchanged and nothing is cached', () async {
    const failure = ValidationFailure(message: 'malformed', requestId: 'r3');
    when(
      () => remoteDataSource.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((_) async => const Left(failure));

    final result = await repository.create(
      content: 'hello',
      source: EntrySource.manual,
    );

    expect(result, const Left<Failure, Entry>(failure));
    expect(repository.cachedEntries, isEmpty);
  });

  group('list()', () {
    final page = EntriesPage(entries: [_buildEntry()], nextCursor: 'cursor-2');

    test('success on the first attempt returns Right with no refresh call made', () async {
      when(
        () => remoteDataSource.list(cursor: any(named: 'cursor')),
      ).thenAnswer((_) async => Right(page));

      final result = await repository.list();

      expect(result, Right<Failure, EntriesPage>(page));
      verifyNever(() => sessionRepository.refresh());
    });

    test(
      'AuthExpiredFailure followed by a successful refresh retries and returns '
      'Right, with exactly 2 remote calls and 1 refresh call',
      () async {
        const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
        var callCount = 0;
        when(() => remoteDataSource.list(cursor: any(named: 'cursor'))).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? const Left(authExpired) : Right(page);
        });
        when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildSession()));

        final result = await repository.list();

        expect(result, Right<Failure, EntriesPage>(page));
        expect(callCount, 2);
        verify(() => sessionRepository.refresh()).called(1);
      },
    );

    test(
      'AuthExpiredFailure followed by a refresh that itself fails returns '
      'Left(AuthExpiredFailure), no second refresh attempt',
      () async {
        const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
        when(
          () => remoteDataSource.list(cursor: any(named: 'cursor')),
        ).thenAnswer((_) async => const Left(authExpired));
        when(() => sessionRepository.refresh()).thenAnswer(
          (_) async => const Left(AuthInvalidFailure(message: 'no token', requestId: '')),
        );

        final result = await repository.list();

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<AuthExpiredFailure>());
        verify(() => sessionRepository.refresh()).called(1);
        verify(() => remoteDataSource.list(cursor: any(named: 'cursor'))).called(1);
      },
    );

    test('any other failure code passes through unchanged with no refresh attempted', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
      when(
        () => remoteDataSource.list(cursor: any(named: 'cursor')),
      ).thenAnswer((_) async => const Left(failure));

      final result = await repository.list();

      expect(result, const Left<Failure, EntriesPage>(failure));
      verifyNever(() => sessionRepository.refresh());
    });

    test('passes the cursor straight through to the remote data source', () async {
      when(
        () => remoteDataSource.list(cursor: any(named: 'cursor')),
      ).thenAnswer((_) async => Right(page));

      await repository.list(cursor: 'abc');

      verify(() => remoteDataSource.list(cursor: 'abc')).called(1);
    });
  });

  group('getById()', () {
    final entry = _buildEntry();

    test('success on the first attempt returns Right with no refresh call made', () async {
      when(() => remoteDataSource.getById(any())).thenAnswer((_) async => Right(entry));

      final result = await repository.getById('entry-1');

      expect(result, Right<Failure, Entry>(entry));
      verifyNever(() => sessionRepository.refresh());
    });

    test(
      'AuthExpiredFailure followed by a successful refresh retries and returns '
      'Right, with exactly 2 remote calls and 1 refresh call',
      () async {
        const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
        var callCount = 0;
        when(() => remoteDataSource.getById(any())).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? const Left(authExpired) : Right(entry);
        });
        when(() => sessionRepository.refresh()).thenAnswer((_) async => Right(_buildSession()));

        final result = await repository.getById('entry-1');

        expect(result, Right<Failure, Entry>(entry));
        expect(callCount, 2);
        verify(() => sessionRepository.refresh()).called(1);
      },
    );

    test(
      'AuthExpiredFailure followed by a refresh that itself fails returns '
      'Left(AuthExpiredFailure), no second refresh attempt',
      () async {
        const authExpired = AuthExpiredFailure(message: 'expired', requestId: 'r1');
        when(
          () => remoteDataSource.getById(any()),
        ).thenAnswer((_) async => const Left(authExpired));
        when(() => sessionRepository.refresh()).thenAnswer(
          (_) async => const Left(AuthInvalidFailure(message: 'no token', requestId: '')),
        );

        final result = await repository.getById('entry-1');

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<AuthExpiredFailure>());
        verify(() => sessionRepository.refresh()).called(1);
        verify(() => remoteDataSource.getById(any())).called(1);
      },
    );

    test('any other failure code passes through unchanged with no refresh attempted', () async {
      const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
      when(() => remoteDataSource.getById(any())).thenAnswer((_) async => const Left(failure));

      final result = await repository.getById('entry-1');

      expect(result, const Left<Failure, Entry>(failure));
      verifyNever(() => sessionRepository.refresh());
    });
  });
}
