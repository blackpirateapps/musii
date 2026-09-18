import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Material,
        MaterialType,
        Slider,
        SliderTheme,
        SliderThemeData,
        RoundSliderThumbShape,
        RoundSliderOverlayShape,
        RoundedRectSliderTrackShape;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../../library/presentation/widgets/audio_info_sheet.dart';
import '../../../library/presentation/widgets/technical_badge.dart';
import '../../../library/presentation/widgets/track_overflow_sheet.dart';
import '../../../lyrics/presentation/pages/lyrics_sheet.dart';
import '../../../last_fm/presentation/providers/last_fm_providers.dart';
import '../../domain/entities/playback_state.dart';
import '../widgets/now_playing_inline_lyrics.dart';
import 'queue_page.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  AnimationController? _dismissController;
  Animation<double>? _dismissAnimation;
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _dismissController?.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dismissController?.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta == null) return;
    setState(() {
      _dragOffset = max(0.0, _dragOffset + details.primaryDelta!);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;

    // Swipe up to open queue when at top
    if (_dragOffset == 0.0 && velocity < -300) {
      showQueueSheet(context);
      return;
    }

    // Dismiss if pulled down past 120px or flicked downwards
    if (velocity > 300 || _dragOffset > 120) {
      Navigator.of(context).pop();
    } else {
      _animateBack();
    }
  }

  void _animateBack() {
    final start = _dragOffset;
    if (start == 0.0) return;
    _dismissController?.reset();
    _dismissAnimation =
        Tween<double>(begin: start, end: 0.0).animate(
          CurvedAnimation(
            parent: _dismissController!,
            curve: Curves.easeOutCubic,
          ),
        )..addListener(() {
          setState(() {
            _dragOffset = _dismissAnimation!.value;
          });
        });
    _dismissController?.forward().then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = 0.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Selective watches: only rebuild when these specific fields change
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack),
    );
    final isPlaying = ref.watch(
      playerStateProvider.select((s) => s.value?.isPlaying ?? false),
    );
    final isBuffering = ref.watch(
      playerStateProvider.select((s) => s.value?.isBuffering ?? false),
    );
    final shuffleMode = ref.watch(
      playerStateProvider.select((s) => s.value?.shuffleMode ?? false),
    );
    final repeatMode = ref.watch(
      playerStateProvider.select(
        (s) => s.value?.repeatMode ?? AudioRepeatMode.off,
      ),
    );

    final mediaSize = MediaQuery.of(context).size;
    final screenWidth = mediaSize.width;
    final screenHeight = mediaSize.height;
    // Sized responsively to usable screen width and height
    final artworkSize = min(screenWidth * 0.64, screenHeight * 0.33);
    final isCompactScreen = screenHeight < 620;

    final isFavAsync = track != null
        ? ref.watch(isTrackFavoriteProvider(track.id))
        : const AsyncValue.data(false);
    final isFav = isFavAsync.value ?? false;
    final lastScrobbledTrack = ref.watch(lastScrobbledTrackProvider).value;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Stack(
            children: [
              // 1. Blurred Backdrop from current artwork (isolated from repaints)
              RepaintBoundary(
                child: Stack(
                  children: [
                    if (track?.artworkPath != null)
                      Positioned.fill(
                        child: Image.file(
                          File(track!.artworkPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x40000000),
                                Color(0x80000000),
                                Color(0xB3000000),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Main Content
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                          maxHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            // Top Bar: Down Chevron on Left, "Now Playing" Title Centered, Queue Button on Right
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Left: Dismiss Chevron
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minSize: 44,
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Icon(
                                      CupertinoIcons.chevron_down,
                                      size: 24,
                                      color: CupertinoColors.white,
                                    ),
                                  ),

                                  // Center: "Now Playing" Title
                                  const Text(
                                    'Now Playing',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.4,
                                      color: CupertinoColors.white,
                                    ),
                                  ),

                                  // Right: Top Queue / Up Next Button
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minSize: 44,
                                    onPressed: () => showQueueSheet(context),
                                    child: const Icon(
                                      CupertinoIcons.text_badge_plus,
                                      size: 22,
                                      color: CupertinoColors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(flex: 1),

                            // Floating Artwork with Left/Right Swipe Gestures
                            GestureDetector(
                              onHorizontalDragEnd: (details) {
                                if (details.primaryVelocity != null) {
                                  if (details.primaryVelocity! < -200) {
                                    // Swipe left -> Next track
                                    ref
                                        .read(playbackRepositoryProvider)
                                        .skipToNext();
                                  } else if (details.primaryVelocity! > 200) {
                                    // Swipe right -> Previous track
                                    ref
                                        .read(playbackRepositoryProvider)
                                        .skipToPrevious();
                                  }
                                }
                              },
                              child: Hero(
                                tag: 'current_artwork_${track?.id ?? 'none'}',
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: CupertinoColors.black
                                            .withOpacity(0.40),
                                        blurRadius: 36,
                                        offset: const Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: AlbumArtwork(
                                    artworkPath: track?.artworkPath,
                                    title: track?.title,
                                    artist: track?.artistName,
                                    size: artworkSize,
                                    borderRadius: 22,
                                  ),
                                ),
                              ),
                            ),

                            const Spacer(flex: 1),

                            // Track Metadata Row: Left-aligned Text + Circular More Button on Right
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xl,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Left Text Block
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          track?.title ?? 'No Track Playing',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.4,
                                            color: CupertinoColors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          track?.artistName ?? 'Unknown Artist',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w400,
                                            color: CupertinoColors.white
                                                .withOpacity(0.85),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          track?.albumName ?? 'Unknown Album',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            color: CupertinoColors.white
                                                .withOpacity(0.55),
                                          ),
                                        ),
                                        if (track != null) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              TechnicalBadge(
                                                track: track,
                                                isDarkBackground: true,
                                                onTap: () => showAudioInfoSheet(
                                                  context,
                                                  track,
                                                ),
                                              ),
                                              if (lastScrobbledTrack?.id ==
                                                  track.id)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: CupertinoColors
                                                        .activeGreen
                                                        .withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                    border: Border.all(
                                                      color: CupertinoColors
                                                          .activeGreen
                                                          .withOpacity(0.5),
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        CupertinoIcons
                                                            .checkmark_alt,
                                                        size: 11,
                                                        color: CupertinoColors
                                                            .activeGreen,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Scrobbled',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: CupertinoColors
                                                              .activeGreen,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: AppSpacing.md),

                                  // Visible More Button (...)
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minSize: 0,
                                    onPressed: () {
                                      if (track != null) {
                                        showTrackActionSheet(
                                          context: context,
                                          track: track,
                                          ref: ref,
                                          trackContext:
                                              TrackActionContext.nowPlaying,
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: CupertinoColors.systemGrey
                                            .withOpacity(0.32),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          CupertinoIcons.ellipsis,
                                          size: 20,
                                          color: CupertinoColors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Inline Synced Lyrics (between metadata and scrubber)
                            NowPlayingInlineLyrics(
                              track: track,
                              isCompactScreen: isCompactScreen,
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Apple-Style Scrubber (isolated — only scrubber rebuilds on position ticks)
                            const _NowPlayingScrubber(),

                            const SizedBox(height: AppSpacing.md),

                            // Primary Playback Controls Row (Shuffle, Prev, Play/Pause, Next, Repeat)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xl,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Shuffle
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => ref
                                        .read(playbackRepositoryProvider)
                                        .toggleShuffle(),
                                    child: Icon(
                                      CupertinoIcons.shuffle,
                                      size: 22,
                                      color: shuffleMode
                                          ? CupertinoColors.systemPink
                                          : CupertinoColors.white.withOpacity(
                                              0.70,
                                            ),
                                    ),
                                  ),

                                  // Previous
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => ref
                                        .read(playbackRepositoryProvider)
                                        .skipToPrevious(),
                                    child: const Icon(
                                      CupertinoIcons.backward_end_fill,
                                      size: 34,
                                      color: CupertinoColors.white,
                                    ),
                                  ),

                                  // Play/Pause (Large Circular Translucent Button)
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      if (isPlaying) {
                                        ref
                                            .read(playbackRepositoryProvider)
                                            .pause();
                                      } else if (track != null) {
                                        ref
                                            .read(playbackRepositoryProvider)
                                            .resume();
                                      }
                                    },
                                    child: Container(
                                      width: 74,
                                      height: 74,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: CupertinoColors.white
                                            .withOpacity(0.24),
                                      ),
                                      child: Center(
                                        child: isBuffering
                                            ? const CupertinoActivityIndicator(
                                                color: CupertinoColors.white,
                                              )
                                            : Icon(
                                                isPlaying
                                                    ? CupertinoIcons.pause_fill
                                                    : CupertinoIcons.play_fill,
                                                size: 36,
                                                color: CupertinoColors.white,
                                              ),
                                      ),
                                    ),
                                  ),

                                  // Next
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => ref
                                        .read(playbackRepositoryProvider)
                                        .skipToNext(),
                                    child: const Icon(
                                      CupertinoIcons.forward_end_fill,
                                      size: 34,
                                      color: CupertinoColors.white,
                                    ),
                                  ),

                                  // Repeat
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => ref
                                        .read(playbackRepositoryProvider)
                                        .cycleRepeatMode(),
                                    child: Icon(
                                      repeatMode == AudioRepeatMode.one
                                          ? CupertinoIcons.repeat_1
                                          : CupertinoIcons.repeat,
                                      size: 22,
                                      color: repeatMode != AudioRepeatMode.off
                                          ? CupertinoColors.systemPink
                                          : CupertinoColors.white.withOpacity(
                                              0.70,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: AppSpacing.xl),

                            // Bottom Secondary Controls (Favorite, Lyrics, Queue)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xxl,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Favorite
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      if (track != null) {
                                        ref
                                            .read(favoriteRepositoryProvider)
                                            .toggleFavorite(track.id);
                                      }
                                    },
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: CupertinoColors.white
                                            .withOpacity(0.08),
                                        border: Border.all(
                                          color: CupertinoColors.white
                                              .withOpacity(0.25),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Icon(
                                        isFav
                                            ? CupertinoIcons.heart_fill
                                            : CupertinoIcons.heart,
                                        size: 24,
                                        color: isFav
                                            ? CupertinoColors.systemPink
                                            : CupertinoColors.white,
                                      ),
                                    ),
                                  ),

                                  // Lyrics
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      if (track != null) {
                                        showLyricsSheet(context, track);
                                      }
                                    },
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: CupertinoColors.white
                                            .withOpacity(0.08),
                                        border: Border.all(
                                          color: CupertinoColors.white
                                              .withOpacity(0.25),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.quote_bubble,
                                        size: 22,
                                        color: CupertinoColors.white,
                                      ),
                                    ),
                                  ),

                                  // Queue
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => showQueueSheet(context),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: CupertinoColors.white
                                            .withOpacity(0.08),
                                        border: Border.all(
                                          color: CupertinoColors.white
                                              .withOpacity(0.25),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.text_badge_plus,
                                        size: 22,
                                        color: CupertinoColors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(flex: 1),

                            // Home Indicator Bar
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                width: 135,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: CupertinoColors.white.withOpacity(
                                    0.35,
                                  ),
                                  borderRadius: BorderRadius.circular(2.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isolated scrubber widget that watches the high-frequency position stream.
/// Uses AnimationController to lerp smoothly between ~200ms position ticks
/// for a premium 60fps scrubber feel.
class _NowPlayingScrubber extends ConsumerStatefulWidget {
  const _NowPlayingScrubber();

  @override
  ConsumerState<_NowPlayingScrubber> createState() =>
      _NowPlayingScrubberState();
}

class _NowPlayingScrubberState extends ConsumerState<_NowPlayingScrubber>
    with SingleTickerProviderStateMixin {
  bool _isScrubbing = false;
  double _scrubValue = 0.0;

  late final AnimationController _lerpController;
  double _lerpStart = 0.0;
  double _lerpEnd = 0.0;

  @override
  void initState() {
    super.initState();
    _lerpController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          if (!_isScrubbing && mounted) {
            setState(() {});
          }
        });
  }

  @override
  void dispose() {
    _lerpController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = ref.watch(
      playerStateProvider.select((s) => s.value?.duration ?? Duration.zero),
    );
    final rawPosition = ref.watch(playbackPositionProvider);

    // Smooth 60fps interpolation between position ticks
    final posMs = rawPosition.inMilliseconds.toDouble();
    if (posMs != _lerpEnd) {
      _lerpStart = _lerpStart + (_lerpEnd - _lerpStart) * _lerpController.value;
      _lerpEnd = posMs;
      _lerpController.forward(from: 0.0);
    }

    final double maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final double interpolatedPos =
        _lerpStart + (_lerpEnd - _lerpStart) * _lerpController.value;
    final double curMs = _isScrubbing
        ? _scrubValue
        : interpolatedPos.clamp(0.0, maxMs);

    final remainingMs = (maxMs - curMs).toInt().clamp(0, 86400000);
    final remainingDuration = Duration(milliseconds: remainingMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4.0,
                activeTrackColor: CupertinoColors.white,
                inactiveTrackColor: CupertinoColors.white.withOpacity(0.3),
                thumbColor: CupertinoColors.white,
                overlayColor: CupertinoColors.white.withOpacity(0.1),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14.0,
                ),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: curMs,
                min: 0.0,
                max: maxMs,
                onChangeStart: (_) {
                  setState(() => _isScrubbing = true);
                },
                onChanged: (val) {
                  setState(() => _scrubValue = val);
                },
                onChangeEnd: (val) {
                  _isScrubbing = false;
                  _lerpStart = val;
                  _lerpEnd = val;
                  ref
                      .read(playbackRepositoryProvider)
                      .seek(Duration(milliseconds: val.toInt()));
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: curMs.toInt())),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.white.withOpacity(0.65),
                  ),
                ),
                Text(
                  '-${_formatDuration(remainingDuration)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
