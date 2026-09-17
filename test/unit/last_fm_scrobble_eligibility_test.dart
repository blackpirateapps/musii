import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/last_fm/domain/services/scrobble_eligibility_service.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';

void main() {
  group('ScrobbleEligibilityService', () {
    Track createTrack({
      String id = 't1',
      String title = 'Plastic Love',
      String? artistName = 'Mariya Takeuchi',
      int durationMs = 300000, // 5 min
    }) {
      return Track(
        id: id,
        driveFileId: 'df_$id',
        sourceId: 'src_$id',
        title: title,
        normalizedTitle: title.toLowerCase(),
        artistName: artistName,
        albumName: 'Variety',
        durationMs: durationMs,
      );
    }

    group('isTrackEligible', () {
      test('returns false when track is null', () {
        expect(ScrobbleEligibilityService.isTrackEligible(null), isFalse);
      });

      test('returns false when title is empty or whitespace', () {
        expect(
          ScrobbleEligibilityService.isTrackEligible(createTrack(title: '')),
          isFalse,
        );
        expect(
          ScrobbleEligibilityService.isTrackEligible(createTrack(title: '   ')),
          isFalse,
        );
      });

      test('returns false when artist is null, empty or whitespace', () {
        expect(
          ScrobbleEligibilityService.isTrackEligible(
            createTrack(artistName: null),
          ),
          isFalse,
        );
        expect(
          ScrobbleEligibilityService.isTrackEligible(
            createTrack(artistName: ''),
          ),
          isFalse,
        );
        expect(
          ScrobbleEligibilityService.isTrackEligible(
            createTrack(artistName: '   '),
          ),
          isFalse,
        );
      });

      test(
        'returns false when track duration is strictly less than 30 seconds',
        () {
          expect(
            ScrobbleEligibilityService.isTrackEligible(
              createTrack(durationMs: 29999),
            ),
            isFalse,
          );
          expect(
            ScrobbleEligibilityService.isTrackEligible(
              createTrack(durationMs: 15000),
            ),
            isFalse,
          );
        },
      );

      test('returns true when track meets all criteria', () {
        expect(
          ScrobbleEligibilityService.isTrackEligible(
            createTrack(durationMs: 30000), // exactly 30s
          ),
          isTrue,
        );
        expect(
          ScrobbleEligibilityService.isTrackEligible(
            createTrack(durationMs: 180000), // 3 mins
          ),
          isTrue,
        );
      });

      test('returns true when duration is 0 (unknown duration)', () {
        expect(
          ScrobbleEligibilityService.isTrackEligible(
            createTrack(durationMs: 0),
          ),
          isTrue,
        );
      });
    });

    group('calculateThresholdMs', () {
      test('returns max 4 minutes (240,000 ms) for unknown/zero duration', () {
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(0),
          equals(240000),
        );
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(-10),
          equals(240000),
        );
      });

      test('returns 30,000 ms for tracks shorter than 30s', () {
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(20000),
          equals(30000),
        );
      });

      test('calculates half-duration for tracks under 8 minutes', () {
        // 60s track -> 30s threshold
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(60000),
          equals(30000),
        );
        // 180s track -> 90s threshold
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(180000),
          equals(90000),
        );
        // 400s track -> 200s threshold
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(400000),
          equals(200000),
        );
      });

      test('caps threshold at 4 minutes (240,000 ms) for tracks longer than 8 minutes', () {
        // 8 min track (480,000 ms) -> exactly 240,000 ms
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(480000),
          equals(240000),
        );
        // 10 min track (600,000 ms) -> 240,000 ms (capped)
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(600000),
          equals(240000),
        );
        // 20 min track (1,200,000 ms) -> 240,000 ms (capped)
        expect(
          ScrobbleEligibilityService.calculateThresholdMs(1200000),
          equals(240000),
        );
      });
    });

    group('hasReachedThreshold', () {
      test('returns false if track duration is under 30 seconds', () {
        expect(
          ScrobbleEligibilityService.hasReachedThreshold(
            positionMs: 25000,
            durationMs: 25000,
          ),
          isFalse,
        );
      });

      test('returns true when position reaches or exceeds threshold for normal track', () {
        const duration = 200000; // 200s, threshold is 100s (100,000 ms)

        expect(
          ScrobbleEligibilityService.hasReachedThreshold(
            positionMs: 99999,
            durationMs: duration,
          ),
          isFalse,
        );

        expect(
          ScrobbleEligibilityService.hasReachedThreshold(
            positionMs: 100000,
            durationMs: duration,
          ),
          isTrue,
        );

        expect(
          ScrobbleEligibilityService.hasReachedThreshold(
            positionMs: 150000,
            durationMs: duration,
          ),
          isTrue,
        );
      });

      test('returns true when 4-minute cap is reached on a long track', () {
        const duration = 600000; // 10 min track, cap is 240,000 ms

        expect(
          ScrobbleEligibilityService.hasReachedThreshold(
            positionMs: 239999,
            durationMs: duration,
          ),
          isFalse,
        );

        expect(
          ScrobbleEligibilityService.hasReachedThreshold(
            positionMs: 240000,
            durationMs: duration,
          ),
          isTrue,
        );
      });
    });
  });
}
