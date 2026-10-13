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
}
