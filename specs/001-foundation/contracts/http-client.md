# Contract: `ApiClient` (`lib/core/network/api_client.dart`)

The single way any feature calls the backend (FR-003). Every later unit's `data/` layer depends on
this, never on `dio` directly.

## Construction

```dart
class ApiClient {
  ApiClient({required Dio dio, required SecureTokenStorage tokenStorage, required String anonKey});

  Future<Either<Failure, Map<String, dynamic>>> call(
    String function, {               // e.g. "auth-login" — never a REST path (FR-005)
    required String method,          // "GET" | "POST" | "PATCH" | "DELETE"
    Map<String, dynamic>? body,
    List<String>? pathSegments,      // appended in the order the OpenAPI path declares them
    AuthMode authMode = AuthMode.userSession, // or AuthMode.anonKey
  });
}

enum AuthMode { anonKey, userSession }
```

## Behavior

1. **URL construction**: `{FUNCTIONS_BASE_URL}/<function>/<pathSegments...>` — read from `.env`'s
   `FUNCTIONS_BASE_URL`. Never the OpenAPI document's REST-notation path (Principle III, FR-005).
2. **Headers, every call**: `apikey: <SUPABASE_ANON_KEY>` (from `.env`).
3. **`Authorization` header**:
   - `AuthMode.anonKey` → `Bearer <SUPABASE_ANON_KEY>` — used for `auth-signup`, `auth-login`,
     `auth-refresh` (no user session exists yet or is being replaced).
   - `AuthMode.userSession` → `Bearer <stored accessToken>` (read from `SecureTokenStorage`) — used
     for `auth-session` and every `bearerAuth` operation added by later units.
4. **Success**: returns `Right(data)` where `data` is the parsed `data` object from the response
   envelope (`{data, meta}`), discarding `meta` unless a future unit's contract says otherwise.
5. **Failure**: any non-2xx response with the `{code, message, retryable, requestId}` error body is
   passed to `ErrorMapper.fromResponse(...)` → `Left(Failure)` (see `failure-taxonomy.md`). A dio
   `DioExceptionType.connectionError`/no-response condition is mapped directly to
   `Left(NetworkOfflineFailure(...))` without a parse attempt (error-taxonomy.md: `NETWORK_OFFLINE`
   never arrives as an HTTP response). A dio timeout is mapped to `Left(NetworkTimeoutFailure(...))`.
6. **Never throws** past this boundary — every exception dio can raise is caught and mapped to a
   `Failure` before returning, satisfying FR-003 ("never an unhandled crash").

## Who depends on this

`AuthRemoteDataSource`, `SessionRemoteDataSource` (this unit) and every later unit's `*RemoteDataSource`.
