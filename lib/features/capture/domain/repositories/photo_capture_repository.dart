enum PhotoSource { camera, gallery }

abstract class PhotoCaptureRepository {
  /// `null` means the user cancelled the OS picker (Edge Cases/User Story 4).
  Future<String?> pickImage(PhotoSource source);
}
