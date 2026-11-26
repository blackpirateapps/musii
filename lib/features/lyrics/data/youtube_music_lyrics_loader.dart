import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/error/failures.dart';
import '../../library/domain/entities/music_entities.dart';
import '../../youtube_music/data/youtube_music_client.dart';
import '../domain/entities/lyric_model.dart';
import '../domain/repositories/lyrics_repository.dart';
import '../domain/services/lrc_parser.dart';

class YouTubeMusicLyricsLoader {
  YouTubeMusicLyricsLoader({
    required LyricsRepository lyrics,
    required YouTubeMusicClient youtube,
    required http.Client httpClient,
  }) : _lyrics = lyrics,
       _youtube = youtube,
       _http = httpClient;

  final LyricsRepository _lyrics;
  final YouTubeMusicClient _youtube;
  final http.Client _http;
  final _inFlight = <String, Future<void>>{};
  final _notFound = <String>{};

  Future<void> load(Track track, {Duration? playbackDuration}) {
    final videoId = track.youtubeVideoId;
    if (videoId == null || _notFound.contains(track.id)) return Future.value();
    return _inFlight.putIfAbsent(
      track.id,
      () => _load(track, videoId, playbackDuration).whenComplete(() {
        _inFlight.remove(track.id);
      }),
    );
  }

  Future<void> _load(
    Track track,
    String videoId,
    Duration? playbackDuration,
  ) async {
    final cached = await _lyrics.getLyricsForTrack(track.id);
    if (cached?.hasLyrics == true) return;

    Object? lookupError;
    String? fromLrclib;
    try {
      fromLrclib = await _lookupLrclib(track, playbackDuration);
    } catch (error) {
      lookupError = error;
    }
    if (fromLrclib != null &&
        await _save(track.id, fromLrclib, LyricSource.lrclib)) {
      return;
    }

    final fromYouTube = await _youtube.getLyrics(videoId);
    if (fromYouTube != null &&
        await _save(track.id, fromYouTube, LyricSource.youtubeMusic)) {
      return;
    }
    if (lookupError != null) throw lookupError;
    _notFound.add(track.id);
  }

  Future<String?> _lookupLrclib(Track track, Duration? playbackDuration) async {
    final artist = track.artistName
        ?.replaceFirst(RegExp(r'\s+-\s+Topic$', caseSensitive: false), '')
        .trim();
    if (artist == null || artist.isEmpty || track.title.trim().isEmpty) {
      return null;
    }
    final durationMs = playbackDuration?.inMilliseconds ?? 0;
    final seconds = ((durationMs > 0 ? durationMs : track.durationMs) / 1000)
        .round();
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': track.title.trim(),
      'artist_name': artist,
      if (seconds >= 1 && seconds <= 3600) 'duration': '$seconds',
    });
    final response = await _http
        .get(
          uri,
          headers: {
            'User-Agent': 'Musii (https://github.com/blackpirateapps/musii)',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const NetworkFailure('Could not look up lyrics on LRCLIB.');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map || json['instrumental'] == true) return null;
    final synced = json['syncedLyrics'];
    final plain = json['plainLyrics'];
    if (synced is String && synced.trim().isNotEmpty) return synced;
    return plain is String && plain.trim().isNotEmpty ? plain : null;
  }

  Future<bool> _save(String trackId, String rawText, LyricSource source) async {
    final parsed = LrcParser.parse(rawText);
    if (parsed.lines.isEmpty) return false;
    await _lyrics.saveLyrics(
      trackId: trackId,
      source: source,
      isSynchronized: parsed.isSynchronized,
      rawText: parsed.rawText,
      offsetMs: parsed.offsetMs,
      lines: parsed.lines,
    );
    return true;
  }
}
