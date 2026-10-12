import 'package:cerne/core/network/failure.dart';

/// Maps a backend error response body (`{code, message, retryable,
/// requestId}`) to its typed [Failure] subtype. An unrecognized `code` MUST
/// NOT throw — it is mapped to a defensive [ValidationFailure] instead
/// (contracts/failure-taxonomy.md; FR-003 "never an unhandled crash").
class ErrorMapper {
  const ErrorMapper._();

  static Failure fromResponse(Map<String, dynamic> body) {
    final code = body['code'] as String?;
    final message = body['message'] as String? ?? 'Unknown error';
    final requestId = body['requestId'] as String? ?? '';

    return switch (code) {
      'AUTH_EXPIRED' => AuthExpiredFailure(message: message, requestId: requestId),
      'AUTH_INVALID' => AuthInvalidFailure(message: message, requestId: requestId),
      'NETWORK_TIMEOUT' => NetworkTimeoutFailure(message: message, requestId: requestId),
      'NETWORK_OFFLINE' => NetworkOfflineFailure(message: message, requestId: requestId),
      'VALIDATION_ERROR' => ValidationFailure(message: message, requestId: requestId),
      'PII_CHECK_FAILED' => PiiCheckFailedFailure(message: message, requestId: requestId),
      'EMBEDDING_FAILED' => EmbeddingFailedFailure(message: message, requestId: requestId),
      'AI_GENERATION_TIMEOUT' => AiGenerationTimeoutFailure(message: message, requestId: requestId),
      'NOT_FOUND' => NotFoundFailure(message: message, requestId: requestId),
      'RATE_LIMITED' => RateLimitedFailure(message: message, requestId: requestId),
      'EXPORT_EMPTY_PERIOD' => ExportEmptyPeriodFailure(message: message, requestId: requestId),
      'PAYLOAD_TOO_LARGE' => PayloadTooLargeFailure(message: message, requestId: requestId),
      'OCR_NO_TEXT' => OcrNoTextFailure(message: message, requestId: requestId),
      _ => ValidationFailure(message: message, requestId: requestId),
    };
  }
}
