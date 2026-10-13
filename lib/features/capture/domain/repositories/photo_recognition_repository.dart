import 'package:cerne/core/network/failure.dart';
import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

class OcrResult extends Equatable {
  const OcrResult({required this.text, required this.confidence});

  final String text;

  /// "high" | "low" — carried through, never branched on (Clarification 3).
  final String confidence;

  @override
  List<Object?> get props => [text, confidence];
}

/// A real network call to `media-ocr` — reuses the existing `Failure`
/// hierarchy unchanged (research.md R7), unlike `AudioTranscriptionRepository`.
abstract class PhotoRecognitionRepository {
  Future<Either<Failure, OcrResult>> recognize(String imageFilePath);
}
