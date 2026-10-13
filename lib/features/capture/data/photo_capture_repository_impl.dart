import 'package:cerne/features/capture/data/image_picker_data_source.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';

class PhotoCaptureRepositoryImpl implements PhotoCaptureRepository {
  const PhotoCaptureRepositoryImpl(this._dataSource);

  final ImagePickerDataSource _dataSource;

  @override
  Future<String?> pickImage(PhotoSource source) => _dataSource.pickImage(source);
}
