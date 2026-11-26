import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../lyrics/domain/entities/lyric_model.dart';
import '../../../lyrics/presentation/pages/lyrics_sheet.dart';
import '../../../lyrics/presentation/widgets/lyric_line_widget.dart';

/// Phase of the continuous vertical lyrics reel.
enum _ReelPhase { singing, intro, gap, outro }

/// Unified snapshot of the active 3-line contextual lyrics window.
class _ReelSlotData {
  final _ReelPhase phase;
  final int activeIndex;
  final int targetMs;
  final LyricLine? prevLine;
  final LyricLine? activeLine;
  final LyricLine? upcomingLine;

  const _ReelSlotData({
    required this.phase,
    required this.activeIndex,
    this.targetMs = 0,
    this.prevLine,
    this.activeLine,
    this.upcomingLine,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ReelSlotData &&
        other.phase == phase &&
        other.activeIndex == activeIndex &&
        other.targetMs == targetMs &&
        other.activeLine?.timestampMs == activeLine?.timestampMs &&
        other.upcomingLine?.timestampMs == upcomingLine?.timestampMs;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    activeIndex,
    targetMs,
    activeLine?.timestampMs,
    upcomingLine?.timestampMs,
  );
}

/// Apple Music-grade animated vocal dots with 3..2..1 countdown.
class _VocalCountdownDots extends StatelessWidget {
  final int targetMs;
  final int currentMs;
  final bool isDark;
  final bool disableAnimations;

  const _VocalCountdownDots({
    required this.targetMs,
    required this.currentMs,
    required this.isDark,
    this.disableAnimations = false,
  });

  @override
  Widget build(BuildContext context) {
    final remainingMs = targetMs > 0 ? (targetMs - currentMs) : -1;
    final isCountingDown = remainingMs > 0 && remainingMs <= 3000;
    final baseColor = isDark ? CupertinoColors.white : const Color(0xFF0C0D12);

    // Number of ignited dots (3s left = 1 dot, 2s left = 2 dots, 1s left = 3 dots)
    final int activeDots;
    if (!isCountingDown) {
      activeDots = 0;
    } else if (remainingMs > 2000) {
      activeDots = 1;
    } else if (remainingMs > 1000) {
      activeDots = 2;
    } else {
      activeDots = 3;
    }

    // Audio-synced harmonic breathing phase
    final cycleProgress = ((currentMs.abs() % 2400) / 2400.0);

    final remainingSec = isCountingDown ? (remainingMs / 1000).ceil() : 0;
    final semanticsLabel = isCountingDown
        ? 'Vocals start in $remainingSec'
        : 'Instrumental section';

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        height: 32,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (index) {
              final isLit = index < activeDots;
              double dotOpacity;
              double dotScale = 1.0;

              if (isCountingDown) {
                if (isLit) {
                  dotOpacity = 1.0;
                  if (!disableAnimations) {
                    final secRemaining = 3 - index;
                    final timeAtBeat = targetMs - (secRemaining * 1000);
                    final elapsedSinceBeat = currentMs - timeAtBeat;
                    if (elapsedSinceBeat >= 0 && elapsedSinceBeat < 300) {
                      final p = elapsedSinceBeat / 300.0;
                      dotScale = 1.0 + 0.35 * (1.0 - p);
                    }
                  }
                } else {
                  dotOpacity = 0.22;
                }
              } else {
                if (disableAnimations) {
                  dotOpacity = 0.35;
                } else {
                  final phase = (cycleProgress * 2 * math.pi) - (index * 0.55);
                  dotOpacity = (0.28 + 0.22 * math.sin(phase)).clamp(
                    0.18,
                    0.65,
                  );
                }
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                child: Transform.scale(
                  scale: dotScale,
                  child: Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: baseColor.withOpacity(dotOpacity),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Cinematic inline synchronized lyrics display for the Now Playing screen.
///
/// Sits between track metadata and the playback scrubber, rendering a continuous
/// vertical scrolling reel with a 3-line contextual flow, animated vocal dots
/// during instrumental passages, and word-by-word progressive highlights.
class NowPlayingInlineLyrics extends ConsumerStatefulWidget {
  final Track? track;
  final bool isCompactScreen;

  const NowPlayingInlineLyrics({
    super.key,
    required this.track,
    this.isCompactScreen = false,
  });

  @override
  ConsumerState<NowPlayingInlineLyrics> createState() =>
      _NowPlayingInlineLyricsState();
}

class _NowPlayingInlineLyricsState
    extends ConsumerState<NowPlayingInlineLyrics> {
  _ReelSlotData _slotData = const _ReelSlotData(
    phase: _ReelPhase.singing,
    activeIndex: -1,
  );
  Duration _currentPosition = Duration.zero;

  TrackLyrics? _positionedLyrics;

  int _estimateLineDuration(List<LyricLine> lines, int index) {
    final line = lines[index];
    if (line.hasWords) {
      final actualDuration = line.words.last.endMs - line.timestampMs;
      return actualDuration > 0 ? actualDuration : 3500;
    }
    if (index + 1 < lines.length) {
      final diff = lines[index + 1].timestampMs - line.timestampMs;
      if (diff > 0) return diff.clamp(1200, 4500);
    }
    return 3500;
  }

  _ReelSlotData _calculateSlotData(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) {
      return const _ReelSlotData(phase: _ReelPhase.singing, activeIndex: -1);
    }
    final curMs = position.inMilliseconds;
    final firstLine = lines.first;
    final activeIndex = TrackLyrics.calculateActiveIndex(lines, position);

    // 1. Instrumental Intro Check
    if (activeIndex == -1) {
      if (curMs < firstLine.timestampMs - 200 &&
          firstLine.timestampMs >= 1500) {
        return _ReelSlotData(
          phase: _ReelPhase.intro,
          activeIndex: -1,
          targetMs: firstLine.timestampMs,
          upcomingLine: firstLine,
        );
      }
      return _ReelSlotData(
        phase: _ReelPhase.singing,
        activeIndex: 0,
        activeLine: firstLine,
        upcomingLine: lines.length > 1 ? lines[1] : null,
      );
    }

    if (activeIndex >= 0 && activeIndex < lines.length) {
      final current = lines[activeIndex];
      final lineEndMs = current.hasWords
          ? current.words.last.endMs
          : (current.timestampMs + _estimateLineDuration(lines, activeIndex));
      final int? nextMs = (activeIndex + 1 < lines.length)
          ? lines[activeIndex + 1].timestampMs
          : null;

      // 2. Mid-Song Instrumental Gap Check
      if (nextMs != null && (nextMs - lineEndMs >= 3500)) {
        if (curMs >= lineEndMs + 800 && curMs < nextMs) {
          return _ReelSlotData(
            phase: _ReelPhase.gap,
            activeIndex: activeIndex,
            targetMs: nextMs,
            prevLine: current,
            activeLine: current, // Preserved for fade-out and opacity tests
            upcomingLine: lines[activeIndex + 1],
          );
        }
      }

      // 3. Instrumental Outro Check
      if (activeIndex == lines.length - 1 && curMs >= lineEndMs + 1000) {
        return _ReelSlotData(
          phase: _ReelPhase.outro,
          activeIndex: activeIndex,
          prevLine: current,
        );
      }

      // 4. Normal Singing
      return _ReelSlotData(
        phase: _ReelPhase.singing,
        activeIndex: activeIndex,
        prevLine: activeIndex > 0 ? lines[activeIndex - 1] : null,
        activeLine: current,
        upcomingLine: activeIndex + 1 < lines.length
            ? lines[activeIndex + 1]
            : null,
      );
    }

    return const _ReelSlotData(phase: _ReelPhase.singing, activeIndex: -1);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final enabled = ref.watch(inlineLyricsEnabledProvider);
    if (enabled && !widget.isCompactScreen && track?.youtubeVideoId != null) {
      ref.watch(youtubeMusicLyricsProvider(track!));
    }
    final lyrics = enabled && !widget.isCompactScreen && track != null
        ? ref.watch(trackLyricsProvider(track.id)).value
        : null;
    final shouldShow =
        lyrics != null &&
        lyrics.trackId == track?.id &&
        lyrics.isSynchronized &&
        lyrics.lines.isNotEmpty;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    if (shouldShow) {
      if (!identical(_positionedLyrics, lyrics)) {
        _positionedLyrics = lyrics;
        _currentPosition = ref.read(playbackPositionProvider);
        _slotData = _calculateSlotData(lyrics.lines, _currentPosition);
      }

      ref.listen<Duration>(playbackPositionProvider, (previous, next) {
        if (ref.read(playerStateProvider).value?.currentTrack?.id !=
            track?.id) {
          return;
        }
        final newSlotData = _calculateSlotData(lyrics.lines, next);
        final remainingMs = newSlotData.targetMs - next.inMilliseconds;
        final isCountdown = remainingMs > 0 && remainingMs <= 3000;
        if (newSlotData != _slotData || isCountdown) {
          setState(() {
            _slotData = newSlotData;
            _currentPosition = next;
          });
        }
      });
    } else {
      _positionedLyrics = null;
    }

    void openLyrics() {
      if (track != null) showLyricsSheet(context, track, followPlayback: true);
    }

    final content = shouldShow
        ? Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 2,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: openLyrics,
              child: SizedBox(
                width: double.infinity,
                height: 108,
                child: _InlineLyricsReel(
                  key: ValueKey(track!.id),
                  slotData: _slotData,
                  currentPosition: _currentPosition,
                  isDark: true,
                  disableAnimations: disableAnimations,
                  onTap: openLyrics,
                ),
              ),
            ),
          )
        : const SizedBox(width: double.infinity, height: 0);

    if (disableAnimations) return content;
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        opacity: shouldShow ? 1 : 0,
        child: content,
      ),
    );
  }
}

/// Continuous vertical scrolling reel coordinator.
class _InlineLyricsReel extends StatefulWidget {
  final _ReelSlotData slotData;
  final Duration currentPosition;
  final bool isDark;
  final bool disableAnimations;
  final VoidCallback? onTap;

  const _InlineLyricsReel({
    super.key,
    required this.slotData,
    required this.currentPosition,
    required this.isDark,
    this.disableAnimations = false,
    this.onTap,
  });

  @override
  State<_InlineLyricsReel> createState() => _InlineLyricsReelState();
}

class _InlineLyricsReelState extends State<_InlineLyricsReel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rollController;
  late final Animation<double> _curvedRoll;

  _ReelSlotData? _fromSlotData;
  late _ReelSlotData _toSlotData;
  int _direction = 1; // 1 for forward, -1 for backward

  @override
  void initState() {
    super.initState();
    _toSlotData = widget.slotData;
    _rollController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _curvedRoll = CurvedAnimation(
      parent: _rollController,
      curve: Curves.easeOutCubic,
    );
    _rollController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _fromSlotData = null;
          _rollController.reset();
        });
      }
    });
  }

  @override
  void didUpdateWidget(_InlineLyricsReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.slotData != oldWidget.slotData) {
      final old = oldWidget.slotData;
      final next = widget.slotData;

      if (widget.disableAnimations) {
        _fromSlotData = null;
        _toSlotData = next;
        _rollController.reset();
        return;
      }

      // Check if advancing forward by 1 step
      final isStepForward =
          (next.activeIndex == old.activeIndex + 1) ||
          (old.phase == _ReelPhase.intro &&
              next.phase == _ReelPhase.singing &&
              next.activeIndex == 0) ||
          (old.phase == _ReelPhase.singing && next.phase == _ReelPhase.gap) ||
          (old.phase == _ReelPhase.gap &&
              next.phase == _ReelPhase.singing &&
              next.activeIndex == old.activeIndex + 1);

      // Check if seeking backward by 1 step
      final isStepBackward =
          (next.activeIndex == old.activeIndex - 1) ||
          (old.phase == _ReelPhase.singing && next.phase == _ReelPhase.intro) ||
          (old.phase == _ReelPhase.gap &&
              next.phase == _ReelPhase.singing &&
              next.activeIndex == old.activeIndex);

      if (isStepForward) {
        _fromSlotData = old;
        _toSlotData = next;
        _direction = 1;
        _rollController.forward(from: 0.0);
      } else if (isStepBackward) {
        _fromSlotData = old;
        _toSlotData = next;
        _direction = -1;
        _rollController.forward(from: 0.0);
      } else {
        // Multi-line scrub jump: snap directly to destination
        _fromSlotData = null;
        _toSlotData = next;
        _rollController.reset();
      }
    }
  }

  @override
  void dispose() {
    _rollController.dispose();
    super.dispose();
  }

  Widget _buildLineItem({
    required double centerY,
    required double scale,
    required double opacity,
    required LyricLine? line,
    required bool isCenterHero,
    required bool showDots,
    required int targetMs,
    required int currentMs,
    required bool isDark,
    bool isInstrumentalHero = false,
  }) {
    if (showDots) {
      return Positioned(
        top: centerY - 16.0,
        left: 0,
        right: 0,
        height: 32.0,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: _VocalCountdownDots(
              targetMs: targetMs,
              currentMs: currentMs,
              isDark: isDark,
              disableAnimations: widget.disableAnimations,
            ),
          ),
        ),
      );
    }

    if (line == null || line.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final textBaseColor = isDark
        ? CupertinoColors.white
        : const Color(0xFF0C0D12);

    if (isCenterHero) {
      return Positioned(
        top: centerY - 28.0,
        left: 0,
        right: 0,
        height: 56.0,
        child: Semantics(
          key: ValueKey('inline_current_${line.timestampMs}_${line.sequence}'),
          label: 'Current lyric: ${line.text}',
          child: Transform.scale(
            scale: scale,
            child: AnimatedOpacity(
              duration: widget.disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              opacity: isInstrumentalHero ? 0.0 : opacity.clamp(0.0, 1.0),
              child: Center(
                child: LyricLineWidget(
                  line: line,
                  isActive: true,
                  isDark: isDark,
                  enableScale: false,
                  enableSimulatedLineSweep: false,
                  textAlign: TextAlign.center,
                  alignment: Alignment.center,
                  padding: EdgeInsets.zero,
                  activeStyle: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.35,
                    color: textBaseColor,
                  ),
                  inactiveStyle: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.35,
                    color: textBaseColor.withOpacity(0.38),
                  ),
                  onTap: widget.onTap ?? () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Non-hero slot (preview or previous line)
    return Positioned(
      top: centerY - 12.0,
      left: 0,
      right: 0,
      height: 24.0,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Center(
            child: Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textBaseColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pitch = 36.0;
    const previousOpacity = 0.64;
    const upcomingOpacity = 0.76;
    final currentMs = widget.currentPosition.inMilliseconds;
    final isDark = widget.isDark;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0.0, 0.14, 0.86, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: AnimatedBuilder(
        animation: _curvedRoll,
        builder: (context, child) {
          final isRolling =
              _fromSlotData != null && _rollController.isAnimating;

          if (!isRolling) {
            // Steady State Display (No roll active)
            final currentLine = _toSlotData.activeLine;
            final isInstrumental = _toSlotData.phase != _ReelPhase.singing;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Top Slot: Previous line
                if (_toSlotData.prevLine != null)
                  _buildLineItem(
                    centerY: 18.0,
                    scale: 0.72,
                    opacity: previousOpacity,
                    line: _toSlotData.prevLine,
                    isCenterHero: false,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),

                // Center Slot: Hero Lyric OR Vocal Countdown Dots
                if (currentLine != null)
                  _buildLineItem(
                    centerY: 54.0,
                    scale: 1.0,
                    opacity: 1.0,
                    line: currentLine,
                    isCenterHero: true,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                    isInstrumentalHero: isInstrumental,
                  ),

                if (isInstrumental)
                  _buildLineItem(
                    centerY: 54.0,
                    scale: 1.0,
                    opacity: 1.0,
                    line: null,
                    isCenterHero: false,
                    showDots: true,
                    targetMs: _toSlotData.targetMs,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),

                // Bottom Slot: Upcoming line preview
                if (_toSlotData.upcomingLine != null)
                  _buildLineItem(
                    centerY: 90.0,
                    scale: 0.72,
                    opacity: upcomingOpacity,
                    line: _toSlotData.upcomingLine,
                    isCenterHero: false,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),
              ],
            );
          }

          // Active Continuous Vertical Roll (380ms easeOutCubic)
          final t = _curvedRoll.value;
          final dy = -1.0 * _direction * t * pitch;
          final from = _fromSlotData!;
          final to = _toSlotData;

          if (_direction == 1) {
            // Forward Roll
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Old top exits past top fade
                if (from.prevLine != null)
                  _buildLineItem(
                    centerY: 18.0 + dy,
                    scale: 0.72,
                    opacity: (1.0 - t) * previousOpacity,
                    line: from.prevLine,
                    isCenterHero: false,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),

                // 2. Old center rolls up to top slot
                _buildLineItem(
                  centerY: 54.0 + dy,
                  scale: 1.0 - (0.28 * t),
                  opacity: 1.0 - ((1 - previousOpacity) * t),
                  line: from.activeLine,
                  isCenterHero: false,
                  showDots: from.phase != _ReelPhase.singing,
                  targetMs: from.targetMs,
                  currentMs: currentMs,
                  isDark: isDark,
                ),

                // 3. Old bottom rolls up to center spotlight
                _buildLineItem(
                  centerY: 90.0 + dy,
                  scale: 0.72 + (0.28 * t),
                  opacity: upcomingOpacity + ((1 - upcomingOpacity) * t),
                  line: to.activeLine ?? from.upcomingLine,
                  isCenterHero: to.phase == _ReelPhase.singing,
                  showDots: to.phase != _ReelPhase.singing,
                  targetMs: to.targetMs,
                  currentMs: currentMs,
                  isDark: isDark,
                ),

                // 4. New bottom emerges into preview slot
                if (to.upcomingLine != null)
                  _buildLineItem(
                    centerY: 126.0 + dy,
                    scale: 0.72,
                    opacity: t * upcomingOpacity,
                    line: to.upcomingLine,
                    isCenterHero: false,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),
              ],
            );
          } else {
            // Backward Roll (seeking backward)
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. New top emerges from top fade
                if (to.prevLine != null)
                  _buildLineItem(
                    centerY: -18.0 + dy,
                    scale: 0.72,
                    opacity: t * previousOpacity,
                    line: to.prevLine,
                    isCenterHero: false,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),

                // 2. Old top rolls down into center slot
                _buildLineItem(
                  centerY: 18.0 + dy,
                  scale: 0.72 + (0.28 * t),
                  opacity: previousOpacity + ((1 - previousOpacity) * t),
                  line: to.activeLine ?? from.prevLine,
                  isCenterHero: to.phase == _ReelPhase.singing,
                  showDots: to.phase != _ReelPhase.singing,
                  targetMs: to.targetMs,
                  currentMs: currentMs,
                  isDark: isDark,
                ),

                // 3. Old center rolls down into bottom slot
                _buildLineItem(
                  centerY: 54.0 + dy,
                  scale: 1.0 - (0.28 * t),
                  opacity: 1.0 - ((1 - upcomingOpacity) * t),
                  line: from.activeLine,
                  isCenterHero: false,
                  showDots: from.phase != _ReelPhase.singing,
                  targetMs: from.targetMs,
                  currentMs: currentMs,
                  isDark: isDark,
                ),

                // 4. Old bottom exits downward
                if (from.upcomingLine != null)
                  _buildLineItem(
                    centerY: 90.0 + dy,
                    scale: 0.72,
                    opacity: (1.0 - t) * upcomingOpacity,
                    line: from.upcomingLine,
                    isCenterHero: false,
                    showDots: false,
                    targetMs: 0,
                    currentMs: currentMs,
                    isDark: isDark,
                  ),
              ],
            );
          }
        },
      ),
    );
  }
}
