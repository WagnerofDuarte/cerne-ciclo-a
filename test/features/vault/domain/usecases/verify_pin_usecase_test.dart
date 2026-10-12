import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/verify_pin_usecase.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockVaultRepository repository;
  late VerifyPinUseCase useCase;

  setUp(() {
    repository = MockVaultRepository();
    useCase = VerifyPinUseCase(repository);
  });

  test('correct PIN -> true', () async {
    when(() => repository.verifyPin('1234')).thenAnswer((_) async => true);

    final result = await useCase('1234');

    expect(result, isTrue);
  });

  test('incorrect PIN -> false', () async {
    when(() => repository.verifyPin('0000')).thenAnswer((_) async => false);

    final result = await useCase('0000');

    expect(result, isFalse);
  });
}
