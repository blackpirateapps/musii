import 'package:flutter/cupertino.dart';

abstract final class AppRadii {
  static const double small = 12.0;
  static const double card = 16.0;
  static const double artwork = 20.0;
  static const double sheet = 24.0;
  static const double circular = 999.0;

  static const BorderRadius smallRadius = BorderRadius.all(
    Radius.circular(small),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius artworkRadius = BorderRadius.all(
    Radius.circular(artwork),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

abstract final class AppSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  static const EdgeInsets edgeInsetsXs = EdgeInsets.all(xs);
  static const EdgeInsets edgeInsetsSm = EdgeInsets.all(sm);
  static const EdgeInsets edgeInsetsMd = EdgeInsets.all(md);
  static const EdgeInsets edgeInsetsLg = EdgeInsets.all(lg);
  static const EdgeInsets edgeInsetsXl = EdgeInsets.all(xl);

  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
}

abstract final class AppAudioConstants {
  static const List<String> supportedExtensions = [
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
  ];

  static const List<String> supportedMimeTypes = [
    'audio/mpeg',
    'audio/mp3',
    'audio/flac',
    'audio/x-flac',
    'audio/mp4',
    'audio/x-m4a',
    'audio/aac',
    'audio/ogg',
    'audio/opus',
    'audio/wav',
    'audio/x-wav',
  ];

  // Meaningful playback threshold: 30 seconds or 30% of song
  static const int minPlaySecondsForHistory = 30;
  static const double minPlayRatioForHistory = 0.30;

  // Cache settings (bytes)
  static const int defaultCacheSizeBytes = 5 * 1024 * 1024 * 1024; // 5 GB
  static const int minCacheSizeBytes = 500 * 1024 * 1024; // 500 MB
  static const int maxCacheSizeBytes = 50 * 1024 * 1024 * 1024; // 50 GB
}

abstract final class AppImageConstants {
  static const List<String> supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  static const List<String> supportedMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
  ];

  static const List<String> standardCoverNames = [
    'cover',
    'folder',
    'front',
    'albumart',
    'album',
    'artwork',
  ];

  static bool isImageFile(String filename, [String? mimeType]) {
    final mime = (mimeType ?? '').toLowerCase().trim();
    if (mime.startsWith('image/')) return true;
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filename.length - 1) return false;
    final ext = filename.substring(dotIndex + 1).toLowerCase().trim();
    return supportedExtensions.contains(ext);
  }
}

abstract final class AppGreeting {
  static String getGreeting([DateTime? now]) {
    final time = now ?? DateTime.now();
    final hour = time.hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good afternoon';
    } else if (hour >= 17 && hour < 21) {
      return 'Good evening';
    } else {
      return 'Good night';
    }
  }
}
