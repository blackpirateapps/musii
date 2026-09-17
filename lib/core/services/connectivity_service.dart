import 'package:connectivity_plus/connectivity_plus.dart';

import '../logging/app_logger.dart';

/// Service responsible for monitoring and checking network connectivity types.
class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  /// Returns `true` if connected via Wi-Fi or Ethernet.
  Future<bool> isWifiConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.cache,
        'Could not evaluate network connectivity',
        e,
        st,
      );
      return false;
    }
  }

  /// Returns `true` if any internet connection is active (wifi, mobile, ethernet, vpn, etc.).
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.cache,
        'Could not evaluate online connectivity',
        e,
        st,
      );
      return false;
    }
  }

  /// Broadcast stream of connectivity changes.
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

}
