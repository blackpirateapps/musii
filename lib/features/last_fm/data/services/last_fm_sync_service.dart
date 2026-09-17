import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../domain/repositories/last_fm_repository.dart';

class LastFmSyncService {
  final LastFmRepository _repository;
  final ConnectivityService _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  LastFmSyncService({
    required LastFmRepository repository,
    required ConnectivityService connectivity,
  })  : _repository = repository,
        _connectivity = connectivity;

  void start() {
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        _scheduleSync();
      }
    });

    // Check immediately on start
    _scheduleSync(delay: const Duration(seconds: 2));
  }

  void _scheduleSync({Duration delay = const Duration(seconds: 1)}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () async {
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        final pendingCount = await _repository.getPendingCount();
        if (pendingCount > 0) {
          AppLogger.info(
            LogCategory.lastFm,
            'Connectivity restored/active with $pendingCount pending scrobble(s); synchronizing...',
          );
          await _repository.syncPendingScrobbles();
        }
      } catch (e, st) {
        AppLogger.warning(
          LogCategory.lastFm,
          'Error during background scrobble sync',
          e,
          st,
        );
      } finally {
        _isSyncing = false;
      }
    });
  }

  void dispose() {
    _debounceTimer?.cancel();
    _connectivitySub?.cancel();
  }
}
