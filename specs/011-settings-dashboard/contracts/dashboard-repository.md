# Contract: `DashboardRepository`

`features/settings/domain/repositories/dashboard_repository.dart`, implemented by
`DashboardRepositoryImpl` (`features/settings/data/`), backed by `DashboardRemoteDataSource` calling
`dashboard-aggregate-get` (`GET /dashboard/aggregate?period=all`) and `dashboard-narrative-get`
(`GET /dashboard/narrative?period=all`).

```dart
abstract class DashboardRepository {
  Future<Either<Failure, DashboardAggregate>> fetchAggregate();
  Future<Either<Failure, DashboardNarrative>> fetchNarrative();
}
```

## Parsing

`fetchAggregate()` decodes `data.buckets[]` (`date`, `count`, `sources.{manual,audio,photo,chat}`) and
`data.totals` (`count`, `sources`) per `openapi.yaml`'s schema (both always present, even for a zero-entry
account — "always 200" per the contract's own summary line). `fetchNarrative()` decodes `data.text`/
`data.generatedAt`. A missing/mistyped required field on either call is a `ValidationFailure` (`TypeError`
caught, never thrown past this boundary — same pattern as `SessionRepositoryImpl._assembleFromCheckSession`).

## Retry-once-on-expiry

Both methods follow `EntriesRepositoryImpl._retryAfterSilentRefresh`'s exact shape: on `AuthExpiredFailure`,
call `SessionRepository.refresh()` once; on its own failure, return
`Left(AuthExpiredFailure(message: 'Session could not be renewed'))` (no second refresh attempt); on success,
retry the original call exactly once more and return whatever it resolves to.

## Scenario table (RNF09 — `fetchAggregate`/`fetchNarrative` are `GET`s, outside the write-endpoint tally,
but still fully `Either`-typed and tested)

| # | Scenario | Expected `Either` |
|---|---|---|
| 1 | 200, zero-entry account (`buckets: []`, `totals.count: 0`) | `Right(DashboardAggregate)` with an empty bucket list — never a `Left` |
| 2 | 200, well-formed non-empty payload | `Right(DashboardAggregate)` / `Right(DashboardNarrative)` |
| 3 | Dio timeout | `Left(NetworkTimeoutFailure)` |
| 4 | No connection (no response) | `Left(NetworkOfflineFailure)` |
| 5 | 200 with a malformed body (`buckets` not a list / `count` missing) | `Left(ValidationFailure)` |
| 6 | 401 `AUTH_EXPIRED`, silent refresh succeeds | retried call's own result (success path re-exercises #1/#2) |
| 7 | 401 `AUTH_EXPIRED`, silent refresh itself fails | `Left(AuthExpiredFailure)`, and `SettingsBloc.reauthRequired` fires |
| 8 | `dashboard-narrative-get` returns `AI_GENERATION_TIMEOUT` | `Left(AiGenerationTimeoutFailure)` — mapped by `ErrorMapper` unchanged, surfaced by `SettingsBloc` as the "narrativa indisponível" state (FR-006), never conflated with #1's empty-history copy |

## `DashboardAggregate.tenBars()` — see data-model.md / research.md R2

Exercised directly by a domain unit test (no repository/network involved) for: empty input (10 zeros), a
single bucket on "today" (all weight in bar 9), buckets spanning exactly 10 days (one bucket per bar,
1:1), buckets spanning 100 days (several buckets folding into the same bar), and a bucket dated after `today`
(defensive — clamps to bar 9 rather than throwing or going out-of-range).
