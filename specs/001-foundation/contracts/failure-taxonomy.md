# Contract: `Failure` (`lib/core/network/failure.dart`)

The typed failure every repository's `Either<Failure, T>` resolves to on the `Left` side
(RNF09, FR-004). Domain-layer code only — no Flutter import.

```dart
sealed class Failure extends Equatable {
  const Failure({required this.message, required this.requestId});
  final String message;
  final String requestId;
  bool get retryable;
  String get code;
  @override
  List<Object?> get props => [code, message, requestId];
}

class AuthExpiredFailure extends Failure { bool get retryable => false; String get code => 'AUTH_EXPIRED'; }
class AuthInvalidFailure extends Failure { bool get retryable => false; String get code => 'AUTH_INVALID'; }
class NetworkTimeoutFailure extends Failure { bool get retryable => true;  String get code => 'NETWORK_TIMEOUT'; }
class NetworkOfflineFailure extends Failure { bool get retryable => true;  String get code => 'NETWORK_OFFLINE'; }
class ValidationFailure extends Failure { bool get retryable => false; String get code => 'VALIDATION_ERROR'; }
class PiiCheckFailedFailure extends Failure { bool get retryable => true;  String get code => 'PII_CHECK_FAILED'; }
class EmbeddingFailedFailure extends Failure { bool get retryable => true;  String get code => 'EMBEDDING_FAILED'; }
class AiGenerationTimeoutFailure extends Failure { bool get retryable => true;  String get code => 'AI_GENERATION_TIMEOUT'; }
class NotFoundFailure extends Failure { bool get retryable => false; String get code => 'NOT_FOUND'; }
class RateLimitedFailure extends Failure { bool get retryable => true;  String get code => 'RATE_LIMITED'; }
class ExportEmptyPeriodFailure extends Failure { bool get retryable => false; String get code => 'EXPORT_EMPTY_PERIOD'; }
class PayloadTooLargeFailure extends Failure { bool get retryable => false; String get code => 'PAYLOAD_TOO_LARGE'; }
class OcrNoTextFailure extends Failure { bool get retryable => false; String get code => 'OCR_NO_TEXT'; }
```

`ErrorMapper.fromResponse(Map<String, dynamic> body)` performs the exhaustive `code` → subtype
switch; an unrecognized `code` is a contract violation (the taxonomy is closed per
error-taxonomy.md) and is treated as a defensive `ValidationFailure` rather than thrown, keeping
FR-003's "never an unhandled crash" guarantee even against a future backend regression.

## Who depends on this

Every repository in every feature, present and future. UI code branches on `failure.retryable` to
choose a retry affordance vs. a terminal error message (FR-004, FR-015), and on `runtimeType` (or a
`when`/`switch` pattern) to choose the exact message shown — F000's own screens only branch on
`AuthExpiredFailure`, `AuthInvalidFailure`, `NetworkTimeoutFailure`, `NetworkOfflineFailure`,
`ValidationFailure`, `RateLimitedFailure`; the other seven are reachable only from endpoints later
units add.
