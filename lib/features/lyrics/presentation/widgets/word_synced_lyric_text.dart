import 'package:flutter/cupertino.dart';

import '../../domain/entities/lyric_model.dart';

class WordSyncedLyricText extends StatelessWidget {
  final LyricLine line;
  final Duration position;
  final bool isActive;
  final bool isDark;
  final TextStyle style;
  final TextAlign textAlign;
  final int? nextLineTimestampMs;

  const WordSyncedLyricText({
    super.key,
    required this.line,
    required this.position,
    required this.isActive,
    required this.isDark,
    required this.style,
    this.textAlign = TextAlign.left,
    this.nextLineTimestampMs,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    final inactiveColor = isDark
        ? CupertinoColors.white.withOpacity(0.38)
        : CupertinoColors.black.withOpacity(0.38);

    // 1. If no word timing data (standard LRC):
    if (!line.hasWords) {
      if (!isActive) {
        return Text(
          line.text.isNotEmpty ? line.text : '♪',
          style: style.copyWith(color: inactiveColor),
          textAlign: textAlign,
        );
      }

      // Simulated line-wide progressive sweep across the line duration
      final curMs = position.inMilliseconds;
      final startMs = line.timestampMs;
      final nextMs = nextLineTimestampMs ?? (startMs + 3500);
      final rawDuration = nextMs - startMs;
      final lineDuration = rawDuration > 0
          ? rawDuration.clamp(1200, 4500)
          : 3500;
      final progress = curMs <= startMs
          ? 0.0
          : ((curMs - startMs) / lineDuration).clamp(0.0, 1.0);

      return _FeatheredProgressText(
        text: line.text.isNotEmpty ? line.text : '♪',
        progress: progress,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        style: style,
        isDark: isDark,
        textAlign: textAlign,
        featherPx: 14.0,
      );
    }

    // 2. Inactive line with word timing: render all words with inactive styling
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

    // 3. Active line with word timing: continuous in-place feathered glyph reveal
    final spans = <InlineSpan>[];

    for (int i = 0; i < line.words.length; i++) {
      final word = line.words[i];
      final progress = word.progressAt(position);

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _FeatheredProgressText(
            text: word.text,
            progress: progress,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            style: style,
            isDark: isDark,
            textAlign: textAlign,
            featherPx: 8.0,
          ),
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
}

/// Progressive text renderer supporting continuous 60/120 FPS left-to-right
/// fill with Apple Music-grade feathered leading edge and subtle vocal glow.
class _FeatheredProgressText extends StatelessWidget {
  final String text;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final TextStyle style;
  final bool isDark;
  final TextAlign textAlign;
  final double featherPx;

  const _FeatheredProgressText({
    required this.text,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.style,
    required this.isDark,
    this.textAlign = TextAlign.left,
    this.featherPx = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);

    // If not yet started: render pure inactive text (zero GPU shader overhead)
    if (clampedProgress <= 0.0) {
      return Text(
        text,
        style: style.copyWith(color: inactiveColor),
        textAlign: textAlign,
      );
    }

    // If completely sung: render 100% active text (zero GPU shader overhead)
    if (clampedProgress >= 1.0) {
      return Text(
        text,
        style: style.copyWith(color: activeColor),
        textAlign: textAlign,
      );
    }

    // Active progressive state: Apple Music subtle luminescence and contrast accent
    final glowShadow = isDark
        ? [
            Shadow(
              color: CupertinoColors.white.withOpacity(0.45),
              blurRadius: 8.0,
            ),
          ]
        : [
            Shadow(
              color: CupertinoColors.black.withOpacity(0.22),
              blurRadius: 4.0,
            ),
          ];

    final activeGlowStyle = style.copyWith(
      color: CupertinoColors.white,
      shadows: glowShadow,
    );

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        if (bounds.width <= 0) {
          return LinearGradient(colors: [inactiveColor, inactiveColor])
              .createShader(bounds);
        }

        final width = bounds.width;
        final featherFraction = (featherPx / width).clamp(0.005, 0.45);

        final stop1 = (clampedProgress - featherFraction).clamp(0.0, 1.0);
        final stop2 = clampedProgress;

        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [activeColor, activeColor, inactiveColor, inactiveColor],
          stops: [0.0, stop1, stop2, 1.0],
        ).createShader(bounds);
      },
      child: Text(text, style: activeGlowStyle, textAlign: textAlign),
    );
  }
}
