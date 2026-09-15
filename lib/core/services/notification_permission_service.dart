import 'package:permission_handler/permission_handler.dart';

import '../logging/app_logger.dart';

/// Service responsible for managing Android 13+ (API 33+) notification permissions.
class NotificationPermissionService {
  const NotificationPermissionService();

  /// Requests notification permission if it has not been granted yet.
  /// Returns `true` if permission is granted, `false` otherwise.
  static Future<bool> requestNotificationPermissionIfNeeded() async {
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        return true;
      }

      if (status.isDenied || status.isProvisional) {
        AppLogger.info(
          LogCategory.playback,
          'Requesting notification permission from user...',
        );
        final result = await Permission.notification.request();
        AppLogger.info(
          LogCategory.playback,
          'Notification permission result: $result',
        );
        return result.isGranted;
      }

      return status.isGranted;
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.playback,
        'Could not evaluate notification permission',
        e,
        st,
      );
      return false;
    }
  }

  /// Checks if notification permission is currently granted.
  static Future<bool> isNotificationPermissionGranted() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Opens application settings if the user previously permanently denied permissions.
  static Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      return false;
    }
  }
}
