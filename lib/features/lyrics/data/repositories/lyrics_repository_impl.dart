import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/lyric_model.dart';
import '../../domain/repositories/lyrics_repository.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  final AppDatabase _database;

  LyricsRepositoryImpl({required AppDatabase database}) : _database = database;

  Future<List<LyricLine>> _loadLinesWithWords(String lyricsId) async {
    final linesQuery = (_database.select(_database.lyricLines)
      ..where((tbl) => tbl.lyricsId.equals(lyricsId))
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.sequence)]));

    final lineRows = await linesQuery.get();
    if (lineRows.isEmpty) return const [];

    final lineIds = lineRows.map((lr) => lr.id).toList();

    final wordsQuery = (_database.select(_database.lyricWords)
      ..where((tbl) => tbl.lineId.isIn(lineIds))
      ..orderBy([
        (tbl) => OrderingTerm.asc(tbl.lineId),
        (tbl) => OrderingTerm.asc(tbl.wordIndex),
      ]));

    final wordRows = await wordsQuery.get();
    final Map<String, List<LyricWord>> wordsByLineId = {};
    for (final wr in wordRows) {
      wordsByLineId
          .putIfAbsent(wr.lineId, () => [])
          .add(
            LyricWord(
              index: wr.wordIndex,
              text: wr.content,
              startMs: wr.startMs,
              endMs: wr.endMs,
            ),
          );
    }

    return lineRows
        .map(
          (lr) => LyricLine(
            timestampMs: lr.timestampMs,
            text: lr.content,
            sequence: lr.sequence,
            words: wordsByLineId[lr.id] ?? const [],
          ),
        )
        .toList();
  }

  @override
  Stream<TrackLyrics?> watchLyricsForTrack(String trackId) {
    final query = (_database.select(_database.lyrics)
      ..where((tbl) => tbl.trackId.equals(trackId)));

    return query.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;

      final lines = await _loadLinesWithWords(row.id);

      return TrackLyrics(
        id: row.id,
        trackId: row.trackId,
        source: LyricSource.fromString(row.source),
        isSynchronized: row.isSynchronized,
        rawText: row.rawText,
        offsetMs: row.offsetMs,
        lines: lines,
      );
    });
  }

  @override
  Future<TrackLyrics?> getLyricsForTrack(String trackId) async {
    try {
      final row = await (_database.select(
        _database.lyrics,
      )..where((tbl) => tbl.trackId.equals(trackId))).getSingleOrNull();

      if (row == null) return null;

      final lines = await _loadLinesWithWords(row.id);

      return TrackLyrics(
        id: row.id,
        trackId: row.trackId,
        source: LyricSource.fromString(row.source),
        isSynchronized: row.isSynchronized,
        rawText: row.rawText,
        offsetMs: row.offsetMs,
        lines: lines,
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
      await _database
          .into(_database.lyrics)
          .insertOnConflictUpdate(
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

      // 2. Clear old words & lines for this lyric
      final existingLineRows = await (_database.select(
        _database.lyricLines,
      )..where((tbl) => tbl.lyricsId.equals(lyricsId))).get();
      if (existingLineRows.isNotEmpty) {
        final existingLineIds = existingLineRows.map((lr) => lr.id).toList();
        await (_database.delete(
          _database.lyricWords,
        )..where((tbl) => tbl.lineId.isIn(existingLineIds))).go();
      }
      await (_database.delete(
        _database.lyricLines,
      )..where((tbl) => tbl.lyricsId.equals(lyricsId))).go();

      // 3. Batch insert new lines and words
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineId = 'll_${lyricsId}_$i';

        await _database
            .into(_database.lyricLines)
            .insert(
              LyricLinesCompanion(
                id: Value(lineId),
                lyricsId: Value(lyricsId),
                timestampMs: Value(line.timestampMs),
                content: Value(line.text),
                sequence: Value(i),
              ),
            );

        for (int w = 0; w < line.words.length; w++) {
          final word = line.words[w];
          await _database
              .into(_database.lyricWords)
              .insert(
                LyricWordsCompanion(
                  id: Value('lw_${lineId}_$w'),
                  lineId: Value(lineId),
                  wordIndex: Value(w),
                  content: Value(word.text),
                  startMs: Value(word.startMs),
                  endMs: Value(word.endMs),
                ),
              );
        }
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
      final existingLineRows = await (_database.select(
        _database.lyricLines,
      )..where((tbl) => tbl.lyricsId.equals(lyricsId))).get();
      if (existingLineRows.isNotEmpty) {
        final existingLineIds = existingLineRows.map((lr) => lr.id).toList();
        await (_database.delete(
          _database.lyricWords,
        )..where((tbl) => tbl.lineId.isIn(existingLineIds))).go();
      }
      await (_database.delete(
        _database.lyricLines,
      )..where((tbl) => tbl.lyricsId.equals(lyricsId))).go();
      await (_database.delete(
        _database.lyrics,
      )..where((tbl) => tbl.id.equals(lyricsId))).go();
    });
  }
}
