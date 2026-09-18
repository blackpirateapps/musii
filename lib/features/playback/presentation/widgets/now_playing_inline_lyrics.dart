import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../lyrics/domain/entities/lyric_model.dart';
import '../../../lyrics/presentation/pages/lyrics_sheet.dart';
import '../../../lyrics/presentation/widgets/lyric_line_widget.dart';

/// Cinematic inline synchronized lyrics display for the Now Playing screen.
///
/// Sits between track metadata and the playback scrubber, rendering the active
/// synchronized lyric line in high contrast with word-by-word progressive
/// highlighting when word timing exists, alongside subtle previous and next lines.
///
/// Gracefully collapses when lyrics are unavailable, plain (unsynchronized),
/// or when disabled by the user in Settings.
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
  int _activeIndex = -1;
  bool _isInstrumental = false;

  @override
  void initState() {
    super.initState();
    _initActiveIndex();
  }

  void _initActiveIndex() {
    final track = widget.track;
    if (track == null) return;
    final lyrics = ref.read(trackLyricsProvider(track.id)).value;
    if (lyrics != null &&
        lyrics.isSynchronized &&
        lyrics.lines.isNotEmpty &&
        lyrics.trackId == track.id) {
      final pos = ref.read(playbackPositionProvider);
      _activeIndex = TrackLyrics.calculateActiveIndex(lyrics.lines, pos);
      _isInstrumental = _checkIsInstrumental(lyrics.lines, _activeIndex, pos);
    }
  }

  @override
  void didUpdateWidget(NowPlayingInlineLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id) {
      _activeIndex = -1;
      _isInstrumental = false;
      _initActiveIndex();
    }
  }

  /// Determines whether playback is currently in a meaningful instrumental gap.
  ///
  /// A gap is considered meaningful when there are >= 3.0 seconds between the
  /// conclusion of the active lyric line and the timestamp of the next line.
  /// During this interval, the current line smoothly fades down to let the
  /// atmospheric backdrop breathe.
  bool _checkIsInstrumental(
    List<LyricLine> lines,
    int activeIndex,
    Duration position,
  ) {
    if (activeIndex < 0 || activeIndex >= lines.length) {
      return false;
    }
    final line = lines[activeIndex];
    final curMs = position.inMilliseconds;
    final int? nextMs = (activeIndex + 1 < lines.length)
        ? lines[activeIndex + 1].timestampMs
        : null;

    final int lineEndMs;
    if (line.hasWords) {
      lineEndMs = line.words.last.endMs;
    } else {
      final rawDuration = nextMs != null ? (nextMs - line.timestampMs) : 3500;
      final lineDuration = rawDuration > 0
          ? rawDuration.clamp(1200, 4500)
          : 3500;
      lineEndMs = line.timestampMs + lineDuration;
    }

    if (nextMs != null && (nextMs - lineEndMs >= 3000)) {
      if (curMs > lineEndMs + 1000 && curMs < nextMs - 600) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final inlineLyricsEnabled = ref.watch(inlineLyricsEnabledProvider);
    final lyricsAsync = widget.track != null
        ? ref.watch(trackLyricsProvider(widget.track!.id))
        : const AsyncValue<TrackLyrics?>.data(null);
    final lyrics = lyricsAsync.value;

    final hasValidSyncedLyrics =
        widget.track != null &&
        lyrics != null &&
        lyrics.isSynchronized &&
        lyrics.lines.isNotEmpty &&
        lyrics.trackId == widget.track!.id;

    final shouldShow =
        inlineLyricsEnabled && !widget.isCompactScreen && hasValidSyncedLyrics;

    final disableAnimations = MediaQuery.of(context).disableAnimations;

    // Listen to playback position updates. Only trigger setState when the active
    // line index changes or when entering/exiting an instrumental section.
    // High-frequency word progressive repainting is strictly scoped inside
    // LyricLineWidget's internal RepaintBoundary.
    ref.listen<Duration>(playbackPositionProvider, (prev, next) {
      final currentTrack = widget.track;
      final currentLyrics = lyrics;
      if (currentTrack == null ||
          currentLyrics == null ||
          !currentLyrics.isSynchronized ||
          currentLyrics.lines.isEmpty ||
          currentLyrics.trackId != currentTrack.id) {
        return;
      }

      final newIndex = TrackLyrics.calculateActiveIndex(
        currentLyrics.lines,
        next,
      );

      final instrumental = _checkIsInstrumental(
        currentLyrics.lines,
        newIndex,
        next,
      );

      if (newIndex != _activeIndex || instrumental != _isInstrumental) {
        setState(() {
          _activeIndex = newIndex;
          _isInstrumental = instrumental;
        });
      }
    });

    // Cold-start or asynchronous lyrics arrival resolution
    if (hasValidSyncedLyrics && _activeIndex == -1) {
      final pos = ref.read(playbackPositionProvider);
      final currentActive = TrackLyrics.calculateActiveIndex(lyrics.lines, pos);
      if (currentActive != -1) {
        _activeIndex = currentActive;
        _isInstrumental = _checkIsInstrumental(lyrics.lines, _activeIndex, pos);
      }
    }

    final lines = hasValidSyncedLyrics ? lyrics.lines : const <LyricLine>[];

    final prevLine = (_activeIndex > 0 && _activeIndex < lines.length)
        ? lines[_activeIndex - 1]
        : null;
    final currentLine = (_activeIndex >= 0 && _activeIndex < lines.length)
        ? lines[_activeIndex]
        : null;
    final nextLine = (_activeIndex >= 0 && _activeIndex + 1 < lines.length)
        ? lines[_activeIndex + 1]
        : (_activeIndex == -1 && lines.isNotEmpty ? lines[0] : null);

    return AnimatedSize(
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        opacity: shouldShow ? 1.0 : 0.0,
        child: shouldShow
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 2.0,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (widget.track != null) {
                      showLyricsSheet(context, widget.track!);
                    }
                  },
                  child: SizedBox(
                    width: double.infinity,
                    height: 108.0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Previous Line (Subtle / Muted Context)
                        SizedBox(
                          height: 20,
                          width: double.infinity,
                          child: AnimatedSwitcher(
                            duration: disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            transitionBuilder: (child, animation) {
                              if (disableAnimations) return child;
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child:
                                prevLine != null &&
                                    prevLine.text.trim().isNotEmpty
                                ? Text(
                                    prevLine.text,
                                    key: ValueKey(
                                      'inline_prev_${prevLine.timestampMs}_${prevLine.sequence}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: CupertinoColors.white.withOpacity(
                                        0.24,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('empty_prev'),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Current Line (Hero Lyric with Word-Level Highlighting)
                        SizedBox(
                          height: 58,
                          width: double.infinity,
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: <Widget>[
                                    ...previousChildren,
                                    ?currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (child, animation) {
                                if (disableAnimations) return child;
                                final fade = FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.14),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: fade,
                                );
                              },
                              child: currentLine != null
                                  ? Semantics(
                                      key: ValueKey(
                                        'inline_current_${currentLine.timestampMs}_${currentLine.sequence}',
                                      ),
                                      label:
                                          'Current lyric: ${currentLine.text}',
                                      child: AnimatedOpacity(
                                        duration: disableAnimations
                                            ? Duration.zero
                                            : const Duration(milliseconds: 320),
                                        curve: Curves.easeOutCubic,
                                        opacity: _isInstrumental ? 0.0 : 1.0,
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: LyricLineWidget(
                                            line: currentLine,
                                            isActive: true,
                                            isDark: true,
                                            enableScale: false,
                                            enableSimulatedLineSweep: false,
                                            textAlign: TextAlign.center,
                                            alignment: Alignment.center,
                                            padding: EdgeInsets.zero,
                                            activeStyle: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                              height: 1.35,
                                              color: CupertinoColors.white,
                                            ),
                                            inactiveStyle: TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                              height: 1.35,
                                              color: CupertinoColors.white
                                                  .withOpacity(0.38),
                                            ),
                                            nextLineTimestampMs:
                                                (_activeIndex + 1 <
                                                    lines.length)
                                                ? lines[_activeIndex + 1]
                                                      .timestampMs
                                                : null,
                                            onTap: () {
                                              if (widget.track != null) {
                                                showLyricsSheet(
                                                  context,
                                                  widget.track!,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('empty_current'),
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Next Line (Subtle / Muted Context)
                        SizedBox(
                          height: 20,
                          width: double.infinity,
                          child: AnimatedSwitcher(
                            duration: disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            transitionBuilder: (child, animation) {
                              if (disableAnimations) return child;
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child:
                                nextLine != null &&
                                    nextLine.text.trim().isNotEmpty
                                ? Text(
                                    nextLine.text,
                                    key: ValueKey(
                                      'inline_next_${nextLine.timestampMs}_${nextLine.sequence}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: CupertinoColors.white.withOpacity(
                                        0.20,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('empty_next'),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}
