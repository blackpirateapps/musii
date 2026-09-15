import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

class AppFileSystem {
  static AppFileSystem? _instance;
  static AppFileSystem get instance => _instance ??= AppFileSystem._();

  AppFileSystem._();

  late final Directory _appSupportDir;
  late final Directory _audioCacheDir;
  late final Directory _artworkCacheDir;
  late final Directory _tempDir;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Directory get audioCacheDir => _audioCacheDir;
  Directory get artworkCacheDir => _artworkCacheDir;
  Directory get tempDir => _tempDir;

  Future<void> initialize({Directory? baseDir}) async {
    if (_initialized) return;

    if (baseDir != null) {
      _appSupportDir = baseDir;
    } else {
      _appSupportDir = await getApplicationSupportDirectory();
    }

    _audioCacheDir = Directory(p.join(_appSupportDir.path, 'audio_cache'));
    _artworkCacheDir = Directory(p.join(_appSupportDir.path, 'artwork_cache'));
    _tempDir = Directory(p.join(_appSupportDir.path, 'temp_files'));

    await _audioCacheDir.create(recursive: true);
    await _artworkCacheDir.create(recursive: true);
    await _tempDir.create(recursive: true);

    _initialized = true;

    // Clean up any stale partial files left over from prior runs
    await cleanOrphanedPartialFiles();

    AppLogger.info(
      LogCategory.cache,
      'FileSystem initialized: Audio cache at ${_audioCacheDir.path}',
    );
  }

  File getAudioCacheFile(String trackId, String extension) {
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return File(p.join(_audioCacheDir.path, '$trackId$ext'));
  }

  File getPartialAudioCacheFile(String trackId, String extension) {
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return File(p.join(_audioCacheDir.path, '$trackId$ext.partial'));
  }

  File getArtworkCacheFile(String key) {
    return File(p.join(_artworkCacheDir.path, '$key.jpg'));
  }

  File getTempMetadataFile(String filename) {
    return File(p.join(_tempDir.path, filename));
  }

  Future<File> atomicCommitFile(File partialFile, File targetFile) async {
    if (!await partialFile.exists()) {
      throw FileSystemException(
        'Partial file does not exist',
        partialFile.path,
      );
    }

    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    // Atomic rename
    return await partialFile.rename(targetFile.path);
  }

  Future<void> cleanOrphanedPartialFiles() async {
    try {
      if (await _audioCacheDir.exists()) {
        final entries = _audioCacheDir.listSync();
        for (final entry in entries) {
          if (entry is File && entry.path.endsWith('.partial')) {
            try {
              await entry.delete();
              AppLogger.debug(
                LogCategory.cache,
                'Cleaned orphaned partial file: ${entry.path}',
              );
            } catch (e) {
              AppLogger.warning(
                LogCategory.cache,
                'Failed to delete orphaned partial file: ${entry.path}',
                e,
              );
            }
          }
        }
      }

      if (await _tempDir.exists()) {
        final tempEntries = _tempDir.listSync();
        for (final entry in tempEntries) {
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.warning(
        LogCategory.cache,
        'Error during orphaned files cleanup',
        e,
      );
    }
  }

  Future<int> getAudioCacheSizeBytes() async {
    if (!await _audioCacheDir.exists()) return 0;
    int total = 0;
    final entries = _audioCacheDir.listSync(recursive: true);
    for (final entry in entries) {
      if (entry is File && !entry.path.endsWith('.partial')) {
        total += await entry.length();
      }
    }
    return total;
  }
}
