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
  // Regex for standard LRC timestamps: [mm:ss.xx] or [mm:ss.xxx]
  static final RegExp _bracketTimestampPattern = RegExp(
    r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  static final RegExp _bracketHourTimestampPattern = RegExp(
    r'\[(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  // Regex for word-level timestamps: <mm:ss.xx> or <mm:ss.xxx>
  static final RegExp _angleTimestampPattern = RegExp(
    r'<(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?>',
  );

  static final RegExp _angleHourTimestampPattern = RegExp(
    r'<(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?>',
  );

  // Metadata tags e.g. [offset:+500] or [ar:Artist] or [ti:Title]
  static final RegExp _tagPattern = RegExp(r'^\[([a-zA-Z]+)\s*:\s*(.*)\]$');

  // Prefix for word-synced format e.g. "v1:"
  static final RegExp _v1PrefixPattern = RegExp(
    r'^v1:\s*',
    caseSensitive: false,
  );

  /// Checks whether a text contains valid synchronized timestamps or v1 word markup.
  static bool hasTimestamps(String text) {
    if (text.isEmpty) return false;
    return text.toLowerCase().contains('v1:') ||
        _bracketTimestampPattern.hasMatch(text) ||
        _bracketHourTimestampPattern.hasMatch(text) ||
        _angleTimestampPattern.hasMatch(text) ||
        _angleHourTimestampPattern.hasMatch(text);
  }

  /// Parses an LRC string, v1 word-synced format, or plain text lyrics.
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
    final List<_RawLineWithWords> timedLines = [];
    final List<String> plainLines = [];
    bool foundAnyTimestamp = false;

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 1. Check for metadata tag e.g. [offset:+500] or [ti:Title]
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

      // 2. Check for word-level synchronization (<mm:ss.xxx> or v1:<...>)
      if (_hasWordTimestamps(trimmed)) {
        foundAnyTimestamp = true;
        final wordLine = _parseWordSyncedLine(trimmed);
        if (wordLine != null) {
          timedLines.add(wordLine);
          continue;
        }
      }

      // 3. Check for standard line-level timestamps ([mm:ss.xx])
      final bracketMatches = _findAllBracketTimestamps(trimmed);
      if (bracketMatches.isNotEmpty) {
        foundAnyTimestamp = true;
        // Strip all leading bracket timestamps to get the line text
        final lyricText = trimmed
            .replaceAll(_bracketTimestampPattern, '')
            .replaceAll(_bracketHourTimestampPattern, '')
            .trim();

        for (final timeMs in bracketMatches) {
          timedLines.add(
            _RawLineWithWords(
              timestampMs: timeMs,
              text: lyricText,
              words: const [],
            ),
          );
        }
      } else {
        // 4. Plain text line
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
        final adjustedLineTime = max(0, item.timestampMs + offsetMs);

        final adjustedWords = item.words.map((w) {
          final adjStart = max(0, w.startMs + offsetMs);
          final adjEnd = max(adjStart, w.endMs + offsetMs);
          return LyricWord(
            index: w.index,
            text: w.text,
            startMs: adjStart,
            endMs: adjEnd,
          );
        }).toList();

        finalLines.add(
          LyricLine(
            timestampMs: adjustedLineTime,
            text: item.text,
            sequence: i,
            words: adjustedWords,
          ),
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

  static bool _hasWordTimestamps(String line) {
    return line.contains(_v1PrefixPattern) ||
        _angleTimestampPattern.hasMatch(line) ||
        _angleHourTimestampPattern.hasMatch(line);
  }

  static _RawLineWithWords? _parseWordSyncedLine(String rawLine) {
    // Strip leading v1: prefix if present
    String content = rawLine.replaceFirst(_v1PrefixPattern, '').trim();

    // Strip optional leading bracket timestamp e.g. [00:18.812]<00:18.812>
    content = content
        .replaceAll(_bracketTimestampPattern, '')
        .replaceAll(_bracketHourTimestampPattern, '')
        .trim();

    // Find all <mm:ss.xxx> or <hh:mm:ss.xxx> timestamp occurrences
    final matches = <_TimestampToken>[];

    for (final m in _angleTimestampPattern.allMatches(content)) {
      final ms = _parseAngleTimestamp(m);
      if (ms != null) {
        matches.add(_TimestampToken(ms, m.start, m.end));
      }
    }

    for (final m in _angleHourTimestampPattern.allMatches(content)) {
      final ms = _parseAngleHourTimestamp(m);
      if (ms != null) {
        matches.add(_TimestampToken(ms, m.start, m.end));
      }
    }

    if (matches.isEmpty) {
      return null;
    }

    // Sort timestamp tokens by position in the string
    matches.sort((a, b) => a.startIndex.compareTo(b.startIndex));

    final words = <LyricWord>[];
    int wordIndex = 0;

    for (int i = 0; i < matches.length; i++) {
      final currentMatch = matches[i];
      final nextStartIndex = (i + 1 < matches.length)
          ? matches[i + 1].startIndex
          : content.length;

      final rawWord = content.substring(currentMatch.endIndex, nextStartIndex);
      final cleanWord = rawWord.trim();

      if (cleanWord.isNotEmpty) {
        final startMs = currentMatch.timestampMs;
        int endMs;
        if (i + 1 < matches.length) {
          endMs = matches[i + 1].timestampMs;
        } else {
          endMs = startMs + 800;
        }

        if (endMs <= startMs) {
          endMs = startMs + 100;
        }

        words.add(
          LyricWord(
            index: wordIndex++,
            text: cleanWord,
            startMs: startMs,
            endMs: endMs,
          ),
        );
      }
    }

    if (words.isEmpty) {
      return null;
    }

    final lineText = words.map((w) => w.text).join(' ');
    final lineStartMs = words.first.startMs;

    return _RawLineWithWords(
      timestampMs: lineStartMs,
      text: lineText,
      words: words,
    );
  }

  static int? _parseAngleTimestamp(Match m) {
    final minutes = int.tryParse(m.group(1) ?? '0') ?? 0;
    final seconds = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (seconds >= 60) return null;
    final fractionStr = m.group(3);

    int fractionMs = 0;
    if (fractionStr != null) {
      if (fractionStr.length == 1) {
        fractionMs = (int.tryParse(fractionStr) ?? 0) * 100;
      } else if (fractionStr.length == 2) {
        fractionMs = (int.tryParse(fractionStr) ?? 0) * 10;
      } else {
        fractionMs = int.tryParse(fractionStr.substring(0, 3)) ?? 0;
      }
    }

    return (minutes * 60 + seconds) * 1000 + fractionMs;
  }

  static int? _parseAngleHourTimestamp(Match m) {
    final hours = int.tryParse(m.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(m.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(m.group(3) ?? '0') ?? 0;
    if (minutes >= 60 || seconds >= 60) return null;
    final fractionStr = m.group(4);

    int fractionMs = 0;
    if (fractionStr != null) {
      if (fractionStr.length == 1) {
        fractionMs = (int.tryParse(fractionStr) ?? 0) * 100;
      } else if (fractionStr.length == 2) {
        fractionMs = (int.tryParse(fractionStr) ?? 0) * 10;
      } else {
        fractionMs = int.tryParse(fractionStr.substring(0, 3)) ?? 0;
      }
    }

    return (hours * 3600 + minutes * 60 + seconds) * 1000 + fractionMs;
  }

  static List<int> _findAllBracketTimestamps(String line) {
    final List<int> results = [];

    // Check [mm:ss.xx]
    final matches = _bracketTimestampPattern.allMatches(line);
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
    final hourMatches = _bracketHourTimestampPattern.allMatches(line);
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

class _TimestampToken {
  final int timestampMs;
  final int startIndex;
  final int endIndex;

  _TimestampToken(this.timestampMs, this.startIndex, this.endIndex);
}

class _RawLineWithWords {
  final int timestampMs;
  final String text;
  final List<LyricWord> words;

  _RawLineWithWords({
    required this.timestampMs,
    required this.text,
    required this.words,
  });
}
