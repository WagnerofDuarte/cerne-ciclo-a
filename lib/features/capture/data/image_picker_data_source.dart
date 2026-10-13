import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:image_picker/image_picker.dart';

/// The only class importing `image_picker`'s `ImagePicker`/`ImageSource`/
/// `XFile` types. Always calls with `imageQuality: 90` (research.md R3) so
/// every returned file is JPEG regardless of the original asset format —
/// notably HEIC from the iOS Photos library, which `media-ocr`'s contract
/// does not accept at all.
class ImagePickerDataSource {
  ImagePickerDataSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<String?> pickImage(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 90,
    );
    return file?.path;
  }
}
