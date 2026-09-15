import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';

void main() {
  group('TrackLyrics Active Line Tracking', () {
    const testLines = [
      LyricLine(timestampMs: 5000, text: 'First line', sequence: 0),
      LyricLine(timestampMs: 12000, text: 'Second line', sequence: 1),
      LyricLine(timestampMs: 20000, text: 'Third line', sequence: 2),
      LyricLine(timestampMs: 35000, text: 'Final chorus line', sequence: 3),
    ];

    const syncedLyrics = TrackLyrics(
      id: 'lyrics_1',
      trackId: 'track_1',
      source: LyricSource.embeddedSynced,
      isSynchronized: true,
      lines: testLines,
    );

    test(
      'returns -1 when playback position is before the first lyric line',
      () {
        expect(
          syncedLyrics.findActiveIndex(const Duration(milliseconds: 0)),
          equals(-1),
        );
        expect(
          syncedLyrics.findActiveIndex(const Duration(milliseconds: 2500)),
          equals(-1),
        );
        expect(
          syncedLyrics.findActiveIndex(const Duration(milliseconds: 4999)),
          equals(-1),
        );
      },
    );

    test('returns line 0 when playback position is inside first line', () {
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 5000)),
        equals(0),
      );
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 8000)),
        equals(0),
      );
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 11999)),
        equals(0),
      );
    });

    test('returns line 1 when playback position crosses into second line', () {
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 12000)),
        equals(1),
      );
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 16000)),
        equals(1),
      );
    });

    test('returns correct index across subsequent lines', () {
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 20000)),
        equals(2),
      );
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 34999)),
        equals(2),
      );
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 35000)),
        equals(3),
      );
    });

    test(
      'retains the final lyric line index when playback exceeds last timestamp',
      () {
        expect(
          syncedLyrics.findActiveIndex(const Duration(milliseconds: 60000)),
          equals(3),
        );
        expect(
          syncedLyrics.findActiveIndex(const Duration(minutes: 5)),
          equals(3),
        );
      },
    );

    test('handles forward and backward seeking correctly', () {
      // Seek forward from start to line 2
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 25000)),
        equals(2),
      );

      // Seek backward from line 2 to line 0
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 6000)),
        equals(0),
      );

      // Seek backward before line 0
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 1000)),
        equals(-1),
      );

      // Seek forward to last line
      expect(
        syncedLyrics.findActiveIndex(const Duration(milliseconds: 40000)),
        equals(3),
      );
    });

    test('returns -1 for unsynchronized lyrics', () {
      const unsyncedLyrics = TrackLyrics(
        id: 'lyrics_2',
        trackId: 'track_2',
        source: LyricSource.embeddedPlain,
        isSynchronized: false,
        lines: [
          LyricLine(timestampMs: 0, text: 'Plain line 1', sequence: 0),
          LyricLine(timestampMs: 0, text: 'Plain line 2', sequence: 1),
        ],
      );

      expect(
        unsyncedLyrics.findActiveIndex(const Duration(seconds: 10)),
        equals(-1),
      );
    });

    test('returns -1 for empty lyrics lines', () {
      const emptyLyrics = TrackLyrics(
        id: 'lyrics_3',
        trackId: 'track_3',
        source: LyricSource.embeddedSynced,
        isSynchronized: true,
        lines: [],
      );

      expect(
        emptyLyrics.findActiveIndex(const Duration(seconds: 10)),
        equals(-1),
      );
    });

    test(
      'static calculateActiveIndex handles empty and arbitrary lists safely',
      () {
        expect(
          TrackLyrics.calculateActiveIndex([], const Duration(seconds: 5)),
          equals(-1),
        );
        expect(
          TrackLyrics.calculateActiveIndex(
            testLines,
            const Duration(milliseconds: 15000),
          ),
          equals(1),
        );
      },
    );
  });
}
