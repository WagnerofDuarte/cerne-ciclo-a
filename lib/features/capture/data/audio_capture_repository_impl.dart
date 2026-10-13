import 'dart:async';

import 'package:cerne/features/capture/data/audio_recorder_data_source.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';

const _amplitudePollInterval = Duration(milliseconds: 100);

/// Maps [AudioRecorderDataSource]/`record` results to plain
/// `bool`/`String`/`Stream<double>` before they reach `domain/` (RNF06).
class AudioCaptureRepositoryImpl implements AudioCaptureRepository {
  AudioCaptureRepositoryImpl(this._dataSource);

  final AudioRecorderDataSource _dataSource;

  @override
  Future<bool> hasPermission() => _dataSource.hasPermission();

  @override
  Future<void> start() => _dataSource.start();

  @override
  Stream<double> get amplitudeStream =>
      _dataSource.onAmplitudeChanged(_amplitudePollInterval);

  @override
  Future<String> stop() async => (await _dataSource.stop()) ?? '';

  @override
  void discard() {
    unawaited(_dataSource.cancel());
  }
}
