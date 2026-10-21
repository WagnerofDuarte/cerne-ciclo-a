import 'package:connectivity_plus/connectivity_plus.dart';

/// Interface-level online/offline check (research.md R5) — lives in `core/`,
/// not inside `capture/`, because later offline-gated units (RF04, RF06)
/// reuse this exact checker. Reports OS-level interface state (Wi-Fi/
/// cellular/none), not actual internet reachability — an accepted
/// limitation (research.md R5).
class ConnectivityChecker {
  ConnectivityChecker({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  /// Live connectivity transitions (research.md R8) — layered on top of,
  /// never replacing, [hasConnection]'s own synchronous pre-check. Maps "any
  /// result `!= ConnectivityResult.none`" to `true`, the exact predicate
  /// [hasConnection] already uses.
  Stream<bool> get onConnectivityChanged => _connectivity.onConnectivityChanged
      .map((results) => results.any((result) => result != ConnectivityResult.none));
}
