import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../../library/presentation/widgets/audio_info_sheet.dart';
import '../../../library/presentation/widgets/technical_badge.dart';
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
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final screenWidth = MediaQuery.of(context).size.width;
    final artworkSize = screenWidth * 0.78;

    final duration = playerSnapshot.duration;
    final position = playerSnapshot.position;

    final double maxSec = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final double curSec = _isScrubbing
        ? _scrubValue
        : position.inMilliseconds.toDouble().clamp(0.0, maxSec);

    final isFavAsync = track != null
        ? ref.watch(isTrackFavoriteProvider(track.id))
        : const AsyncValue.data(false);
    final isFav = isFavAsync.value ?? false;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.transparent,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            CupertinoIcons.chevron_down,
            size: 26,
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
        middle: Text(
          'Now Playing',
          style: TextStyle(
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: Stack(
        children: [
          // 1. Blurred Backdrop
          if (track?.artworkPath != null &&
              File(track!.artworkPath!).existsSync())
            Positioned.fill(
              child: Image.file(File(track.artworkPath!), fit: BoxFit.cover),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
              child: Container(
                color: isDark
                    ? CupertinoColors.black.withOpacity(0.65)
                    : CupertinoColors.white.withOpacity(0.75),
              ),
            ),
          ),

          // 2. Main Content with Gesture Recognition
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
              child: Column(
                children: [
                  const Spacer(flex: 1),

                  // Artwork with Swipe Left/Right Gestures
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
                          borderRadius: BorderRadius.circular(
                            AppRadii.artwork + 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CupertinoColors.black.withOpacity(
                                isDark ? 0.45 : 0.20,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: AlbumArtwork(
                          artworkPath: track?.artworkPath,
                          title: track?.title,
                          artist: track?.artistName,
                          size: artworkSize,
                          borderRadius: AppRadii.artwork + 4,
                        ),
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Track Metadata
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Column(
                      children: [
                        Text(
                          track?.title ?? 'No Track Playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${track?.artistName ?? 'Unknown Artist'} — ${track?.albumName ?? 'Unknown Album'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                        if (track != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TechnicalBadge(
                            track: track,
                            onTap: () => showAudioInfoSheet(context, track),
                          ),
                        ],
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
                          activeColor: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                          thumbColor: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
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
                                  color: isDark
                                      ? CupertinoColors.systemGrey
                                      : CupertinoColors.secondaryLabel,
                                ),
                              ),
                              Text(
                                '-${_formatDuration(Duration(milliseconds: (maxSec - curSec).toInt()))}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? CupertinoColors.systemGrey
                                      : CupertinoColors.secondaryLabel,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Primary Playback Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Previous
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => ref
                              .read(playbackRepositoryProvider)
                              .skipToPrevious(),
                          child: Icon(
                            CupertinoIcons.backward_fill,
                            size: 38,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),

                        // Play/Pause (Central Circular Button)
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
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                            child: Center(
                              child: playerSnapshot.isBuffering
                                  ? CupertinoActivityIndicator(
                                      color: isDark
                                          ? CupertinoColors.black
                                          : CupertinoColors.white,
                                    )
                                  : Icon(
                                      playerSnapshot.isPlaying
                                          ? CupertinoIcons.pause_fill
                                          : CupertinoIcons.play_fill,
                                      size: 32,
                                      color: isDark
                                          ? CupertinoColors.black
                                          : CupertinoColors.white,
                                    ),
                            ),
                          ),
                        ),

                        // Next
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              ref.read(playbackRepositoryProvider).skipToNext(),
                          child: Icon(
                            CupertinoIcons.forward_fill,
                            size: 38,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Secondary Controls (Shuffle, Favorite, Repeat, Queue)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                : (isDark
                                      ? CupertinoColors.systemGrey
                                      : CupertinoColors.secondaryLabel),
                          ),
                        ),

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
                          child: Icon(
                            isFav
                                ? CupertinoIcons.heart_fill
                                : CupertinoIcons.heart,
                            size: 24,
                            color: isFav
                                ? CupertinoColors.systemPink
                                : (isDark
                                      ? CupertinoColors.systemGrey
                                      : CupertinoColors.secondaryLabel),
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
                            color:
                                playerSnapshot.repeatMode != AudioRepeatMode.off
                                ? CupertinoColors.systemPink
                                : (isDark
                                      ? CupertinoColors.systemGrey
                                      : CupertinoColors.secondaryLabel),
                          ),
                        ),

                        // Queue
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => showQueueSheet(context),
                          child: Icon(
                            CupertinoIcons.list_bullet,
                            size: 24,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
