import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../domain/entities/lyric_model.dart';
import 'word_synced_lyric_text.dart';

class LyricLineWidget extends ConsumerStatefulWidget {
  final LyricLine line;
  final Duration? position;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;
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
  late final AnimationController _extrapolationController;
  double _anchorPositionMs = 0.0;
  Duration _smoothPosition = Duration.zero;
  bool _isPlaying = false;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _extrapolationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_onExtrapolationTick);

    if (widget.isActive) {
      _initClock();
    }
  }

  void _initClock() {
    final Duration pos = widget.position ?? ref.read(playbackPositionProvider);
    final posMs = pos.inMilliseconds.toDouble();
    _anchorPositionMs = posMs;
    _smoothPosition = Duration(milliseconds: posMs.round());

    final isPlaying = ref.read(
      playerStateProvider.select((s) => s.value?.isPlaying ?? false),
    );
    _isPlaying = isPlaying;
    _speed = 1.0;

    final bool needsVsync =
        widget.line.hasWords || widget.enableSimulatedLineSweep;
    if (_isPlaying && needsVsync) {
      _extrapolationController.forward(from: 0.0);
    }
  }

  void _onExtrapolationTick() {
    if (!mounted || !widget.isActive) {
      _extrapolationController.stop();
      return;
    }
    if (!_isPlaying) {
      _extrapolationController.stop();
      return;
    }

    final elapsedMs = _extrapolationController.value * 500.0 * _speed;
    final extrapolatedMs = _anchorPositionMs + elapsedMs;
    final nextPos = Duration(milliseconds: extrapolatedMs.round());

    if (nextPos != _smoothPosition) {
      setState(() {
        _smoothPosition = nextPos;
      });
    }
  }

  @override
  void didUpdateWidget(LyricLineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _initClock();
      } else {
        _extrapolationController.stop();
        _smoothPosition = Duration.zero;
      }
    } else if (widget.isActive &&
        widget.position != null &&
        widget.position != oldWidget.position) {
      _onPositionUpdated(widget.position!.inMilliseconds.toDouble());
    }
  }

  void _onPositionUpdated(double rawMs) {
    if (!mounted || !widget.isActive) return;

    final currentCalcMs =
        _anchorPositionMs + (_extrapolationController.value * 500.0 * _speed);
    final diff = (rawMs - currentCalcMs).abs();

    final bool needsVsync =
        widget.line.hasWords || widget.enableSimulatedLineSweep;
    if (diff > 300) {
      // Seek or jump: snap immediately
      _anchorPositionMs = rawMs;
      _smoothPosition = Duration(milliseconds: rawMs.round());
      if (_isPlaying && needsVsync) {
        _extrapolationController.forward(from: 0.0);
      }
    } else {
      // Minor audio clock drift: blend anchor smoothly
      _anchorPositionMs = (currentCalcMs + rawMs) / 2.0;
      if (_isPlaying && needsVsync) {
        _extrapolationController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _extrapolationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Duration effectivePosition;

    if (widget.isActive) {
      final Duration rawPos =
          widget.position ?? ref.watch(playbackPositionProvider);
      final isPlaying = ref.watch(
        playerStateProvider.select((s) => s.value?.isPlaying ?? false),
      );

      final isPlayingChanged = (isPlaying != _isPlaying);
      _isPlaying = isPlaying;
      _speed = 1.0;

      final bool needsVsync =
          widget.line.hasWords || widget.enableSimulatedLineSweep;
      final rawMs = rawPos.inMilliseconds.toDouble();
      if ((rawMs - _anchorPositionMs).abs() > 0.001) {
        _onPositionUpdated(rawMs);
      } else if (isPlayingChanged) {
        if (_isPlaying && needsVsync) {
          _extrapolationController.forward(from: 0.0);
        } else {
          _extrapolationController.stop();
        }
      }

      effectivePosition = _smoothPosition;
    } else {
      effectivePosition = widget.position ?? Duration.zero;
    }

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
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 280),
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
