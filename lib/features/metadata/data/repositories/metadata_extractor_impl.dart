import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:path/path.dart' as p;

import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/parsed_audio_metadata.dart';
import '../../domain/services/metadata_normalization_service.dart';

class MetadataExtractor {
  final AppFileSystem _fileSystem;

  MetadataExtractor({AppFileSystem? fileSystem})
    : _fileSystem = fileSystem ?? AppFileSystem.instance;

  Future<ParsedAudioMetadata> extractFromFile(
    File file, {
    String? fallbackName,
    int? knownFileSize,
  }) async {
    final fileName = fallbackName ?? p.basename(file.path);
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final fileSize =
        knownFileSize ?? (await file.exists() ? await file.length() : 0);

    try {
      final meta = amr.readMetadata(file, getImage: true);

      Uint8List? artworkBytes;
      if (meta.pictures.isNotEmpty) {
        artworkBytes = meta.pictures.first.bytes;
      }

      final durationMs = meta.duration?.inMilliseconds ?? 0;
      final year = meta.year?.year;

      final parsed = ParsedAudioMetadata(
        title: (meta.title != null && meta.title!.trim().isNotEmpty)
            ? meta.title!.trim()
            : MetadataNormalizationService.cleanFilename(fileName),
        artist: meta.artist?.trim(),
        album: meta.album?.trim(),
        albumArtist: meta.albumArtist?.trim(),
        genre: meta.genres.isNotEmpty ? meta.genres.first : null,
        year: year,
        trackNumber: meta.trackNumber,
        discNumber: meta.discNumber,
        durationMs: durationMs,
        bitrate: meta.bitrate,
        sampleRate: meta.sampleRate,
        format: ext.toUpperCase(),
        fileSize: fileSize,
        artworkBytes: artworkBytes,
        rawMetadata: {
          'title': meta.title,
          'artist': meta.artist,
          'album': meta.album,
          'albumArtist': meta.albumArtist,
          'durationMs': durationMs,
          'trackNumber': meta.trackNumber,
          'discNumber': meta.discNumber,
          'year': year,
          'bitrate': meta.bitrate,
          'sampleRate': meta.sampleRate,
        },
      );

      // Save artwork if available
      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        await _saveArtworkIfNew(parsed.album, parsed.artist, artworkBytes);
      }

      return parsed;
    } catch (e) {
      AppLogger.warning(
        LogCategory.metadata,
        'Metadata extraction warning for $fileName; using filename fallback',
        e,
      );

      return ParsedAudioMetadata(
        title: MetadataNormalizationService.cleanFilename(fileName),
        format: ext.toUpperCase(),
        fileSize: fileSize,
      );
    }
  }

  Future<String?> _saveArtworkIfNew(
    String? album,
    String? artist,
    Uint8List artworkBytes,
  ) async {
    try {
      final artworkKey = MetadataNormalizationService.computeArtworkKey(
        album,
        artist,
      );
      final artworkFile = _fileSystem.getArtworkCacheFile(artworkKey);

      if (!await artworkFile.exists()) {
        await artworkFile.writeAsBytes(artworkBytes, flush: true);
        AppLogger.debug(
          LogCategory.metadata,
          'Saved artwork for $artworkKey (${artworkBytes.length} bytes)',
        );
      }

      return artworkFile.path;
    } catch (e) {
      AppLogger.warning(LogCategory.metadata, 'Failed to save artwork file', e);
      return null;
    }
  }
}
