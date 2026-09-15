import 'package:flutter/foundation.dart';

@immutable
class ParsedAudioMetadata {
  final String title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? composer;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;
  final int? channels;
  final String format;
  final int fileSize;
  final Uint8List? artworkBytes;
  final Map<String, dynamic>? rawMetadata;

  const ParsedAudioMetadata({
    required this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.composer,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.durationMs = 0,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    required this.format,
    required this.fileSize,
    this.artworkBytes,
    this.rawMetadata,
  });
}

@immutable
class NormalizedMetadata {
  final String title;
  final String normalizedTitle;
  final String artist;
  final String normalizedArtist;
  final String album;
  final String normalizedAlbum;
  final String? albumArtist;
  final String? genre;
  final String? normalizedGenre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;
  final int? channels;
  final String format;
  final int fileSize;

  const NormalizedMetadata({
    required this.title,
    required this.normalizedTitle,
    required this.artist,
    required this.normalizedArtist,
    required this.album,
    required this.normalizedAlbum,
    this.albumArtist,
    this.genre,
    this.normalizedGenre,
    this.trackNumber,
    this.discNumber,
    this.year,
    required this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    required this.format,
    required this.fileSize,
  });
}
