import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/capture/data/media_ocr_remote_data_source.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Reuses `ApiClient`/`ErrorMapper` unmodified. `OCR_NO_TEXT` is already a
/// mapped `Failure` subtype (`OcrNoTextFailure`, present since F000); a
/// client-side guard treats a `200` response whose `text` is blank
/// identically — a defensive normalization, not a new failure type
/// (contracts/photo-capture-repository.md).
class PhotoRecognitionRepositoryImpl implements PhotoRecognitionRepository {
  const PhotoRecognitionRepositoryImpl(this._remote);

  final MediaOcrRemoteDataSource _remote;

  @override
  Future<Either<Failure, OcrResult>> recognize(String imageFilePath) async {
    final result = await _remote.recognize(imageFilePath);
    return result.flatMap(_parseResult);
  }

  Either<Failure, OcrResult> _parseResult(Map<String, dynamic> data) {
    try {
      final text = data['text'] as String;
      final confidence = data['confidence'] as String;
      if (text.trim().isEmpty) {
        return const Left(
          OcrNoTextFailure(message: 'No text recognized', requestId: ''),
        );
      }
      return Right(OcrResult(text: text, confidence: confidence));
    } on TypeError {
      return const Left(
        ValidationFailure(message: 'Malformed media-ocr response', requestId: ''),
      );
    }
  }
}
