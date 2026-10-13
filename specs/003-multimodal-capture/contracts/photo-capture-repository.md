# Contract: Photo capture & recognition (`lib/features/capture/domain/`)

Mirrors audio-capture-repository.md's split, but `PhotoRecognitionRepository` is a real network
call and so reuses the existing `Failure` hierarchy unchanged (research.md R7) rather than needing
a new local-only failure type.

```dart
// lib/features/capture/domain/repositories/photo_capture_repository.dart
enum PhotoSource { camera, gallery }

abstract class PhotoCaptureRepository {
  Future<String?> pickImage(PhotoSource source);   // null == user cancelled the OS picker (Edge Cases/User Story 4)
}

// lib/features/capture/domain/repositories/photo_recognition_repository.dart
class OcrResult {
  final String text;
  final String confidence;   // "high" | "low" — carried through, never branched on (Clarification 3)
}

abstract class PhotoRecognitionRepository {
  Future<Either<Failure, OcrResult>> recognize(String imageFilePath);
}
```

- **`ImagePickerDataSource`** (`lib/features/capture/data/image_picker_data_source.dart`) is the
  only class importing `image_picker`'s `ImagePicker`/`ImageSource`/`XFile` types, always calling
  `pickImage(source: ..., imageQuality: 90)` (research.md R3) so every returned file is JPEG
  regardless of the original asset format (notably HEIC from the iOS Photos library, which
  `media-ocr`'s contract does not accept at all).
- **`MediaOcrRemoteDataSource`** (`lib/features/capture/data/media_ocr_remote_data_source.dart`)
  reads the picked file's bytes, `base64Encode`s them (`dart:convert`, no new package), and calls
  `ApiClient.call('media-ocr', method: 'POST', body: {'image': base64, 'mimeType': 'image/jpeg'})`
  (research.md R4) — reusing `ApiClient`/`ErrorMapper` unmodified. `OCR_NO_TEXT` is already a
  mapped `Failure` subtype (`OcrNoTextFailure`, present in `core/network/failure.dart` since F000)
  and is exactly the Edge Case "illegible/blank image" outcome.
- **Client-side empty-text guard**: if the backend ever answers `200` with a `text` that is empty
  or whitespace-only (rather than the `OCR_NO_TEXT` error), `PhotoRecognitionRepositoryImpl` treats
  it identically to receiving `OcrNoTextFailure` — a defensive normalization, not a new failure
  type, so `SavePhotoEntryUseCase` has exactly one "no usable text" branch to handle regardless of
  which of the two ways the backend expressed it.
- **Who depends on this**: `SavePhotoEntryUseCase` (both repositories), `InsertionModalBloc`
  (`pickImage`, to drive the Foto tab's sub-states). No `presentation/` widget calls either
  repository directly.
