import 'package:equatable/equatable.dart';

/// The typed failure every repository's `Either<Failure, T>` resolves to on
/// the `Left` side (RNF09, FR-004). Covers all 13 of the backend's closed
/// error codes (contracts/failure-taxonomy.md) — domain-layer only, no
/// `package:flutter` import (RNF06).
sealed class Failure extends Equatable {
  const Failure({required this.message, required this.requestId});

  final String message;
  final String requestId;

  bool get retryable;
  String get code;

  @override
  List<Object?> get props => [code, message, requestId];
}

class AuthExpiredFailure extends Failure {
  const AuthExpiredFailure({required super.message, required super.requestId});

  @override
  bool get retryable => false;

  @override
  String get code => 'AUTH_EXPIRED';
}

class AuthInvalidFailure extends Failure {
  const AuthInvalidFailure({required super.message, required super.requestId});

  @override
  bool get retryable => false;

  @override
  String get code => 'AUTH_INVALID';
}

class NetworkTimeoutFailure extends Failure {
  const NetworkTimeoutFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => true;

  @override
  String get code => 'NETWORK_TIMEOUT';
}

class NetworkOfflineFailure extends Failure {
  const NetworkOfflineFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => true;

  @override
  String get code => 'NETWORK_OFFLINE';
}

class ValidationFailure extends Failure {
  const ValidationFailure({required super.message, required super.requestId});

  @override
  bool get retryable => false;

  @override
  String get code => 'VALIDATION_ERROR';
}

class PiiCheckFailedFailure extends Failure {
  const PiiCheckFailedFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => true;

  @override
  String get code => 'PII_CHECK_FAILED';
}

class EmbeddingFailedFailure extends Failure {
  const EmbeddingFailedFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => true;

  @override
  String get code => 'EMBEDDING_FAILED';
}

class AiGenerationTimeoutFailure extends Failure {
  const AiGenerationTimeoutFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => true;

  @override
  String get code => 'AI_GENERATION_TIMEOUT';
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({required super.message, required super.requestId});

  @override
  bool get retryable => false;

  @override
  String get code => 'NOT_FOUND';
}

class RateLimitedFailure extends Failure {
  const RateLimitedFailure({required super.message, required super.requestId});

  @override
  bool get retryable => true;

  @override
  String get code => 'RATE_LIMITED';
}

class ExportEmptyPeriodFailure extends Failure {
  const ExportEmptyPeriodFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => false;

  @override
  String get code => 'EXPORT_EMPTY_PERIOD';
}

class PayloadTooLargeFailure extends Failure {
  const PayloadTooLargeFailure({
    required super.message,
    required super.requestId,
  });

  @override
  bool get retryable => false;

  @override
  String get code => 'PAYLOAD_TOO_LARGE';
}

class OcrNoTextFailure extends Failure {
  const OcrNoTextFailure({required super.message, required super.requestId});

  @override
  bool get retryable => false;

  @override
  String get code => 'OCR_NO_TEXT';
}
