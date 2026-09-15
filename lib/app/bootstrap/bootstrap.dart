import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/filesystem/app_file_system.dart';
import '../../core/logging/app_logger.dart';
import '../app.dart';
import 'providers.dart';

Future<void> bootstrap() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize logging
  AppLogger.info(LogCategory.ui, 'Musii bootstrap starting...');

  // 3. Initialize application filesystem directories
  await AppFileSystem.instance.initialize();

  // 4. Create ProviderContainer for pre-flight state initialization
  final container = ProviderContainer();

  try {
    // 5. Initialize database
    final db = container.read(appDatabaseProvider);
    AppLogger.info(
      LogCategory.database,
      'Drift database connected (schema v${db.schemaVersion})',
    );

    // 6. Restore saved playback state and queue
    final playbackRepo = container.read(playbackRepositoryProvider);
    await playbackRepo.restoreSavedState();

    // 7. Check authenticated user session
    final authRepo = container.read(authRepositoryProvider);
    final userResult = await authRepo.getCurrentUser();
    if (userResult.isSuccess && userResult.dataOrNull != null) {
      AppLogger.info(
        LogCategory.auth,
        'Restored session for ${userResult.dataOrNull!.email}',
      );
    }
  } catch (e, st) {
    AppLogger.error(LogCategory.ui, 'Error during bootstrap sequence', e, st);
  }

  // 8. Render application
  runApp(
    UncontrolledProviderScope(container: container, child: const MusiiApp()),
  );
}
