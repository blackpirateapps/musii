import 'dart:math';

import '../entities/lyric_model.dart';

class ParsedLyricsResult {
  final List<LyricLine> lines;
  final bool isSynchronized;
  final int offsetMs;
  final Map<String, String> metadataTags;
  final String rawText;

  const ParsedLyricsResult({
    required this.lines,
    required this.isSynchronized,
    required this.offsetMs,
    required this.metadataTags,
    required this.rawText,
  });
}

class LrcParser {
  // Regex for standard LRC timestamps: [mm:ss.xx] or [mm:ss.xxx] or [hh:mm:ss.xx]
  static final RegExp _timestampPattern = RegExp(
    r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  static final RegExp _hourTimestampPattern = RegExp(
    r'\[(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  // Metadata tags e.g. [offset:+500] or [ar:Artist] or [ti:Title]
  static final RegExp _tagPattern = RegExp(r'^\[([a-zA-Z]+)\s*:\s*(.*)\]$');

  /// Checks whether a text contains valid synchronized timestamps.
  static bool hasTimestamps(String text) {
    if (text.isEmpty) return false;
    return _timestampPattern.hasMatch(text) ||
        _hourTimestampPattern.hasMatch(text);
  }

  /// Parses an LRC string or plain text lyrics.
  static ParsedLyricsResult parse(String? rawContent) {
    if (rawContent == null || rawContent.trim().isEmpty) {
      return const ParsedLyricsResult(
        lines: [],
        isSynchronized: false,
        offsetMs: 0,
        metadataTags: {},
        rawText: '',
      );
    }

    final raw = rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = raw.split('\n');

    final Map<String, String> tags = {};
    int offsetMs = 0;
    final List<_RawLineWithTime> timedLines = [];
    final List<String> plainLines = [];
    bool foundAnyTimestamp = false;

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Check for metadata tag e.g. [offset:+500] or [ti:Title]
      final tagMatch = _tagPattern.firstMatch(trimmed);
      if (tagMatch != null) {
        final key = tagMatch.group(1)!.toLowerCase();
        final value = tagMatch.group(2)!.trim();
        tags[key] = value;
        if (key == 'offset') {
          offsetMs = int.tryParse(value) ?? 0;
        }
        continue;
      }

      // Check for timestamps in the line
      // A line may have multiple timestamps: [00:10.00][00:20.00]Hello world
      final matches = _findAllTimestamps(trimmed);

      if (matches.isNotEmpty) {
        foundAnyTimestamp = true;
        // Strip all leading timestamp tags to get the lyric text
        final lyricText = trimmed
            .replaceAll(_timestampPattern, '')
            .replaceAll(_hourTimestampPattern, '')
            .trim();

        for (final timeMs in matches) {
          timedLines.add(_RawLineWithTime(timeMs, lyricText));
        }
      } else {
        // Plain text line
        plainLines.add(trimmed);
      }
    }

    if (foundAnyTimestamp && timedLines.isNotEmpty) {
      // Sort ascending by timestamp
      timedLines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

      // Apply offset (bounded to >= 0)
      final List<LyricLine> finalLines = [];
      for (int i = 0; i < timedLines.length; i++) {
        final item = timedLines[i];
        final adjustedTime = max(0, item.timestampMs + offsetMs);
        finalLines.add(
          LyricLine(timestampMs: adjustedTime, text: item.text, sequence: i),
        );
      }

      return ParsedLyricsResult(
        lines: finalLines,
        isSynchronized: true,
        offsetMs: offsetMs,
        metadataTags: tags,
        rawText: raw,
      );
    } else {
      // Treat as plain unsynchronized lyrics
      final List<LyricLine> finalLines = [];
      for (int i = 0; i < plainLines.length; i++) {
        finalLines.add(
          LyricLine(timestampMs: 0, text: plainLines[i], sequence: i),
        );
      }

      return ParsedLyricsResult(
        lines: finalLines,
        isSynchronized: false,
        offsetMs: 0,
        metadataTags: tags,
        rawText: raw,
      );
    }
  }

  static List<int> _findAllTimestamps(String line) {
    final List<int> results = [];

    // Check [mm:ss.xx]
    final matches = _timestampPattern.allMatches(line);
    for (final m in matches) {
      final minutes = int.tryParse(m.group(1) ?? '0') ?? 0;
      final seconds = int.tryParse(m.group(2) ?? '0') ?? 0;
      if (seconds >= 60) continue;
      final fractionStr = m.group(3);

      int fractionMs = 0;
      if (fractionStr != null) {
        if (fractionStr.length == 1) {
          fractionMs = (int.tryParse(fractionStr) ?? 0) * 100;
        } else if (fractionStr.length == 2) {
          fractionMs = (int.tryParse(fractionStr) ?? 0) * 10;
        } else {
          fractionMs = (int.tryParse(fractionStr.substring(0, 3)) ?? 0);
        }
      }

      final totalMs = (minutes * 60 + seconds) * 1000 + fractionMs;
      results.add(totalMs);
    }

    // Check [hh:mm:ss.xx]
    final hourMatches = _hourTimestampPattern.allMatches(line);
    for (final m in hourMatches) {
      final hours = int.tryParse(m.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(m.group(2) ?? '0') ?? 0;
      final seconds = int.tryParse(m.group(3) ?? '0') ?? 0;
      if (minutes >= 60 || seconds >= 60) continue;
      final fractionStr = m.group(4);

      int fractionMs = 0;
      if (fractionStr != null) {
        if (fractionStr.length == 1) {
          fractionMs = (int.tryParse(fractionStr) ?? 0) * 100;
        } else if (fractionStr.length == 2) {
          fractionMs = (int.tryParse(fractionStr) ?? 0) * 10;
        } else {
          fractionMs = (int.tryParse(fractionStr.substring(0, 3)) ?? 0);
        }
      }

      final totalMs =
          (hours * 3600 + minutes * 60 + seconds) * 1000 + fractionMs;
      results.add(totalMs);
    }

    return results;
  }
}

class _RawLineWithTime {
  final int timestampMs;
  final String text;
  _RawLineWithTime(this.timestampMs, this.text);
}
