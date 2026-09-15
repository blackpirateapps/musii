import 'package:flutter/cupertino.dart';

import '../../domain/entities/lyric_model.dart';

class WordSyncedLyricText extends StatelessWidget {
  final LyricLine line;
  final Duration position;
  final bool isActive;
  final bool isDark;
  final TextStyle style;
  final TextAlign textAlign;

  const WordSyncedLyricText({
    super.key,
    required this.line,
    required this.position,
    required this.isActive,
    required this.isDark,
    required this.style,
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    final inactiveColor = isDark
        ? CupertinoColors.white.withOpacity(0.38)
        : CupertinoColors.black.withOpacity(0.38);

    // If no word timing data, render line text
    if (!line.hasWords) {
      return Text(
        line.text.isNotEmpty ? line.text : '♪',
        style: style.copyWith(color: isActive ? activeColor : inactiveColor),
        textAlign: textAlign,
      );
    }

    // Inactive line: render all words with inactive styling
    if (!isActive) {
      final spans = <InlineSpan>[];
      for (int i = 0; i < line.words.length; i++) {
        spans.add(
          TextSpan(
            text: line.words[i].text,
            style: style.copyWith(color: inactiveColor),
          ),
        );
        if (i < line.words.length - 1) {
          spans.add(
            TextSpan(
              text: ' ',
              style: style.copyWith(color: inactiveColor),
            ),
          );
        }
      }
      return RichText(
        text: TextSpan(children: spans),
        textAlign: textAlign,
      );
    }

    // Active line with word timing: render continuous progressive in-place highlight
    final curMs = position.inMilliseconds;
    final spans = <InlineSpan>[];

    for (int i = 0; i < line.words.length; i++) {
      final word = line.words[i];

      if (curMs >= word.endMs) {
        // Completed word: fully highlighted
        spans.add(
          TextSpan(
            text: word.text,
            style: style.copyWith(color: activeColor),
          ),
        );
      } else if (curMs < word.startMs) {
        // Future word: muted
        spans.add(
          TextSpan(
            text: word.text,
            style: style.copyWith(color: inactiveColor),
          ),
        );
      } else {
        // Current active word: progressive in-place glyph highlight
        final progress = word.progressAt(position);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _ProgressiveWordSpan(
              text: word.text,
              progress: progress,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              style: style,
            ),
          ),
        );
      }

      if (i < line.words.length - 1) {
        final spaceColor = curMs >= word.endMs ? activeColor : inactiveColor;
        spans.add(
          TextSpan(
            text: ' ',
            style: style.copyWith(color: spaceColor),
          ),
        );
      }
    }

    return RichText(
      text: TextSpan(children: spans),
      textAlign: textAlign,
    );
  }
}

class _ProgressiveWordSpan extends StatelessWidget {
  final String text;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final TextStyle style;

  const _ProgressiveWordSpan({
    required this.text,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base layer: inactive muted glyphs
        Text(text, style: style.copyWith(color: inactiveColor)),
        // Overlay layer: active contrast glyphs clipped to current progress
        ClipRect(
          clipper: _HorizontalFractionClipper(progress),
          child: Text(text, style: style.copyWith(color: activeColor)),
        ),
      ],
    );
  }
}

class _HorizontalFractionClipper extends CustomClipper<Rect> {
  final double fraction;

  const _HorizontalFractionClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    final clamped = fraction.clamp(0.0, 1.0);
    return Rect.fromLTRB(0, 0, size.width * clamped, size.height);
  }

  @override
  bool shouldReclip(_HorizontalFractionClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}
