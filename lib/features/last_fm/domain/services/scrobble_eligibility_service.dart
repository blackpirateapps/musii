import '../../../library/domain/entities/music_entities.dart';

/// Pure domain service determining Last.fm scrobble eligibility.
///
/// Last.fm Official Guidelines:
/// 1. The track must be longer than 30 seconds.
/// 2. The track must have been played for at least half its duration,
///    OR for 4 minutes (240 seconds), whichever occurs first.
/// 3. Track must contain valid, non-empty title and artist metadata.
class ScrobbleEligibilityService {
  static const int minTrackDurationMs = 30000; // 30 seconds
  static const int maxThresholdMs = 240000; // 4 minutes

  /// Determines whether a [Track] is structurally eligible to be scrobbled.
  static bool isTrackEligible(Track? track) {
    if (track == null) return false;
    final title = track.title.trim();
    final artist = (track.artistName ?? '').trim();
    if (title.isEmpty || artist.isEmpty) return false;

    // Track must be at least 30 seconds long
    if (track.durationMs > 0 && track.durationMs < minTrackDurationMs) {
      return false;
    }
    return true;
  }

  /// Calculates the required listening duration in milliseconds before
  /// a scrobble can be submitted.
  ///
  /// - For tracks >= 30s: min(duration / 2, 4 minutes).
  /// - For tracks with unknown/0 duration: defaults to 4 minutes (240s).
  static int calculateThresholdMs(int durationMs) {
    if (durationMs <= 0) {
      return maxThresholdMs;
    }
    if (durationMs < minTrackDurationMs) {
      // Ineligible track
      return minTrackDurationMs;
    }
    final halfDuration = durationMs ~/ 2;
    return halfDuration < maxThresholdMs ? halfDuration : maxThresholdMs;
  }

  /// Checks if the playback [positionMs] has reached or exceeded the required
  /// listening threshold for the track's [durationMs].
  static bool hasReachedThreshold({
    required int positionMs,
    required int durationMs,
  }) {
    if (durationMs > 0 && durationMs < minTrackDurationMs) {
      return false;
    }
    final threshold = calculateThresholdMs(durationMs);
    return positionMs >= threshold;
  }
}
