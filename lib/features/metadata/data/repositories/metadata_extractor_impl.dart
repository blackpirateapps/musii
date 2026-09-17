import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:path/path.dart' as p;

import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../datasources/tag_supplement_reader.dart';
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
      final supplement = await AudioTagSupplement.extract(file, ext);

      Uint8List? artworkBytes;
      if (meta.pictures.isNotEmpty) {
        artworkBytes = meta.pictures.first.bytes;
      }

      final durationMs = meta.duration?.inMilliseconds ?? 0;
      final year = meta.year?.year;

      final resolvedArtist =
          (supplement.songArtist != null &&
              supplement.songArtist!.trim().isNotEmpty)
          ? supplement.songArtist!.trim()
          : meta.artist?.trim();

      String? resolvedAlbumArtist =
          (supplement.albumArtist != null &&
              supplement.albumArtist!.trim().isNotEmpty)
          ? supplement.albumArtist!.trim()
          : meta.albumArtist?.trim();

      if (supplement.isCompilation &&
          (resolvedAlbumArtist == null || resolvedAlbumArtist.isEmpty)) {
        resolvedAlbumArtist = MetadataNormalizationService.variousArtists;
      }

      final parsed = ParsedAudioMetadata(
        title: (meta.title != null && meta.title!.trim().isNotEmpty)
            ? meta.title!.trim()
            : MetadataNormalizationService.cleanFilename(fileName),
        artist: resolvedArtist,
        album: meta.album?.trim(),
        albumArtist: resolvedAlbumArtist,
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
        lyrics: (meta.lyrics != null && meta.lyrics!.trim().isNotEmpty)
            ? meta.lyrics!.trim()
            : null,
        rawMetadata: {
          'title': meta.title,
          'artist': resolvedArtist,
          'album': meta.album,
          'albumArtist': resolvedAlbumArtist,
          'durationMs': durationMs,
          'trackNumber': meta.trackNumber,
          'discNumber': meta.discNumber,
          'year': year,
          'bitrate': meta.bitrate,
          'sampleRate': meta.sampleRate,
          'hasLyrics': meta.lyrics != null && meta.lyrics!.trim().isNotEmpty,
          'isCompilation': supplement.isCompilation,
        },
      );

      // Save artwork if available
      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        final effectiveArtist =
            (parsed.albumArtist != null &&
                parsed.albumArtist!.trim().isNotEmpty)
            ? parsed.albumArtist
            : parsed.artist;
        await _saveArtworkIfNew(parsed.album, effectiveArtist, artworkBytes);
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
