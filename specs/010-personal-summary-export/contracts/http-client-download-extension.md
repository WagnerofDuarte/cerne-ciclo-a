# Contract: `ApiClient.downloadFile` (`lib/core/network/api_client.dart`)

Extends `ApiClient` (F000/RF01, already extended by RF04's `sseStream()`) in place. `call()`/`sseStream()` are
unchanged. This is a `core/network/` addition, not export-specific — any future signed-URL-download unit
reuses it as-is (research.md R1).

```dart
Future<Either<Failure, Uint8List>> downloadFile(
  String function, {
  List<String>? pathSegments,
  Map<String, dynamic>? queryParameters,
  AuthMode authMode = AuthMode.userSession,
}) async {
  final baseUrl = dotenv.env['FUNCTIONS_BASE_URL'] ?? '';
  final segments = [function, ...?pathSegments];
  final url = '$baseUrl/${segments.join('/')}';
  final bearer = authMode == AuthMode.anonKey
      ? _anonKey
      : (await _tokenStorage.readAccessToken() ?? '');

  try {
    // Leg 1 — our own backend function. Same apikey/Authorization headers every other `call()` already
    // sends. `followRedirects: false` + accepting <400 via `validateStatus` means a 302 lands here as a
    // normal response object instead of being auto-followed (which would forward these headers to Storage).
    final redirectResponse = await _dio.request<void>(
      url,
      queryParameters: queryParameters,
      options: Options(
        method: 'GET',
        headers: {'apikey': _anonKey, 'Authorization': 'Bearer $bearer'},
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final location = redirectResponse.headers.value('location');
    if (redirectResponse.statusCode != 302 || location == null) {
      return const Left(
        ValidationFailure(message: 'Malformed response: expected a 302 redirect', requestId: ''),
      );
    }

    // Leg 2 — the signed Storage URL. Deliberately NO apikey/Authorization headers: the signed URL already
    // carries its own short-lived auth via query parameters, and forwarding this app's own credentials to a
    // third-party host they were never scoped for is an unnecessary exposure (research.md R1).
    final fileResponse = await _dio.request<List<int>>(
      location,
      options: Options(method: 'GET', responseType: ResponseType.bytes),
    );

    return Right(Uint8List.fromList(fileResponse.data ?? const []));
  } on DioException catch (e) {
    // Leg 1 failures (our backend's own {code, message, retryable} envelope) map through the exact same
    // `_mapException` every other call() site already uses. Leg 2 failures (the storage host never speaks
    // this app's error envelope — a 403/404 from an expired signed URL, a dropped connection mid-download)
    // have no `{code, message, retryable}` body to parse, so they fall through `_mapException`'s own
    // no-JSON-body branch and resolve to the same retryable `NetworkOfflineFailure`/`NetworkTimeoutFailure`
    // it already synthesizes for a connection-level failure — never a new, undocumented Failure subtype.
    return Left(_mapException(e));
  }
}
```

- Exactly two network round-trips per call, in sequence — never more (no following of a second redirect; a
  Storage response that itself redirects again is treated as leg 2's own non-2xx failure via `_mapException`,
  since `_dio.request<List<int>>` here keeps `dio`'s default `followRedirects: true` only for leg 2, where no
  credential is being forwarded in the first place, so a further redirect being auto-followed is harmless).
- No `unwrapData`-style parameter and no `body` parameter — `GET /export/{jobId}/download` takes no request
  body, and the return shape is always raw bytes, never a `{"data": ...}` JSON envelope.

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | Leg 1 returns `302` with a valid `location` header; leg 2 returns `200` with bytes | `Right(Uint8List)` containing exactly those bytes |
| 2 | Leg 1 returns `200` (no redirect at all — a contract-violating response) | `Left(ValidationFailure)` |
| 3 | Leg 1 returns `302` with no `location` header | `Left(ValidationFailure)` |
| 4 | Leg 1 throws a `DioException` with `{code: 'AUTH_EXPIRED', ...}` in its response body | `Left(AuthExpiredFailure)` — identical mapping to `call()`'s own `AUTH_EXPIRED` handling |
| 5 | Leg 1 succeeds (302 + location); leg 2 throws a `DioException` with `type: connectionTimeout` | `Left(NetworkTimeoutFailure)` — the storage-leg failure, not confused with a leg-1 failure |
| 6 | Leg 1 succeeds; leg 2 throws a `DioException` with no `response` at all (expired/garbage signed URL rejected at the transport level) | `Left(NetworkOfflineFailure)` |
| 7 | `downloadFile` called with `queryParameters: {'format': 'raw'}` | leg 1's request URL carries `?format=raw` verbatim |
