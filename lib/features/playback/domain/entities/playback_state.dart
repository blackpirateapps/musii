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

int _queueItemCounter = 0;

@immutable
class QueueItem {
  final String id;
  final Track track;

  const QueueItem({required this.id, required this.track});

  factory QueueItem.fromTrack(Track track, [String? id]) {
    final effectiveId =
        id ??
        'qi_${DateTime.now().microsecondsSinceEpoch}_${++_queueItemCounter}_${track.id}';
    return QueueItem(id: effectiveId, track: track);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          track.id == other.track.id;

  @override
  int get hashCode => id.hashCode ^ track.id.hashCode;

  @override
  String toString() => 'QueueItem(id: $id, track: ${track.title})';
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
  final List<Track> _queue;
  final List<QueueItem> _queueItems;
  final int queueIndex;

  const PlayerStateSnapshot({
    this.currentTrack,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.shuffleMode = false,
    this.repeatMode = AudioRepeatMode.off,
    List<Track> queue = const [],
    List<QueueItem> queueItems = const [],
    this.queueIndex = 0,
  }) : _queue = queue,
       _queueItems = queueItems;

  List<QueueItem> get queueItems => effectiveQueueItems;

  List<Track> get queue =>
      _queue.isNotEmpty ? _queue : _queueItems.map((e) => e.track).toList();

  List<QueueItem> get effectiveQueueItems {
    if (_queueItems.isNotEmpty) return _queueItems;
    if (_queue.isEmpty) return const [];
    return _queue
        .asMap()
        .entries
        .map((e) => QueueItem(id: 'q_${e.key}_${e.value.id}', track: e.value))
        .toList();
  }

  QueueItem? get currentQueueItem =>
      (effectiveQueueItems.isNotEmpty &&
          queueIndex >= 0 &&
          queueIndex < effectiveQueueItems.length)
      ? effectiveQueueItems[queueIndex]
      : null;

  List<QueueItem> get upNextItems =>
      (queueIndex < effectiveQueueItems.length - 1)
      ? effectiveQueueItems.sublist(queueIndex + 1)
      : const [];

  List<Track> get upNextTracks =>
      upNextItems.map((item) => item.track).toList();

  bool get hasNext => queueIndex < effectiveQueueItems.length - 1;
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
    List<QueueItem>? queueItems,
    int? queueIndex,
    bool clearCurrentTrack = false,
  }) {
    List<QueueItem>? nextQueueItems = queueItems;
    List<Track>? nextQueue = queue;

    if (nextQueueItems != null && nextQueue == null) {
      nextQueue = nextQueueItems.map((e) => e.track).toList();
    } else if (nextQueue != null && nextQueueItems == null) {
      nextQueueItems = nextQueue
          .asMap()
          .entries
          .map((e) => QueueItem(id: 'q_${e.key}_${e.value.id}', track: e.value))
          .toList();
    }

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
      queue: nextQueue ?? _queue,
      queueItems: nextQueueItems ?? _queueItems,
      queueIndex: queueIndex ?? this.queueIndex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerStateSnapshot &&
          runtimeType == other.runtimeType &&
          currentTrack == other.currentTrack &&
          position == other.position &&
          duration == other.duration &&
          isPlaying == other.isPlaying &&
          isBuffering == other.isBuffering &&
          shuffleMode == other.shuffleMode &&
          repeatMode == other.repeatMode &&
          queueIndex == other.queueIndex &&
          listEquals(_queueItems, other._queueItems);

  @override
  int get hashCode => Object.hash(
    currentTrack,
    position,
    duration,
    isPlaying,
    isBuffering,
    shuffleMode,
    repeatMode,
    queueIndex,
    Object.hashAll(_queueItems),
  );
}
