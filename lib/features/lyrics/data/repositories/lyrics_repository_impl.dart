import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/lyric_model.dart';
import '../../domain/repositories/lyrics_repository.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  final AppDatabase _database;

  LyricsRepositoryImpl({required AppDatabase database}) : _database = database;

  @override
  Stream<TrackLyrics?> watchLyricsForTrack(String trackId) {
    final query = (_database.select(_database.lyrics)
      ..where((tbl) => tbl.trackId.equals(trackId)));

    return query.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;

      final linesQuery = (_database.select(_database.lyricLines)
        ..where((tbl) => tbl.lyricsId.equals(row.id))
        ..orderBy([(tbl) => OrderingTerm.asc(tbl.sequence)]));

      final lineRows = await linesQuery.get();

      return TrackLyrics(
        id: row.id,
        trackId: row.trackId,
        source: LyricSource.fromString(row.source),
        isSynchronized: row.isSynchronized,
        rawText: row.rawText,
        offsetMs: row.offsetMs,
        lines: lineRows
            .map(
              (lr) => LyricLine(
                timestampMs: lr.timestampMs,
                text: lr.content,
                sequence: lr.sequence,
              ),
            )
            .toList(),
      );
    });
  }

  @override
  Future<TrackLyrics?> getLyricsForTrack(String trackId) async {
    try {
      final row = await (_database.select(_database.lyrics)
            ..where((tbl) => tbl.trackId.equals(trackId)))
          .getSingleOrNull();

      if (row == null) return null;

      final lineRows = await (_database.select(_database.lyricLines)
            ..where((tbl) => tbl.lyricsId.equals(row.id))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.sequence)]))
          .get();

      return TrackLyrics(
        id: row.id,
        trackId: row.trackId,
        source: LyricSource.fromString(row.source),
        isSynchronized: row.isSynchronized,
        rawText: row.rawText,
        offsetMs: row.offsetMs,
        lines: lineRows
            .map(
              (lr) => LyricLine(
                timestampMs: lr.timestampMs,
                text: lr.content,
                sequence: lr.sequence,
              ),
            )
            .toList(),
      );
    } catch (e, st) {
      AppLogger.error(
        LogCategory.metadata,
        'Failed to get lyrics for track $trackId',
        e,
        st,
      );
      return null;
    }
  }

  @override
  Future<void> saveLyrics({
    required String trackId,
    required LyricSource source,
    required bool isSynchronized,
    required String? rawText,
    required int offsetMs,
    required List<LyricLine> lines,
  }) async {
    final lyricsId = 'lyric_$trackId';

    await _database.transaction(() async {
      // 1. Upsert lyrics header record
      await _database.into(_database.lyrics).insertOnConflictUpdate(
            LyricsCompanion(
              id: Value(lyricsId),
              trackId: Value(trackId),
              source: Value(source.value),
              isSynchronized: Value(isSynchronized),
              rawText: Value(rawText),
              offsetMs: Value(offsetMs),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 2. Clear old lines for this lyric
      await (_database.delete(_database.lyricLines)
            ..where((tbl) => tbl.lyricsId.equals(lyricsId)))
          .go();

      // 3. Batch insert new lines
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        await _database.into(_database.lyricLines).insert(
              LyricLinesCompanion(
                id: Value('ll_${lyricsId}_$i'),
                lyricsId: Value(lyricsId),
                timestampMs: Value(line.timestampMs),
                content: Value(line.text),
                sequence: Value(i),
              ),
            );
      }
    });

    AppLogger.debug(
      LogCategory.metadata,
      'Saved ${lines.length} lyric lines for track $trackId (source: ${source.value}, synced: $isSynchronized)',
    );
  }

  @override
  Future<void> deleteLyricsForTrack(String trackId) async {
    final lyricsId = 'lyric_$trackId';
    await _database.transaction(() async {
      await (_database.delete(_database.lyricLines)
            ..where((tbl) => tbl.lyricsId.equals(lyricsId)))
          .go();
      await (_database.delete(_database.lyrics)
            ..where((tbl) => tbl.id.equals(lyricsId)))
          .go();
    });
  }
}
