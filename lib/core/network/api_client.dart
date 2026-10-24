import 'dart:convert';
import 'dart:typed_data';

import 'package:cerne/core/network/error_mapper.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/network/sse_frame.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fpdart/fpdart.dart';

/// Which bearer value a call carries: the anon key (no user session exists
/// yet or is being replaced) or the stored access token (an existing
/// session's authenticated calls).
enum AuthMode { anonKey, userSession }

/// The single way any feature calls the backend (FR-003, contracts/http-client.md).
/// Every `data/` layer depends on this, never on `dio` directly. Never throws
/// past this boundary — every dio exception is caught and mapped to a
/// [Failure] (FR-003 "never an unhandled crash").
class ApiClient {
  ApiClient({
    required this._dio,
    required this._tokenStorage,
    required this._anonKey,
  });

  final Dio _dio;
  final SecureTokenStorage _tokenStorage;
  final String _anonKey;

  Future<Either<Failure, Map<String, dynamic>>> call(
    String function, {
    required String method,
    Map<String, dynamic>? body,
    List<String>? pathSegments,
    Map<String, dynamic>? queryParameters,
    AuthMode authMode = AuthMode.userSession,
    // When false, returns the full decoded body (`{"data": ..., "meta":
    // ...}`) verbatim instead of unwrapping/validating the inner "data"
    // object. Needed by `entries-list`, whose "data" is an array (not an
    // object) and whose "meta.nextCursor" every other call site has no use
    // for and would otherwise be discarded. Every pre-existing call site
    // omits this and is byte-for-byte unaffected.
    bool unwrapData = true,
  }) async {
    final baseUrl = dotenv.env['FUNCTIONS_BASE_URL'] ?? '';
    final segments = [function, ...?pathSegments];
    final url = '$baseUrl/${segments.join('/')}';

    final bearer = authMode == AuthMode.anonKey
        ? _anonKey
        : (await _tokenStorage.readAccessToken() ?? '');

    try {
      final response = await _dio.request<Map<String, dynamic>>(
        url,
        data: body,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {'apikey': _anonKey, 'Authorization': 'Bearer $bearer'},
        ),
      );
      if (!unwrapData) {
        return Right(response.data ?? const {});
      }
      final rawData = response.data?['data'];
      if (rawData != null && rawData is! Map<String, dynamic>) {
        return Left(
          ValidationFailure(
            message: 'Malformed response: "data" is not an object',
            requestId: '',
          ),
        );
      }
      return Right(rawData as Map<String, dynamic>? ?? const {});
    } on DioException catch (e) {
      return Left(_mapException(e));
    }
  }

  /// A two-step fetch for an endpoint whose success response is a 302 to a
  /// signed Storage URL, not JSON (research.md R1, contracts/
  /// http-client-download-extension.md) — export-agnostic, any future
  /// signed-URL-download unit reuses it as-is. Leg 1 talks to our own
  /// backend function (same `apikey`/`Authorization` headers `call()`
  /// already sends); leg 2 is a header-less fetch of the signed URL itself,
  /// so this app's own credentials are never forwarded to a third-party
  /// Storage host (Principle III).
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
          ValidationFailure(
            message: 'Malformed response: expected a 302 redirect',
            requestId: '',
          ),
        );
      }

      final fileResponse = await _dio.request<List<int>>(
        location,
        options: Options(method: 'GET', responseType: ResponseType.bytes),
      );

      return Right(Uint8List.fromList(fileResponse.data ?? const []));
    } on DioException catch (e) {
      return Left(_mapException(e));
    }
  }

  /// Generic SSE transport (research.md R1) — knows nothing about chat
  /// specifically; any future SSE-consuming unit reuses it as-is. Never
  /// throws past this boundary: a transport failure becomes the stream's one
  /// and only `Left(Failure)` item, yielded last, then the stream closes.
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
      // A bound `Utf8Decoder` (not a per-chunk `utf8.decode`) — a
      // multi-byte character (any accented letter, routine in Portuguese
      // text) can straddle two network reads; binding it to the byte stream
      // carries an incomplete trailing sequence over to the next chunk
      // instead of mangling it into replacement characters. `allowMalformed`
      // keeps this boundary's "never throws" guarantee for truly invalid
      // bytes, same as the per-chunk decode this replaces.
      const decoder = Utf8Decoder(allowMalformed: true);
      await for (final chunk in decoder.bind(response.data!.stream)) {
        buffer.write(chunk);
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
      yield Left(_mapException(e));
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
      // Any other SSE field (id:, retry:, comments starting with ':') is
      // ignored — this backend's contract never sends them.
    }
    if (event == null) return null;
    return SseFrame(event: event, data: dataLines.join('\n'));
  }

  Failure _mapException(DioException e) {
    const timeoutTypes = {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    };

    // `e.message` is Dio's own internal exception text (e.g. "Failed host
    // lookup") — never shown to the user; both client-synthesized failures
    // below carry a fixed, user-facing message instead, same as every
    // backend-mapped `Failure` already does via `ErrorMapper`.
    if (timeoutTypes.contains(e.type)) {
      return const NetworkTimeoutFailure(
        message: 'A conexão demorou demais. Tente novamente.',
        requestId: '',
      );
    }

    final responseData = e.response?.data;
    if (responseData is Map<String, dynamic>) {
      return ErrorMapper.fromResponse(responseData);
    }

    // No response at all (connection error) — NETWORK_OFFLINE never arrives
    // as an HTTP response, so it is synthesized client-side here.
    return const NetworkOfflineFailure(
      message: 'Sem conexão com a internet.',
      requestId: '',
    );
  }
}
