import 'dart:convert';
import 'dart:io';

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// Reads the picked file's bytes, base64-encodes them, and calls
/// `media-ocr` (research.md R4) — reusing `ApiClient` unmodified.
class MediaOcrRemoteDataSource {
  const MediaOcrRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, Map<String, dynamic>>> recognize(
    String imageFilePath,
  ) async {
    final bytes = await File(imageFilePath).readAsBytes();
    final base64Image = base64Encode(bytes);
    return _apiClient.call(
      'media-ocr',
      method: 'POST',
      body: {'image': base64Image, 'mimeType': 'image/jpeg'},
    );
  }
}
