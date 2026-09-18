import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/filesystem/app_file_system.dart';
import '../../core/logging/app_logger.dart';
import '../../core/services/notification_permission_service.dart';
import '../../features/last_fm/presentation/providers/last_fm_providers.dart';
import '../../features/playback/data/repositories/playback_repository_impl.dart';
import '../app.dart';
import 'providers.dart';

Future<void> bootstrap() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  // Configure balanced in-memory image cache for smooth fast-scrolling without GC pressure
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      128 * 1024 * 1024; // 128 MB
  PaintingBinding.instance.imageCache.maximumSize = 2000;

  // 2. Initialize logging
  AppLogger.info(LogCategory.ui, 'Musii bootstrap starting...');

  // 3. Initialize application filesystem directories
  await AppFileSystem.instance.initialize();

  // 4. Request Android 13+ notification permissions
  await NotificationPermissionService.requestNotificationPermissionIfNeeded();

  // 5. Create base container for pre-flight initialization
  final preflightContainer = ProviderContainer();

  MusiiAudioHandler audioHandler;
  try {
    // 6. Initialize AudioService with native Android notification channel
    audioHandler = await AudioService.init<MusiiAudioHandler>(
      builder: () => MusiiAudioHandler(
        cacheRepository: preflightContainer.read(cacheRepositoryProvider),
        recentlyPlayedRepository: preflightContainer.read(
          recentlyPlayedRepositoryProvider,
        ),
        database: preflightContainer.read(appDatabaseProvider),
        connectivityService: preflightContainer.read(
          connectivityServiceProvider,
        ),
        lastFmCoordinator: preflightContainer.read(
          lastFmPlaybackCoordinatorProvider,
        ),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.blackpirateapps.musii.channel.audio',
        androidNotificationChannelName: 'Musii Audio Playback',
        androidNotificationChannelDescription:
            'Musii music playback controls and media notification',
        androidNotificationIcon: 'drawable/ic_stat_music',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: true,
        androidNotificationClickStartsActivity: true,
      ),
    );
    AppLogger.info(
      LogCategory.playback,
      'AudioService initialized with Android notification channel and media session',
    );
  } catch (e, st) {
    AppLogger.warning(
      LogCategory.playback,
      'AudioService.init not available (running in test or host environment), using local handler fallback',
      e,
      st,
    );
    audioHandler = MusiiAudioHandler(
      cacheRepository: preflightContainer.read(cacheRepositoryProvider),
      recentlyPlayedRepository: preflightContainer.read(
        recentlyPlayedRepositoryProvider,
      ),
      database: preflightContainer.read(appDatabaseProvider),
      connectivityService: preflightContainer.read(connectivityServiceProvider),
      lastFmCoordinator: preflightContainer.read(
        lastFmPlaybackCoordinatorProvider,
      ),
    );
  }

  // 7. Create root ProviderContainer with platform-bound AudioHandler
  final rootContainer = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(
        preflightContainer.read(appDatabaseProvider),
      ),
      musiiAudioHandlerProvider.overrideWithValue(audioHandler),
    ],
  );

  // Link audio handler to root container coordinator
  audioHandler.lastFmCoordinator = rootContainer.read(
    lastFmPlaybackCoordinatorProvider,
  );

  // Start background Last.fm connectivity sync watcher
  rootContainer.read(lastFmSyncServiceProvider);

  try {
    // 8. Log database connection
    final db = rootContainer.read(appDatabaseProvider);
    AppLogger.info(
      LogCategory.database,
      'Drift database connected (schema v${db.schemaVersion})',
    );

    // 9. Restore saved playback state and queue
    final playbackRepo = rootContainer.read(playbackRepositoryProvider);
    await playbackRepo.restoreSavedState();

    // 10. Check authenticated user session
    final authRepo = rootContainer.read(authRepositoryProvider);
    final userResult = await authRepo.getCurrentUser();
    if (userResult.isSuccess && userResult.dataOrNull != null) {
      AppLogger.info(
        LogCategory.auth,
        'Restored session for ${userResult.dataOrNull!.email}',
      );
    }

    // 11. Check for interrupted sync and auto-resume
    final libraryRepo = rootContainer.read(musicLibraryRepositoryProvider);
    unawaited(libraryRepo.recoverInterruptedSyncIfNeeded());
  } catch (e, st) {
    AppLogger.error(LogCategory.ui, 'Error during bootstrap sequence', e, st);
  }

  // 12. Render application
  runApp(
    UncontrolledProviderScope(
      container: rootContainer,
      child: const MusiiApp(),
    ),
  );
}
