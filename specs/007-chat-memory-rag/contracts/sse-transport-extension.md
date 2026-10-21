# Contract: `ApiClient.sseStream` (`lib/core/network/api_client.dart`, `lib/core/network/sse_frame.dart`)

Extends `ApiClient` (F000/RF01) in place. `call()` is unchanged. This is a `core/network/` addition, not
chat-specific — any future SSE-consuming unit reuses it as-is (research.md R1).

```dart
class SseFrame extends Equatable {
  const SseFrame({required this.event, required this.data});
  final String event;
  final String data;
  @override List<Object?> get props => [event, data];
}

extension on ApiClient {
  Stream<Either<Failure, SseFrame>> sseStream(
    String function, {
    required String method,
    Map<String, dynamic>? body,
    List<String>? pathSegments,
    AuthMode authMode = AuthMode.userSession,
  }) async* {
    final baseUrl = dotenv.env['FUNCTIONS_BASE_URL'] ?? '';
    final segments = [function, ...?pathSegments];
    final url = '$baseUrl/${segments.join('/')}';
    final bearer = authMode == AuthMode.anonKey
        ? _anonKey
        : (await _tokenStorage.readAccessToken() ?? '');

    try {
      final response = await _dio.request<ResponseBody>(
        url,
        data: body,
        options: Options(
          method: method,
          responseType: ResponseType.stream,
          headers: {'apikey': _anonKey, 'Authorization': 'Bearer $bearer'},
        ),
      );

      final buffer = StringBuffer();
      await for (final chunk in response.data!.stream) {
        buffer.write(utf8.decode(chunk, allowMalformed: true));
        var text = buffer.toString();
        while (text.contains('\n\n')) {
          final splitIndex = text.indexOf('\n\n');
          final rawFrame = text.substring(0, splitIndex);
          text = text.substring(splitIndex + 2);
          final frame = _parseFrame(rawFrame);
          if (frame != null) yield Right(frame);
        }
        buffer
          ..clear()
          ..write(text);
      }
    } on DioException catch (e) {
      yield Left(_mapException(e));   // the exact existing _mapException() call() already uses
    }
  }

  SseFrame? _parseFrame(String rawFrame) {
    String? event;
    final dataLines = <String>[];
    for (final line in rawFrame.split('\n')) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
      // any other SSE field (id:, retry:, comments starting with ':') is ignored —
      // this backend's contract never sends them (openapi.yaml's own documented sequence).
    }
    if (event == null) return null;
    return SseFrame(event: event, data: dataLines.join('\n'));
  }
}
```

- Exactly one `Left(Failure)` is ever yielded, and only as the stream's **last** item, then the stream closes
  (`async*` returning after the `yield Left(...)` inside the `catch` — no further iteration of
  `response.data!.stream` after an exception breaks out of the `await for`).
- A backend-named `error` SSE frame (a **successful** HTTP 200 stream that itself carries a business-level
  failure, per `chat.messages.send`'s summary: `message_created -> context -> token* -> done|error`) is *not*
  mapped to `Left` here — it reaches the caller as an ordinary `Right(SseFrame(event: 'error', data: ...))`,
  since only `ChatRemoteDataSource` (not the generic transport) knows that this particular backend's `error`
  event name carries the same `{code, message, retryable}` shape every other endpoint's error body does
  (data-model.md's `ChatStreamEvent` table; research.md R1/R2).
- No `unwrapData`-style parameter — SSE responses have no `{"data": ...}` envelope to unwrap; every frame's
  `data` field is handed back exactly as the backend sent it.

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | A stream with 3 frames split across 2 raw byte chunks mid-frame (simulating TCP packet boundaries) | all 3 frames parsed correctly — the buffer logic never drops/duplicates a byte across chunk boundaries |
| 2 | A `DioException` with `type: connectionTimeout` thrown mid-stream (after 1 frame already yielded) | exactly 2 items total: `Right(frame1)`, then `Left(NetworkTimeoutFailure)`; stream then closes |
| 3 | A `DioException` with no `response` at all (device goes offline mid-stream) | `Left(NetworkOfflineFailure)` as the final item |
| 4 | A frame containing only `event: context\ndata: {}` | yielded as `Right(SseFrame(event: 'context', data: '{}'))` — generic transport does not special-case any event name |
| 5 | A multi-line `data:` field (backend sends `data:` on two consecutive lines for one frame) | both lines joined with `\n` into one `SseFrame.data` string (SSE spec's own multi-line-data convention) |
