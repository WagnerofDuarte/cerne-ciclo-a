import 'package:cerne/core/network/error_mapper.dart';
import 'package:cerne/core/network/failure.dart';
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
