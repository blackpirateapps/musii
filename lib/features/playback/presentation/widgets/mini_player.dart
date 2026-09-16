import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../domain/entities/playback_state.dart';
import '../pages/now_playing_page.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerSnapshot =
        ref.watch(playerStateProvider).value ?? const PlayerStateSnapshot();
    final track = playerSnapshot.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final progress = (playerSnapshot.duration.inMilliseconds > 0)
        ? (playerSnapshot.position.inMilliseconds /
                  playerSnapshot.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xE8262832) : const Color(0xF2F0F0F5),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark ? const Color(0x24FFFFFF) : const Color(0x18000000),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isDark ? 0.35 : 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const NowPlayingPage(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 12.0, 8.0),
                child: Row(
                  children: [
                    Hero(
                      tag: 'current_artwork_${track.id}',
                      child: AlbumArtwork(
                        artworkPath: track.artworkPath,
                        title: track.title,
                        artist: track.artistName,
                        size: 44,
                        borderRadius: 10,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artistName ?? 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              color: isDark
                                  ? CupertinoColors.white.withOpacity(0.65)
                                  : CupertinoColors.secondaryLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Play/Pause Button
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      minSize: 0,
                      onPressed: () {
                        if (playerSnapshot.isPlaying) {
                          ref.read(playbackRepositoryProvider).pause();
                        } else {
                          ref.read(playbackRepositoryProvider).resume();
                        }
                      },
                      child: playerSnapshot.isBuffering
                          ? CupertinoActivityIndicator(
                              radius: 10,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            )
                          : Icon(
                              playerSnapshot.isPlaying
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.play_fill,
                              size: 24,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                    ),
                    const SizedBox(width: 4),
                    // Next Track Button
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 0,
                      onPressed: () {
                        ref.read(playbackRepositoryProvider).skipToNext();
                      },
                      child: Icon(
                        CupertinoIcons.forward_fill,
                        size: 22,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Thin Bottom Progress Bar Indicator
            SizedBox(
              height: 2.0,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: CupertinoColors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  CupertinoColors.systemPink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LinearProgressIndicator extends StatelessWidget {
  final double value;
  final Color backgroundColor;
  final Animation<Color> valueColor;

  const LinearProgressIndicator({
    super.key,
    required this.value,
    required this.backgroundColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(color: backgroundColor),
            Container(
              width: constraints.maxWidth * value,
              color: valueColor.value,
            ),
          ],
        );
      },
    );
  }
}
