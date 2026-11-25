import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:path/path.dart' as p;

import '../../../../core/logging/app_logger.dart';
import '../datasources/tag_supplement_reader.dart';
import '../../domain/entities/parsed_audio_metadata.dart';
import '../../domain/services/metadata_normalization_service.dart';

class MetadataExtractor {
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
}
