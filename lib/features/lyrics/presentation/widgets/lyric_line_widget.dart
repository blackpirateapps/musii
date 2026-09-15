import 'package:flutter/cupertino.dart';

import '../../domain/entities/lyric_model.dart';
import 'word_synced_lyric_text.dart';

class LyricLineWidget extends StatelessWidget {
  final LyricLine line;
  final Duration position;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const LyricLineWidget({
    super.key,
    required this.line,
    required this.position,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    final inactiveColor = isDark
        ? CupertinoColors.white.withOpacity(0.38)
        : CupertinoColors.black.withOpacity(0.38);

    final textStyle = TextStyle(
      fontSize: isActive ? 23 : 19,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: isActive ? -0.3 : -0.2,
      height: 1.4,
      color: isActive ? activeColor : inactiveColor,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: AnimatedScale(
          scale: isActive ? 1.0 : 0.97,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            style: textStyle,
            child: WordSyncedLyricText(
              line: line,
              position: position,
              isActive: isActive,
              isDark: isDark,
              style: textStyle,
            ),
          ),
        ),
      ),
    );
  }
}
