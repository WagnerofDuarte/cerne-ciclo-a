import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/save_pin_usecase.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockVaultRepository repository;
  late SavePinUseCase useCase;

  setUp(() {
    repository = MockVaultRepository();
    useCase = SavePinUseCase(repository);
  });

  test('delegates to repository.savePin', () async {
    when(() => repository.savePin('1234')).thenAnswer((_) async {});

    await useCase('1234');

    verify(() => repository.savePin('1234')).called(1);
  });
}
