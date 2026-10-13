import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The one and only sanctioned way any other feature creates an entry
/// (research.md R8) — `capture`'s three save usecases depend on this, never
/// on [EntriesRepository] directly. RF10 will extend this signature, never
/// bypass it.
class CreateEntryUseCase {
  const CreateEntryUseCase(this._repository);

  final EntriesRepository _repository;

  Future<Either<Failure, Entry>> call(String content, EntrySource source) =>
      _repository.create(content: content, source: source);
}
