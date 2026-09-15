import 'package:flutter/foundation.dart';

import '../../../library/domain/entities/music_entities.dart';

enum AudioRepeatMode {
  off('off'),
  all('all'),
  one('one');

  final String value;
  const AudioRepeatMode(this.value);

  static AudioRepeatMode fromString(String val) {
    return AudioRepeatMode.values.firstWhere(
      (e) => e.value == val,
      orElse: () => AudioRepeatMode.off,
    );
  }
}

@immutable
class PlayerStateSnapshot {
  final Track? currentTrack;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool shuffleMode;
  final AudioRepeatMode repeatMode;
  final List<Track> queue;
  final int queueIndex;

  const PlayerStateSnapshot({
    this.currentTrack,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.shuffleMode = false,
    this.repeatMode = AudioRepeatMode.off,
    this.queue = const [],
    this.queueIndex = 0,
  });

  bool get hasNext => queueIndex < queue.length - 1;
  bool get hasPrevious => queueIndex > 0 || position.inSeconds > 3;

  PlayerStateSnapshot copyWith({
    Track? currentTrack,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    bool? shuffleMode,
    AudioRepeatMode? repeatMode,
    List<Track>? queue,
    int? queueIndex,
    bool clearCurrentTrack = false,
  }) {
    return PlayerStateSnapshot(
      currentTrack: clearCurrentTrack
          ? null
          : (currentTrack ?? this.currentTrack),
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
    );
  }
}
