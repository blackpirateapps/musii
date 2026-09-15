import 'package:flutter/foundation.dart';

@immutable
class LyricLine {
  final int timestampMs;
  final String text;
  final int sequence;

  const LyricLine({
    required this.timestampMs,
    required this.text,
    this.sequence = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricLine &&
          other.timestampMs == timestampMs &&
          other.text == text &&
          other.sequence == sequence);

  @override
  int get hashCode => Object.hash(timestampMs, text, sequence);

  @override
  String toString() =>
      'LyricLine(timestampMs: $timestampMs, sequence: $sequence, text: $text)';
}

enum LyricSource {
  embeddedSynced('embedded_synced'),
  embeddedPlain('embedded_plain'),
  sidecarLrc('sidecar_lrc'),
  none('none');

  final String value;
  const LyricSource(this.value);

  static LyricSource fromString(String val) {
    return LyricSource.values.firstWhere(
      (e) => e.value == val,
      orElse: () => LyricSource.none,
    );
  }
}

@immutable
class TrackLyrics {
  final String id;
  final String trackId;
  final LyricSource source;
  final bool isSynchronized;
  final String? rawText;
  final int offsetMs;
  final List<LyricLine> lines;

  const TrackLyrics({
    required this.id,
    required this.trackId,
    required this.source,
    required this.isSynchronized,
    this.rawText,
    this.offsetMs = 0,
    this.lines = const [],
  });

  bool get hasLyrics =>
      lines.isNotEmpty || (rawText != null && rawText!.trim().isNotEmpty);

  /// Calculates the active lyric line index for a given playback position.
  int findActiveIndex(Duration currentPosition) {
    if (!isSynchronized || lines.isEmpty) return -1;
    return calculateActiveIndex(lines, currentPosition);
  }

  /// Calculates the active lyric line index given a list of [lines] and [currentPosition].
  static int calculateActiveIndex(
    List<LyricLine> lines,
    Duration currentPosition,
  ) {
    if (lines.isEmpty) return -1;
    final curMs = currentPosition.inMilliseconds;
    int activeIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestampMs <= curMs) {
        activeIndex = i;
      } else {
        break;
      }
    }
    return activeIndex;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackLyrics &&
          other.id == id &&
          other.trackId == trackId &&
          other.source == source &&
          other.isSynchronized == isSynchronized);

  @override
  int get hashCode => Object.hash(id, trackId, source, isSynchronized);
}
