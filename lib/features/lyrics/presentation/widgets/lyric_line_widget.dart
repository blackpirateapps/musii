import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../domain/entities/lyric_model.dart';
import 'word_synced_lyric_text.dart';

class LyricLineWidget extends ConsumerStatefulWidget {
  final LyricLine line;
  final Duration? position;
  final bool isActive;
  final bool isDark;
  final VoidCallback? onTap;
  final int? nextLineTimestampMs;
  final TextAlign textAlign;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;
  final bool enableScale;
  final bool enableSimulatedLineSweep;

  const LyricLineWidget({
    super.key,
    required this.line,
    this.position,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    this.nextLineTimestampMs,
    this.textAlign = TextAlign.left,
    this.alignment = Alignment.centerLeft,
    this.padding = const EdgeInsets.symmetric(vertical: 12.0),
    this.activeStyle,
    this.inactiveStyle,
    this.enableScale = true,
    this.enableSimulatedLineSweep = true,
  });

  @override
  ConsumerState<LyricLineWidget> createState() => _LyricLineWidgetState();
}

class _LyricLineWidgetState extends ConsumerState<LyricLineWidget>
    with SingleTickerProviderStateMixin {
  static const _maxExtrapolation = Duration(milliseconds: 500);

  Ticker? _clock;
  Duration? _positionAtAnchor;
  Duration _elapsed = Duration.zero;
  bool _advancing = false;
  int? _sweepEndMs;
  Duration _tickLimit = _maxExtrapolation;

  int get _sweepEnd => _sweepEndMs ??= widget.line.hasWords
      ? widget.line.words.fold<int>(
          widget.line.timestampMs,
          (end, word) => word.endMs > end ? word.endMs : end,
        )
      : widget.line.timestampMs +
            WordSyncedLyricText.simulatedSweepDurationMs(
              widget.line.timestampMs,
              widget.nextLineTimestampMs,
            );

  @override
  void didUpdateWidget(LyricLineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line ||
        oldWidget.nextLineTimestampMs != widget.nextLineTimestampMs) {
      _sweepEndMs = null;
      _positionAtAnchor = null;
    }
  }

  void _tick(Duration elapsed) {
    if (elapsed >= _tickLimit) {
      elapsed = _tickLimit;
      _clock?.stop();
    }
    if (_elapsed != elapsed) setState(() => _elapsed = elapsed);
  }

  Duration _positionForFrame({required bool reduceMotion}) {
    final needsClock =
        widget.isActive &&
        (widget.line.hasWords || widget.enableSimulatedLineSweep);
    if (!needsClock) {
      _clock?.stop();
      _positionAtAnchor = null;
      _advancing = false;
      return widget.position ?? Duration.zero;
    }

    final Duration position =
        widget.position ?? ref.watch(playbackPositionProvider);
    final remaining = Duration(milliseconds: _sweepEnd) - position;
    final advancing =
        !reduceMotion &&
        remaining > Duration.zero &&
        ref.watch(
          playerStateProvider.select((state) {
            final playback = state.value;
            return playback != null &&
                playback.isPlaying &&
                !playback.isBuffering;
          }),
        );
    if (_positionAtAnchor != position || _advancing != advancing) {
      _clock?.stop();
      _positionAtAnchor = position;
      _advancing = advancing;
      _elapsed = Duration.zero;
      if (advancing) {
        _tickLimit = remaining < _maxExtrapolation
            ? remaining
            : _maxExtrapolation;
        (_clock ??= createTicker(_tick)).start();
      }
    }
    return position + _elapsed;
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final effectivePosition = _positionForFrame(reduceMotion: reduceMotion);
    final transitionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);

    final activeColor = widget.isDark
        ? CupertinoColors.white
        : CupertinoColors.black;
    final inactiveColor = widget.isDark
        ? CupertinoColors.white.withOpacity(0.38)
        : CupertinoColors.black.withOpacity(0.38);

    final defaultActiveStyle = TextStyle(
      fontSize: 23,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.4,
      color: activeColor,
    );

    final defaultInactiveStyle = TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
      height: 1.4,
      color: inactiveColor,
    );

    final textStyle = widget.isActive
        ? (widget.activeStyle ?? defaultActiveStyle)
        : (widget.inactiveStyle ?? defaultInactiveStyle);

    final double scale = widget.enableScale
        ? (widget.isActive ? 1.0 : 0.97)
        : 1.0;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: widget.padding,
          child: AnimatedScale(
            scale: scale,
            alignment: widget.alignment,
            duration: transitionDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: transitionDuration,
              curve: Curves.easeOutCubic,
              style: textStyle,
              child: WordSyncedLyricText(
                line: widget.line,
                position: effectivePosition,
                isActive: widget.isActive,
                isDark: widget.isDark,
                style: textStyle,
                textAlign: widget.textAlign,
                nextLineTimestampMs: widget.nextLineTimestampMs,
                enableSimulatedLineSweep: widget.enableSimulatedLineSweep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
