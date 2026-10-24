# Contract: `ChatRepository.createInsight` (extension)

Source: `docs/input/backend/api/openapi.yaml`'s `/chat/sessions/{id}/insight` POST schema;
`docs/input/backend/error-taxonomy.md`; data-model.md; research.md R6/R7/R13.

## Signature

```dart
Future<Either<Failure, String>> createInsight({
  required String sessionId,
  required InsightTriggerType triggerType,
  required String triggerKey,
});
```

- `Right(content)` — the backend's `status: 'ready'`, `content` non-null.
- `Left(Failure)` — a transport failure (timeout, no connection, malformed response/unrecognized `errorCode`),
  **or** a 200 response with any `status` other than `'ready'` (in practice `'failed'`), mapped through
  `ErrorMapper.fromResponse` using the response's own `errorCode` field. Every `Left` cause is handled
  identically by `ChatBloc` (FR-006) — this method's own callers never branch on *which* `Failure` subtype came
  back.

## Request shape (`chat-insight-create`)

```jsonc
POST /chat/sessions/:id/insight
{ "triggerType": "message_count" | "inactivity", "triggerKey": "<non-empty string>" }
```

`triggerType`'s wire value is produced by `ChatRemoteDataSource._wireTriggerType` (`messageCount` →
`'message_count'`, `inactivity` → `'inactivity'`) — the domain enum never carries wire-format knowledge
(RNF06).

## Response shape (relevant fields only)

```jsonc
{ "data": { "status": "ready" | "failed" | ..., "content": "<string>" | null, "errorCode": "<code>" | null, ... } }
```

Per the OpenAPI summary, this endpoint is "never an HTTP error" — a generation failure is still a `200` with
`status: 'failed'`. `_parseInsightContent` reads only `status`/`content`/`errorCode`; every other field
(`id`, `sessionId`, `triggerType`, `triggerKey`, `dismissedAt`, `createdAt`) is accepted by the backend but
never read by this app (FR-009 — nothing about an insight is stored or echoed back into any UI).

## Auth / retry

Same shape as every other non-streaming `ChatRepositoryImpl` method:
`_retryAfterSilentRefreshIfExpired` retries the call exactly once via `SessionRepository.refresh()` if the
*first* attempt's `Failure` is `AuthExpiredFailure`; a repeat `AuthExpiredFailure` after that retry is returned
as-is. `ChatBloc` reacts to a surfaced `AuthExpiredFailure` by firing `reauthRequired` (raising the existing
"Sessão expirada" overlay) — exactly as every other auth-expiry path in this bloc already does — then still
treats the occurrence as a plain failure (no card).

## Caching

None. `createInsight` never reads or writes `ChatLocalCache` — FR-009 requires zero persistence for an insight,
in contrast to every other `ChatRepositoryImpl` method, which caches its result for offline fallback.

## Test-scenario table (RNF09 contribution — research.md R13)

| # | Scenario | Setup | Expected `ChatRemoteDataSource.createInsight` / `ChatRepositoryImpl.createInsight` result |
|---|---|---|---|
| 1 | Success | `ApiClient.call` returns `Right({'status': 'ready', 'content': 'Some insight text'})` | `Right('Some insight text')` |
| 2 | Backend-reported failure | `ApiClient.call` returns `Right({'status': 'failed', 'errorCode': 'AI_GENERATION_TIMEOUT', 'id': 'ins_1'})` | `Left(AiGenerationTimeoutFailure(...))` |
| 3 | Backend-reported failure, null `errorCode` | `Right({'status': 'failed', 'errorCode': null, 'id': 'ins_1'})` | `Left(ValidationFailure(...))` (`ErrorMapper`'s own unrecognized-code default) |
| 4 | Malformed response (missing `status`) | `Right({'content': 'x'})` | `Left(_malformedChatFailure)` (`TypeError` caught) |
| 5 | Timeout | `ApiClient.call` returns `Left(NetworkTimeoutFailure(...))` | `Left(NetworkTimeoutFailure(...))`, unchanged |
| 6 | No connection | `ApiClient.call` returns `Left(NetworkOfflineFailure(...))` | `Left(NetworkOfflineFailure(...))`, unchanged |
| 7 | Auth expired, silent refresh succeeds | First call → `Left(AuthExpiredFailure(...))`; `SessionRepository.refresh()` → `Right(...)`; second call → `Right({'status': 'ready', ...})` | `Right(content)` — retried transparently |
| 8 | Auth expired, silent refresh fails | First call → `Left(AuthExpiredFailure(...))`; `refresh()` → `Left(...)` | `Left(AuthExpiredFailure(message: 'Session could not be renewed', ...))` |
| 9 | No local-cache interaction | Any outcome above | `ChatLocalCache` is never called by `createInsight` (verified via a `verifyNever` on the mock in `chat_repository_impl_test.dart`) |

Scenarios 5–6 (plus 4, as the "malformed response" case) are this unit's contribution to RNF09's project-wide
"5 write endpoints × 3 failures" tally for its one new endpoint; scenarios 1–3 and 7–9 cover this endpoint's own
additional, non-RNF09-counted semantics (the `status: 'failed'` collapse, and the no-cache guarantee).
