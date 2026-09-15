import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../../library/presentation/widgets/audio_info_sheet.dart';
import '../../../library/presentation/widgets/technical_badge.dart';
import '../../../library/presentation/widgets/track_overflow_sheet.dart';
import '../../../lyrics/presentation/pages/lyrics_sheet.dart';
import '../../domain/entities/playback_state.dart';
import 'queue_page.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  bool _isScrubbing = false;
  double _scrubValue = 0.0;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final playerSnapshot =
        ref.watch(playerStateProvider).value ?? const PlayerStateSnapshot();
    final track = playerSnapshot.currentTrack;

    final mediaSize = MediaQuery.of(context).size;
    final screenWidth = mediaSize.width;
    final screenHeight = mediaSize.height;
    // Section 18: Artwork width approx 55–65% of usable screen width, adapting to height
    final artworkSize = min(screenWidth * 0.62, screenHeight * 0.32);

    final duration = playerSnapshot.duration;
    final position = playerSnapshot.position;

    final double maxSec = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final double curSec = _isScrubbing
        ? _scrubValue
        : position.inMilliseconds.toDouble().clamp(0.0, maxSec);

    final remainingMs = (maxSec - curSec).toInt().clamp(0, 86400000);
    final remainingDuration = Duration(milliseconds: remainingMs);

    final isFavAsync = track != null
        ? ref.watch(isTrackFavoriteProvider(track.id))
        : const AsyncValue.data(false);
    final isFav = isFavAsync.value ?? false;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.transparent,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.chevron_down,
            size: 24,
            color: CupertinoColors.white,
          ),
        ),
        middle: const Text(
          'Now Playing',
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => showQueueSheet(context),
          child: const Icon(
            CupertinoIcons.music_note_list,
            size: 22,
            color: CupertinoColors.white,
          ),
        ),
      ),
      child: Stack(
        children: [
          // 1. Blurred Backdrop from current artwork
          if (track?.artworkPath != null &&
              File(track!.artworkPath!).existsSync())
            Positioned.fill(
              child: Image.file(
                File(track.artworkPath!),
                fit: BoxFit.cover,
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
                      Color(0x66000000),
                      Color(0xAA000000),
                      Color(0xDD000000),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Main Content with Gestures
          SafeArea(
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                // Swipe down to dismiss
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 300) {
                  Navigator.of(context).pop();
                }
                // Swipe up to open queue
                else if (details.primaryVelocity != null &&
                    details.primaryVelocity! < -300) {
                  showQueueSheet(context);
                }
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            const Spacer(flex: 1),

                  // Floating Artwork with Left/Right Swipe Gestures
                  GestureDetector(
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity != null) {
                        if (details.primaryVelocity! < -200) {
                          // Swipe left -> Next track
                          ref.read(playbackRepositoryProvider).skipToNext();
                        } else if (details.primaryVelocity! > 200) {
                          // Swipe right -> Previous track
                          ref.read(playbackRepositoryProvider).skipToPrevious();
                        }
                      }
                    },
                    child: Hero(
                      tag: 'current_artwork_${track?.id ?? 'none'}',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: CupertinoColors.black.withOpacity(0.40),
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
                          borderRadius: 24,
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                  color: CupertinoColors.white.withOpacity(0.85),
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
                                  color: CupertinoColors.white.withOpacity(0.55),
                                ),
                              ),
                              if (track != null) ...[
                                const SizedBox(height: 8),
                                TechnicalBadge(
                                  track: track,
                                  onTap: () =>
                                      showAudioInfoSheet(context, track),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: AppSpacing.md),

                        // Visible More Button (Mandatory per Section 20)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            if (track != null) {
                              showTrackActionSheet(
                                context: context,
                                track: track,
                                ref: ref,
                              );
                            }
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CupertinoColors.systemGrey.withOpacity(
                                0.32,
                              ),
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

                  const SizedBox(height: AppSpacing.lg),

                  // Apple-Style Scrubber
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Column(
                      children: [
                        CupertinoSlider(
                          value: curSec,
                          min: 0.0,
                          max: maxSec,
                          activeColor: CupertinoColors.white,
                          thumbColor: CupertinoColors.white,
                          onChangeStart: (_) {
                            setState(() => _isScrubbing = true);
                          },
                          onChanged: (val) {
                            setState(() => _scrubValue = val);
                          },
                          onChangeEnd: (val) {
                            _isScrubbing = false;
                            ref
                                .read(playbackRepositoryProvider)
                                .seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(
                                  Duration(milliseconds: curSec.toInt()),
                                ),
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
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Primary Playback Controls Row (Shuffle, Prev, Play/Pause, Next, Repeat)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                            color: playerSnapshot.shuffleMode
                                ? CupertinoColors.systemPink
                                : CupertinoColors.white.withOpacity(0.70),
                          ),
                        ),

                        // Previous
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => ref
                              .read(playbackRepositoryProvider)
                              .skipToPrevious(),
                          child: const Icon(
                            CupertinoIcons.backward_fill,
                            size: 34,
                            color: CupertinoColors.white,
                          ),
                        ),

                        // Play/Pause (Large Circular Translucent Button)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            if (playerSnapshot.isPlaying) {
                              ref.read(playbackRepositoryProvider).pause();
                            } else {
                              ref.read(playbackRepositoryProvider).resume();
                            }
                          },
                          child: Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CupertinoColors.white.withOpacity(0.24),
                            ),
                            child: Center(
                              child: playerSnapshot.isBuffering
                                  ? const CupertinoActivityIndicator(
                                      color: CupertinoColors.white,
                                    )
                                  : Icon(
                                      playerSnapshot.isPlaying
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
                          onPressed: () =>
                              ref.read(playbackRepositoryProvider).skipToNext(),
                          child: const Icon(
                            CupertinoIcons.forward_fill,
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
                            playerSnapshot.repeatMode == AudioRepeatMode.one
                                ? CupertinoIcons.repeat_1
                                : CupertinoIcons.repeat,
                            size: 22,
                            color: playerSnapshot.repeatMode !=
                                    AudioRepeatMode.off
                                ? CupertinoColors.systemPink
                                : CupertinoColors.white.withOpacity(0.70),
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
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                              color: CupertinoColors.systemGrey.withOpacity(
                                0.28,
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
                              color: CupertinoColors.systemGrey.withOpacity(
                                0.28,
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
                              color: CupertinoColors.systemGrey.withOpacity(
                                0.28,
                              ),
                            ),
                            child: const Icon(
                              CupertinoIcons.list_bullet,
                              size: 22,
                              color: CupertinoColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Home indicator
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      width: 135,
                      height: 5,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
),
        ],
      ),
    );
  }
}
