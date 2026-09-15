import '../entities/lyric_model.dart';

abstract class LyricsRepository {
  Stream<TrackLyrics?> watchLyricsForTrack(String trackId);

  Future<TrackLyrics?> getLyricsForTrack(String trackId);

  Future<void> saveLyrics({
    required String trackId,
    required LyricSource source,
    required bool isSynchronized,
    required String? rawText,
    required int offsetMs,
    required List<LyricLine> lines,
  });

  Future<void> deleteLyricsForTrack(String trackId);
}
