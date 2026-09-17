import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/storage/secure_credential_store.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../data/datasources/last_fm_api_client.dart';
import '../../data/repositories/last_fm_repository_impl.dart';
import '../../data/services/last_fm_playback_coordinator.dart';
import '../../data/services/last_fm_sync_service.dart';
import '../../domain/entities/last_fm_account.dart';
import '../../domain/entities/pending_scrobble.dart';
import '../../domain/entities/scrobble_history_item.dart';
import '../../domain/entities/scrobble_settings.dart';
import '../../domain/repositories/last_fm_repository.dart';

final secureCredentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  return FlutterSecureCredentialStore();
});

final lastFmApiClientProvider = Provider<LastFmApiClient>((ref) {
  return LastFmApiClient();
});

final lastFmRepositoryProvider = Provider<LastFmRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final store = ref.watch(secureCredentialStoreProvider);
  final client = ref.watch(lastFmApiClientProvider);
  final conn = ref.watch(connectivityServiceProvider);

  return LastFmRepositoryImpl(
    database: db,
    credentialStore: store,
    apiClient: client,
    connectivity: conn,
  );
});

final lastFmAccountProvider = StreamProvider<LastFmAccount?>((ref) {
  final repo = ref.watch(lastFmRepositoryProvider);
  return repo.watchAccount();
});

final lastFmSettingsProvider = StreamProvider<ScrobbleSettings>((ref) {
  final repo = ref.watch(lastFmRepositoryProvider);
  return repo.watchSettings();
});

final lastFmPendingScrobblesProvider = StreamProvider<List<PendingScrobble>>((
  ref,
) {
  final repo = ref.watch(lastFmRepositoryProvider);
  return repo.watchPendingScrobbles();
});

final lastFmScrobbleHistoryProvider = StreamProvider<List<ScrobbleHistoryItem>>(
  (ref) {
    final repo = ref.watch(lastFmRepositoryProvider);
    return repo.watchScrobbleHistory();
  },
);

final lastFmPlaybackCoordinatorProvider = Provider<LastFmPlaybackCoordinator>((
  ref,
) {
  final repo = ref.watch(lastFmRepositoryProvider);
  final coordinator = LastFmPlaybackCoordinator(repository: repo);
  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});

final lastFmSyncServiceProvider = Provider<LastFmSyncService>((ref) {
  final repo = ref.watch(lastFmRepositoryProvider);
  final conn = ref.watch(connectivityServiceProvider);
  final service = LastFmSyncService(repository: repo, connectivity: conn);
  service.start();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Streams transient track scrobble events with 3-second auto-clear.
final lastScrobbledTrackProvider = StreamProvider<Track?>((ref) {
  final coordinator = ref.watch(lastFmPlaybackCoordinatorProvider);
  final controller = StreamController<Track?>();
  Timer? clearTimer;

  final sub = coordinator.onScrobbleSuccess.listen((track) {
    controller.add(track);
    clearTimer?.cancel();
    clearTimer = Timer(const Duration(seconds: 3), () {
      if (!controller.isClosed) {
        controller.add(null);
      }
    });
  });

  ref.onDispose(() {
    clearTimer?.cancel();
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
