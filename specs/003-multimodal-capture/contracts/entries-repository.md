# Contract: `entries` feature (`lib/features/entries/domain/`)

The shared seam research.md R8 builds because `requirements.md` §RF10 already names it: "the chat
feature triggers the creation of the entry through a shared interface / use case, never by
directly importing a repository or data source of the entries feature." RF01 is the unit that
creates this feature for the first time; RF10 (later) extends it, never bypasses it.

```dart
// lib/features/entries/domain/entities/entry.dart — see data-model.md for the full field table
enum EntrySource { manual, audio, photo }

class Entry extends Equatable {
  final String id;
  final String content;
  final EntrySource source;
  final String? chatMessageId;
  final DateTime occurredAt;
  final List<EntryTag> tags;
  final PiiStatus piiStatus;
  final List<PiiSpan> piiSpans;
  final EmbeddingStatus embeddingStatus;
  final int? mediaDurationSeconds;
  final int serverRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
}

// lib/features/entries/domain/repositories/entries_repository.dart
abstract class EntriesRepository {
  Future<Either<Failure, Entry>> create({required String content, required EntrySource source});
  List<Entry> get cachedEntries;
}

// lib/features/entries/domain/usecases/create_entry_usecase.dart
class CreateEntryUseCase {
  CreateEntryUseCase(this._repository);
  final EntriesRepository _repository;

  Future<Either<Failure, Entry>> call(String content, EntrySource source) =>
      _repository.create(content: content, source: source);
}
```

- **`EntriesRemoteDataSource`** (`lib/features/entries/data/entries_remote_data_source.dart`) is
  the only class that calls `ApiClient.call('entries-create', method: 'POST', body: {'content':
  content, 'source': source.name})` and parses the full `Entry` response shape (data-model.md). No
  `occurredAt`/`mediaDurationSeconds`/`chatMessageId` is ever sent in the request body by this unit
  — those are either server-assigned or belong to a later unit's request shape (RF10's
  `chatMessageId`).
- **`EntriesRepositoryImpl`** (`lib/features/entries/data/entries_repository_impl.dart`) wraps the
  data source, maps `DioException`/malformed bodies through the existing `ErrorMapper` (unchanged),
  and owns the in-memory `List<Entry>` backing `cachedEntries` — appended to only on a successful
  `create()`. Registered `lazySingleton` in `service_locator.dart` so the cache survives across
  modal opens (same lifetime pattern as `VaultRepository`, RF03 research.md R3).
- **Who depends on this**: `capture/domain/usecases/save_text_entry_usecase.dart`,
  `save_audio_entry_usecase.dart`, `save_photo_entry_usecase.dart` each depend on
  `CreateEntryUseCase` — never on `EntriesRepository` or `EntriesRemoteDataSource` directly, the
  same rule RF10 will have to follow later. No `presentation/` widget in `capture/` imports
  anything from `entries/` directly either — always through `capture/domain/`'s own usecases.
