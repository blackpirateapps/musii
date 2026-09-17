import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/parsed_audio_metadata.dart';

class MetadataNormalizationService {
  static const String unknownArtist = 'Unknown Artist';
  static const String unknownAlbum = 'Unknown Album';
  static const String variousArtists = 'Various Artists';

  static NormalizedMetadata normalize(
    ParsedAudioMetadata raw, {
    required String filenameFallback,
  }) {
    final title = _normalizeTitle(raw.title, filenameFallback);
    final normalizedTitle = _createSearchKey(title);

    final artist = _normalizeArtist(raw.artist);
    final normalizedArtist = _createSearchKey(artist);

    final album = _normalizeAlbum(raw.album);
    final normalizedAlbum = _createSearchKey(album);

    final rawAlbumArtist = raw.albumArtist?.trim();
    final albumArtist = (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty)
        ? _normalizeArtist(rawAlbumArtist)
        : null;
    final genre = _normalizeGenre(raw.genre);
    final normalizedGenre = genre != null ? _createSearchKey(genre) : null;

    return NormalizedMetadata(
      title: title,
      normalizedTitle: normalizedTitle,
      artist: artist,
      normalizedArtist: normalizedArtist,
      album: album,
      normalizedAlbum: normalizedAlbum,
      albumArtist: albumArtist,
      genre: genre,
      normalizedGenre: normalizedGenre,
      trackNumber: raw.trackNumber,
      discNumber: raw.discNumber,
      year: raw.year,
      durationMs: raw.durationMs,
      bitrate: raw.bitrate,
      sampleRate: raw.sampleRate,
      bitDepth: raw.bitDepth,
      channels: raw.channels,
      format: raw.format.toUpperCase(),
      fileSize: raw.fileSize,
    );
  }

  static String _normalizeTitle(String? rawTitle, String fallbackFilename) {
    String candidate = rawTitle?.trim() ?? '';
    if (candidate.isEmpty) {
      candidate = cleanFilename(fallbackFilename);
    }

    // Strip track number prefixes like "01 - ", "01. ", "01 ", "01_", "1-01 ", "[01] "
    candidate = candidate.replaceFirst(
      RegExp(r'^(\[\d+\]\s*|\d+-\d+\s*|\d+\s*[\.\-_]\s*|\d+\s+)'),
      '',
    );

    // Normalize spacing
    candidate = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();

    return candidate.isNotEmpty ? candidate : cleanFilename(fallbackFilename);
  }

  static String cleanFilename(String filename) {
    String clean = filename;
    final dotIndex = clean.lastIndexOf('.');
    if (dotIndex != -1) {
      clean = clean.substring(0, dotIndex);
    }
    // Replace underscores and extra spaces
    clean = clean.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : 'Unknown Track';
  }

  static String _normalizeArtist(String? rawArtist) {
    if (rawArtist == null) return unknownArtist;
    String clean = rawArtist.trim();
    if (clean.isEmpty) return unknownArtist;

    // Normalize "Various Artists" aliases
    final lower = clean.toLowerCase();
    if (lower == 'various' ||
        lower == 'various artist' ||
        lower == 'various artists' ||
        lower == 'va' ||
        lower == 'v/a') {
      return variousArtists;
    }

    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : unknownArtist;
  }

  static String _normalizeAlbum(String? rawAlbum) {
    if (rawAlbum == null) return unknownAlbum;
    String clean = rawAlbum.trim();
    if (clean.isEmpty) return unknownAlbum;

    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : unknownAlbum;
  }

  static String? _normalizeGenre(String? rawGenre) {
    if (rawGenre == null) return null;
    String clean = rawGenre.trim();
    if (clean.isEmpty) return null;

    // Normalize common numeric ID3v1 genre codes like "(17)"
    final match = RegExp(r'^\((\d+)\)$').firstMatch(clean);
    if (match != null) {
      clean = _mapId3GenreCode(int.tryParse(match.group(1) ?? ''));
    }

    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : null;
  }

  static String _mapId3GenreCode(int? code) {
    if (code == null) return 'Other';
    const genres = [
      'Blues',
      'Classic Rock',
      'Country',
      'Dance',
      'Disco',
      'Funk',
      'Grunge',
      'Hip-Hop',
      'Jazz',
      'Metal',
      'New Age',
      'Oldies',
      'Other',
      'Pop',
      'R&B',
      'Rap',
      'Reggae',
      'Rock',
      'Techno',
      'Industrial',
      'Alternative',
      'Ska',
      'Death Metal',
      'Pranks',
      'Soundtrack',
      'Euro-Techno',
      'Ambient',
      'Trip-Hop',
      'Vocal',
      'Jazz+Funk',
      'Fusion',
      'Trance',
      'Classical',
      'Instrumental',
      'Acid',
      'House',
      'Game',
      'Sound Clip',
      'Gospel',
      'Noise',
      'AlternRock',
      'Bass',
      'Soul',
      'Punk',
      'Space',
      'Meditative',
      'Instrumental Pop',
      'Instrumental Rock',
      'Ethnic',
      'Gothic',
      'Darkwave',
      'Techno-Industrial',
      'Electronic',
      'Pop-Folk',
      'Eurodance',
      'Dream',
      'Southern Rock',
      'Comedy',
      'Cult',
      'Gangsta',
      'Top 40',
      'Christian Rap',
      'Pop/Funk',
      'Jungle',
      'Native American',
      'Cabaret',
      'New Wave',
      'Psychadelic',
      'Rave',
      'Showtunes',
      'Trailer',
      'Lo-Fi',
      'Tribal',
      'Acid Punk',
      'Acid Jazz',
      'Polka',
      'Retro',
      'Musical',
      'Rock & Roll',
      'Hard Rock',
    ];
    if (code >= 0 && code < genres.length) {
      return genres[code];
    }
    return 'Other';
  }

  static String _createSearchKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String computeArtworkKey(String? album, String? artist) {
    final normAlbum = _createSearchKey(album ?? unknownAlbum);
    final normArtist = _createSearchKey(artist ?? unknownArtist);
    final combined = '$normArtist:$normAlbum';
    return md5.convert(utf8.encode(combined)).toString();
  }

  static String computeAlbumKey({
    required String albumName,
    required String? albumArtist,
    required String trackArtist,
  }) {
    final effectiveArtist =
        (albumArtist != null && albumArtist.trim().isNotEmpty)
        ? albumArtist
        : trackArtist;

    final normAlbum = _createSearchKey(_normalizeAlbum(albumName));
    final normArtist = _createSearchKey(_normalizeArtist(effectiveArtist));

    return '$normAlbum::$normArtist';
  }
}
