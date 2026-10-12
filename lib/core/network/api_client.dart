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
    AuthMode authMode = AuthMode.userSession,
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
        options: Options(
          method: method,
          headers: {'apikey': _anonKey, 'Authorization': 'Bearer $bearer'},
        ),
      );
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

    if (timeoutTypes.contains(e.type)) {
      return NetworkTimeoutFailure(
        message: e.message ?? 'Request timed out',
        requestId: '',
      );
    }

    final responseData = e.response?.data;
    if (responseData is Map<String, dynamic>) {
      return ErrorMapper.fromResponse(responseData);
    }

    // No response at all (connection error) — NETWORK_OFFLINE never arrives
    // as an HTTP response, so it is synthesized client-side here.
    return NetworkOfflineFailure(
      message: e.message ?? 'No connection',
      requestId: '',
    );
  }
}
