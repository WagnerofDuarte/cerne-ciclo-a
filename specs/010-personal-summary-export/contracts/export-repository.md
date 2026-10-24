# Contract: `ExportRepository` / `ExportFileRepository`

`lib/features/export/domain/repositories/export_repository.dart`,
`lib/features/export/domain/repositories/export_file_repository.dart`, implemented by
`lib/features/export/data/export_repository_impl.dart`/`export_file_repository_impl.dart`.

```dart
abstract class ExportRepository {
  Future<Either<Failure, String>> create({required DateTime? periodStart, required DateTime? periodEnd});
  Future<Either<Failure, ExportJob>> status(String jobId);
  Future<Either<Failure, Uint8List>> download({required String jobId, required ExportFormat format});
}

abstract class ExportFileRepository {
  Future<Either<Failure, Unit>> share({required Uint8List bytes, required ExportFormat format});
}
```

## `ExportRepositoryImpl.create` — request shape

```dart
await _apiClient.call(
  'export-summary-create',
  method: 'POST',
  body: {
    'periodStart': periodStart?.toUtc().toIso8601String(),  // explicit null, never omitted — both keys are
    'periodEnd': periodEnd?.toUtc().toIso8601String(),      // in the OpenAPI schema's `required` list even
    'includeNarrative': true,                               // though both are `nullable: true`
  },
);
```

Parses `data.jobId` (string) from the `202` response; `data.status` is always `'pending'` at this point and is
not separately parsed (the first `status()` poll re-derives the real `ExportJob` immediately after).
`EXPORT_EMPTY_PERIOD` (400) is mapped by the existing, shared `ErrorMapper.fromResponse` → `Left
(ExportEmptyPeriodFailure)` — no export-specific error parsing needed.

## `ExportRepositoryImpl.status` — response shape

```dart
await _apiClient.call('export-status-get', method: 'GET', pathSegments: [jobId]);
```

Parses the full `ExportJob` (`data.jobId`/`data.status`/`data.narrativeStatus`/`data.entryCount`/
`data.errorCode`/`data.narrativeErrorCode`/`data.downloadAvailable`) — every field in the OpenAPI schema's own
`required` list, all nullable except `jobId`/`status`/`narrativeStatus`/`downloadAvailable`. `status`'s wire
value `data_ready` parses to `ExportJobStatus.dataReady` via an explicit lookup table (not `.byName`, since
Dart enum names cannot contain an underscore the way the wire value does) — every other enum
(`ExportJobStatus`'s other four values, all of `NarrativeStatus`) parses via `.byName` as usual.

## `ExportRepositoryImpl.download` — delegates to `ApiClient.downloadFile`

```dart
await _apiClient.downloadFile(
  'export-download-get',
  pathSegments: [jobId],
  queryParameters: {'format': format.name},  // 'pdf' | 'raw'
);
```

No response parsing — `contracts/http-client-download-extension.md` already returns raw `Uint8List`.

## Silent-refresh-and-retry — identical shape across all three methods

```dart
Future<Either<Failure, T>> _retryAfterSilentRefresh<T>(Future<Either<Failure, T>> Function() retry) async {
  final refreshed = await _sessionRepository.refresh();
  return refreshed.match(
    (_) => Future.value(const Left(AuthExpiredFailure(message: 'Session could not be renewed', requestId: ''))),
    (_) => retry(),
  );
}
```

Copied verbatim from `EntriesRepositoryImpl` (RF07) — exactly one retry; a second `AuthExpiredFailure` after
that retry is returned as-is, never a loop.

## `ExportFileRepositoryImpl.share` — behavior

```dart
Future<Either<Failure, Unit>> share({required Uint8List bytes, required ExportFormat format}) async {
  try {
    final dir = await getTemporaryDirectory();
    final extension = format == ExportFormat.pdf ? 'pdf' : 'json';
    final name = format == ExportFormat.pdf ? 'cerne-resumo' : 'cerne-dados';
    final file = File('${dir.path}/$name.$extension');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)]);
    return const Right(unit);
  } catch (_) {
    return const Left(NetworkTimeoutFailure(message: 'Falha ao salvar/compartilhar o arquivo.', requestId: ''));
  }
}
```

A `share_plus` cancel (the user dismissing the OS share sheet without picking a target) is reported by the
package as a normal, non-throwing `ShareResult` — never reaches the `catch` above, and is treated as success
(`Right(unit)`): the file *was* produced and offered; whether the user then chose to save it is outside this
unit's concern (Assumptions: "this unit is not responsible for building a custom in-app file viewer").

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `create()` — backend returns `202 {jobId: 'abc'}` | `Right('abc')` |
| 2 | `create()` — backend returns `400 {code: 'EXPORT_EMPTY_PERIOD', ...}` | `Left(ExportEmptyPeriodFailure)` |
| 3 | `create()` — backend returns `504 {code: 'NETWORK_TIMEOUT', ...}` (or a transport-level timeout) | `Left(NetworkTimeoutFailure)` |
| 4 | `create()` — backend returns `202` with a malformed body (missing `jobId`) | `Left(ValidationFailure)` |
| 5 | `create()` — a transport-level connection failure with no response at all (e.g. no network) | `Left(NetworkOfflineFailure)` |
| 6 | `status()` — backend returns `{status: 'data_ready', narrativeStatus: 'processing', downloadAvailable: true, ...}` | `Right(ExportJob(status: dataReady, narrativeStatus: processing, ...))` |
| 7 | `status()` — malformed body (missing a required field) | `Left(ValidationFailure)` |
| 8 | `create()`/`status()`/`download()` — first attempt `AuthExpiredFailure`, `SessionRepository.refresh()` succeeds, retried call succeeds | the retried call's own `Right(...)` |
| 9 | Same as 8, but `refresh()` itself fails | `Left(AuthExpiredFailure)` — exactly one retry, no loop |
| 10 | `download()` — `ApiClient.downloadFile` returns `Right(bytes)` | `Right(bytes)` unchanged |
| 11 | `ExportFileRepositoryImpl.share()` — `path_provider`/file-write succeeds, `Share.shareXFiles` resolves normally (including a user-cancelled share) | `Right(unit)` |
| 12 | `ExportFileRepositoryImpl.share()` — the file write throws (e.g. disk full) | `Left(NetworkTimeoutFailure)` (retryable) |
