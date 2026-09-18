import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../playback/presentation/pages/now_playing_page.dart';
import '../../domain/entities/music_entities.dart';
import 'album_artwork.dart';
import 'audio_info_sheet.dart';
import 'technical_badge.dart';
import 'track_overflow_sheet.dart';

class ContinueListeningCard extends ConsumerWidget {
  final Track track;

  const ContinueListeningCard({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    // Only rebuild when play/pause/buffer state changes — NOT on every position tick
    final isCurrent = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack?.id == track.id),
    );
    final isPlaying = ref.watch(
      playerStateProvider.select((s) =>
        s.value?.currentTrack?.id == track.id && (s.value?.isPlaying ?? false)),
    );
    final isBuffering = ref.watch(
      playerStateProvider.select((s) =>
        s.value?.currentTrack?.id == track.id && (s.value?.isBuffering ?? false)),
    );

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x38353846) : const Color(0xEEF2F2F7),
        borderRadius: BorderRadius.circular(22.0),
        border: Border.all(
          color: isDark ? const Color(0x26FFFFFF) : const Color(0x1A000000),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isDark ? 0.25 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22.0),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: () {
            // If track is not currently active, start playing it
            if (!isCurrent) {
              ref.read(playbackRepositoryProvider).playTrack(track);
            }
            // Open Now Playing fullscreen dialog
            Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute(
                fullscreenDialog: true,
                builder: (_) => const NowPlayingPage(),
              ),
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              showTrackActionSheet(
                context: context,
                track: track,
                ref: ref,
                trackContext: TrackActionContext.library,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top info row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Album Artwork
                      Hero(
                        tag: 'current_artwork_${track.id}',
                        child: AlbumArtwork(
                          artworkPath: track.artworkPath,
                          title: track.title,
                          artist: track.artistName,
                          size: 102,
                          borderRadius: 16,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Track Metadata Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: isDark
                                    ? CupertinoColors.white
                                    : CupertinoColors.black,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track.artistName ?? 'Unknown Artist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? CupertinoColors.white.withOpacity(0.78)
                                    : CupertinoColors.secondaryLabel,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.albumName ?? 'Unknown Album',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? CupertinoColors.white.withOpacity(0.55)
                                    : CupertinoColors.tertiaryLabel,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TechnicalBadge(
                              track: track,
                              isDarkBackground: isDark,
                              onTap: () => showAudioInfoSheet(context, track),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Circular Play / Pause Action Button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 0,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          if (isCurrent) {
                            if (isPlaying) {
                              ref.read(playbackRepositoryProvider).pause();
                            } else {
                              ref.read(playbackRepositoryProvider).resume();
                            }
                          } else {
                            ref
                                .read(playbackRepositoryProvider)
                                .playTrack(track);
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.20)
                                : CupertinoColors.black.withOpacity(0.08),
                          ),
                          child: Center(
                            child: isBuffering
                                ? CupertinoActivityIndicator(
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  )
                                : Icon(
                                    isPlaying
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                    size: 24,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Bottom Scrubber Bar & Times — isolated to avoid rebuilding the card
                  _ContinueListeningScrubber(
                    track: track,
                    isCurrent: isCurrent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Isolated scrubber that watches the high-frequency position stream.
/// Only this sub-widget rebuilds on position ticks.
class _ContinueListeningScrubber extends ConsumerWidget {
  final Track track;
  final bool isCurrent;

  const _ContinueListeningScrubber({
    required this.track,
    required this.isCurrent,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final rawPosition = ref.watch(playbackPositionProvider);
    final streamDuration = ref.watch(
      playerStateProvider.select((s) => s.value?.duration ?? Duration.zero),
    );

    final duration = isCurrent && streamDuration.inMilliseconds > 0
        ? streamDuration
        : Duration(milliseconds: track.durationMs);
    final position = isCurrent ? rawPosition : Duration.zero;

    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : (track.durationMs > 0 ? track.durationMs : 1);
    final curMs = position.inMilliseconds.clamp(0, maxMs);

    final remainingMs = (maxMs - curMs).clamp(0, 86400000);
    final remainingDuration = Duration(milliseconds: remainingMs);

    final progress = (curMs / maxMs).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Custom Thin Progress Bar with Thumb Dot
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final thumbPos = (barWidth * progress).clamp(
              0.0,
              barWidth,
            );

            return SizedBox(
              height: 8,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Background track
                  Container(
                    height: 3,
                    width: barWidth,
                    decoration: BoxDecoration(
                      color: isDark
                          ? CupertinoColors.white.withOpacity(0.20)
                          : CupertinoColors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  // Active track
                  Container(
                    height: 3,
                    width: thumbPos,
                    decoration: BoxDecoration(
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  // Thumb dot
                  Positioned(
                    left: (thumbPos - 3.5).clamp(
                      0.0,
                      barWidth - 7.0,
                    ),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withOpacity(0.3),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? CupertinoColors.white.withOpacity(0.60)
                    : CupertinoColors.secondaryLabel,
              ),
            ),
            Text(
              '-${_formatDuration(remainingDuration)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? CupertinoColors.white.withOpacity(0.60)
                    : CupertinoColors.secondaryLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
