import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/settings/data/account_deletion_remote_data_source.dart';
import 'package:cerne/features/settings/data/account_deletion_repository_impl.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAccountDeletionRemoteDataSource extends Mock
    implements AccountDeletionRemoteDataSource {}

void main() {
  late MockAccountDeletionRemoteDataSource remoteDataSource;
  late AccountDeletionRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockAccountDeletionRemoteDataSource();
    repository = AccountDeletionRepositoryImpl(remoteDataSource);
  });

  test('200 with ok: true -> Right(unit)', () async {
    when(() => remoteDataSource.deleteAccount())
        .thenAnswer((_) async => const Right({'ok': true}));

    final result = await repository.deleteAccount();

    expect(result, const Right<Failure, Unit>(unit));
  });

  test('Dio timeout -> Left(NetworkTimeoutFailure)', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: '');
    when(() => remoteDataSource.deleteAccount()).thenAnswer((_) async => const Left(failure));

    final result = await repository.deleteAccount();

    expect(result, const Left<Failure, Unit>(failure));
  });

  test('no connection -> Left(NetworkOfflineFailure)', () async {
    const failure = NetworkOfflineFailure(message: 'offline', requestId: '');
    when(() => remoteDataSource.deleteAccount()).thenAnswer((_) async => const Left(failure));

    final result = await repository.deleteAccount();

    expect(result, const Left<Failure, Unit>(failure));
  });

  test('200 with data.ok missing -> Left(ValidationFailure)', () async {
    when(() => remoteDataSource.deleteAccount()).thenAnswer((_) async => const Right({}));

    final result = await repository.deleteAccount();

    expect(result.isLeft(), isTrue);
    expect(result.match((f) => f, (_) => null), isA<ValidationFailure>());
  });

  test('200 with data.ok not true -> Left(ValidationFailure)', () async {
    when(() => remoteDataSource.deleteAccount())
        .thenAnswer((_) async => const Right({'ok': false}));

    final result = await repository.deleteAccount();

    expect(result.isLeft(), isTrue);
    expect(result.match((f) => f, (_) => null), isA<ValidationFailure>());
  });

  test('401 AUTH_EXPIRED -> Left(AuthExpiredFailure), no retry attempted', () async {
    const failure = AuthExpiredFailure(message: 'expired', requestId: '');
    when(() => remoteDataSource.deleteAccount()).thenAnswer((_) async => const Left(failure));

    final result = await repository.deleteAccount();

    expect(result, const Left<Failure, Unit>(failure));
    verify(() => remoteDataSource.deleteAccount()).called(1);
  });
}
