import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

class AppFileSystem {
  static AppFileSystem? _instance;
  static AppFileSystem get instance => _instance ??= AppFileSystem._();

  AppFileSystem._();

  late Directory _appSupportDir;
  late Directory _audioCacheDir;
  late Directory _artworkCacheDir;
  late Directory _tempDir;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  void _ensureInitialized() {
    if (_initialized) return;
    _appSupportDir = Directory.systemTemp.createTempSync('musii_temp_');
    _audioCacheDir = Directory(p.join(_appSupportDir.path, 'audio_cache'))
      ..createSync(recursive: true);
    _artworkCacheDir = Directory(p.join(_appSupportDir.path, 'artwork_cache'))
      ..createSync(recursive: true);
    _tempDir = Directory(p.join(_appSupportDir.path, 'temp_files'))
      ..createSync(recursive: true);
    _initialized = true;
  }

  Directory get audioCacheDir {
    _ensureInitialized();
    return _audioCacheDir;
  }

  Directory get artworkCacheDir {
    _ensureInitialized();
    return _artworkCacheDir;
  }

  Directory get tempDir {
    _ensureInitialized();
    return _tempDir;
  }

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
    return File(p.join(audioCacheDir.path, '$trackId$ext'));
  }

  File getPartialAudioCacheFile(String trackId, String extension) {
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return File(p.join(audioCacheDir.path, '$trackId$ext.partial'));
  }

  File getArtworkCacheFile(String key) {
    return File(p.join(artworkCacheDir.path, '$key.jpg'));
  }

  File getTempMetadataFile(String filename) {
    return File(p.join(tempDir.path, filename));
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
      if (await audioCacheDir.exists()) {
        final entries = audioCacheDir.listSync();
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

      if (await tempDir.exists()) {
        final tempEntries = tempDir.listSync();
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
    if (!await audioCacheDir.exists()) return 0;
    int total = 0;
    final entries = audioCacheDir.listSync(recursive: true);
    for (final entry in entries) {
      if (entry is File && !entry.path.endsWith('.partial')) {
        total += await entry.length();
      }
    }
    return total;
  }
}
