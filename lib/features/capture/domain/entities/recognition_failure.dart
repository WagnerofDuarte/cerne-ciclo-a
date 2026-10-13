/// A purely local, on-device recognition condition with no corresponding
/// backend code — deliberately not a `core/network/failure.dart` subtype
/// (research.md R7).
sealed class RecognitionFailure {
  const RecognitionFailure();
}

/// The transcript was empty or whitespace-only after `.trim()`.
class EmptyRecognitionResult extends RecognitionFailure {
  const EmptyRecognitionResult();
}

/// `whisper_ggml` threw, or the model failed to load.
class TranscriptionError extends RecognitionFailure {
  const TranscriptionError();
}
