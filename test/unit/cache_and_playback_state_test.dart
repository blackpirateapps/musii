import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/constants/app_constants.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';

void main() {
  group('PlayerStateSnapshot and Constants', () {
    test('AppGreeting returns appropriate greeting according to time', () {
      final morning = DateTime(2026, 9, 15, 8, 30);
      final afternoon = DateTime(2026, 9, 15, 14, 0);
      final evening = DateTime(2026, 9, 15, 19, 0);
      final night = DateTime(2026, 9, 15, 23, 0);

      expect(AppGreeting.getGreeting(morning), equals('Good morning'));
      expect(AppGreeting.getGreeting(afternoon), equals('Good afternoon'));
      expect(AppGreeting.getGreeting(evening), equals('Good evening'));
      expect(AppGreeting.getGreeting(night), equals('Good night'));
    });

    test('PlayerStateSnapshot correctly computes hasNext and hasPrevious', () {
      const track1 = Track(
        id: '1',
        driveFileId: 'df1',
        sourceId: 's1',
        title: 'Track 1',
        normalizedTitle: 'track 1',
      );
      const track2 = Track(
        id: '2',
        driveFileId: 'df2',
        sourceId: 's1',
        title: 'Track 2',
        normalizedTitle: 'track 2',
      );

      const snapshot = PlayerStateSnapshot(
        currentTrack: track1,
        queue: [track1, track2],
        queueIndex: 0,
        position: Duration(seconds: 1),
      );

      expect(snapshot.hasNext, isTrue);
      expect(snapshot.hasPrevious, isFalse);

      final nextSnapshot = snapshot.copyWith(
        currentTrack: track2,
        queueIndex: 1,
      );

      expect(nextSnapshot.hasNext, isFalse);
      expect(nextSnapshot.hasPrevious, isTrue);
    });

    test('AudioRepeatMode string parsing handles cycle', () {
      expect(AudioRepeatMode.fromString('all'), equals(AudioRepeatMode.all));
      expect(AudioRepeatMode.fromString('one'), equals(AudioRepeatMode.one));
      expect(
        AudioRepeatMode.fromString('invalid'),
        equals(AudioRepeatMode.off),
      );
    });
  });
}
