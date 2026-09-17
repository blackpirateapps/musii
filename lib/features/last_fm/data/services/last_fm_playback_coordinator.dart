import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../domain/repositories/last_fm_repository.dart';
import '../../domain/services/scrobble_eligibility_service.dart';

class LastFmPlaybackCoordinator {
  final LastFmRepository _repository;

  Track? _currentTrack;
  int _sessionStartTimeSeconds = 0;
  bool _hasScrobbledForSession = false;
  bool _hasSentNowPlaying = false;
  int _lastKnownPositionMs = 0;

  final StreamController<Track> _scrobbleSuccessController =
      StreamController<Track>.broadcast();

  LastFmPlaybackCoordinator({required LastFmRepository repository})
    : _repository = repository;

  Stream<Track> get onScrobbleSuccess => _scrobbleSuccessController.stream;

  Track? get currentTrack => _currentTrack;

  /// Invoked when a track begins loading/playing.
  void onTrackStarted(Track track) {
    // If it's a completely different track, start a new session
    if (_currentTrack?.id != track.id) {
      _startNewSession(track);
    }
  }

  void _startNewSession(Track track) {
    _currentTrack = track;
    _sessionStartTimeSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _hasScrobbledForSession = false;
    _hasSentNowPlaying = false;
    _lastKnownPositionMs = 0;

    AppLogger.debug(
      LogCategory.lastFm,
      'Started Last.fm listening session for "${track.title}" (Session start: $_sessionStartTimeSeconds)',
    );

    _dispatchNowPlaying(track);
  }

  /// Invoked when the same track is restarted or replayed (e.g. repeat-one, skip to 0:00).
  void onTrackReplayed(Track track) {
    AppLogger.debug(
      LogCategory.lastFm,
      'Track replayed, initializing new session for "${track.title}"',
    );
    _startNewSession(track);
  }

  void _dispatchNowPlaying(Track track) {
    if (_hasSentNowPlaying) return;
    _hasSentNowPlaying = true;

    // Fire and forget; never blocks playback
    unawaited(() async {
      try {
        final result = await _repository.updateNowPlaying(track);
        if (result.isFailure) {
          AppLogger.debug(
            LogCategory.lastFm,
            'Now Playing update unsuccessful: ${result.failureOrNull?.message}',
          );
        }
      } catch (e, st) {
        AppLogger.warning(
          LogCategory.lastFm,
          'Unexpected error sending Now Playing',
          e,
          st,
        );
      }
    }());
  }

  /// Invoked during playback position progress.
  void onPositionUpdated(Duration position, Duration? duration) {
    final track = _currentTrack;
    if (track == null) return;

    final posMs = position.inMilliseconds;
    final durMs = duration?.inMilliseconds ?? track.durationMs;

    // Detect user skipping back to beginning after significant play (replay)
    if (_lastKnownPositionMs > 10000 && posMs < 2000) {
      onTrackReplayed(track);
      return;
    }
    _lastKnownPositionMs = posMs;

    // Check scrobble eligibility
    if (!_hasScrobbledForSession) {
      final isEligible = ScrobbleEligibilityService.hasReachedThreshold(
        positionMs: posMs,
        durationMs: durMs,
      );

      if (isEligible) {
        _hasScrobbledForSession = true;
        _dispatchScrobble(track, _sessionStartTimeSeconds);
      }
    }
  }

  void _dispatchScrobble(Track track, int startTime) {
    AppLogger.info(
      LogCategory.lastFm,
      'Track "${track.title}" became eligible for scrobbling; queuing...',
    );

    unawaited(() async {
      try {
        final result = await _repository.recordScrobble(track, startTime);
        if (result.isSuccess) {
          _scrobbleSuccessController.add(track);
        }
      } catch (e, st) {
        AppLogger.warning(
          LogCategory.lastFm,
          'Failed to record scrobble for "${track.title}"',
          e,
          st,
        );
      }
    }());
  }

  /// Invoked when a track finishes playback.
  void onTrackCompleted() {
    _lastKnownPositionMs = 0;
    // On track completed, next play of this or another track will be a new session
  }

  void dispose() {
    _scrobbleSuccessController.close();
  }
}
