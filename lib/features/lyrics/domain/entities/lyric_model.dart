import 'package:flutter/foundation.dart';

@immutable
class LyricWord {
  final int startMs;
  final int endMs;
  final String text;
  final int index;

  const LyricWord({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.index = 0,
  });

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: endMs);
  Duration get duration => Duration(milliseconds: endMs - startMs);

  double progressAt(Duration position) {
    final posMs = position.inMilliseconds;
    if (posMs <= startMs) return 0.0;
    if (posMs >= endMs) return 1.0;
    final total = endMs - startMs;
    if (total <= 0) return 1.0;
    return ((posMs - startMs) / total).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricWord &&
          other.startMs == startMs &&
          other.endMs == endMs &&
          other.text == text &&
          other.index == index);

  @override
  int get hashCode => Object.hash(startMs, endMs, text, index);

  @override
  String toString() =>
      'LyricWord(index: $index, text: "$text", startMs: $startMs, endMs: $endMs)';
}

@immutable
class LyricLine {
  final int timestampMs;
  final String text;
  final int sequence;
  final List<LyricWord> words;

  const LyricLine({
    required this.timestampMs,
    required this.text,
    this.sequence = 0,
    this.words = const [],
  });

  bool get hasWords => words.isNotEmpty;

  /// Returns the index of the currently active word in this line for a given [position].
  /// Returns null if position is before the first word.
  /// If position is after the last word, returns the last word index.
  int? findActiveWordIndex(Duration position) {
    if (words.isEmpty) return null;
    final curMs = position.inMilliseconds;
    if (curMs < words.first.startMs) return null;
    for (int i = 0; i < words.length; i++) {
      if (curMs >= words[i].startMs && curMs < words[i].endMs) {
        return i;
      }
    }
    if (curMs >= words.last.endMs) {
      return words.length - 1;
    }
    for (int i = 0; i < words.length - 1; i++) {
      if (curMs >= words[i].endMs && curMs < words[i + 1].startMs) {
        return i;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricLine &&
          other.timestampMs == timestampMs &&
          other.text == text &&
          other.sequence == sequence &&
          listEquals(other.words, words));

  @override
  int get hashCode =>
      Object.hash(timestampMs, text, sequence, Object.hashAll(words));

  @override
  String toString() =>
      'LyricLine(timestampMs: $timestampMs, sequence: $sequence, text: $text, words: ${words.length})';
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

  bool get hasWordTiming => lines.any((line) => line.hasWords);

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
          other.isSynchronized == isSynchronized &&
          listEquals(other.lines, lines));

  @override
  int get hashCode =>
      Object.hash(id, trackId, source, isSynchronized, Object.hashAll(lines));
}
