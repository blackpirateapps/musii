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

    return CupertinoButton(
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
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4.0,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252528) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thin Progress Bar
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.card),
              ),
              child: SizedBox(
                height: 2.0,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: CupertinoColors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    CupertinoColors.systemPink,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Hero(
                    tag: 'current_artwork_${track.id}',
                    child: AlbumArtwork(
                      artworkPath: track.artworkPath,
                      title: track.title,
                      artist: track.artistName,
                      size: 42,
                      borderRadius: AppRadii.small,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
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
                            fontSize: 15,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Play/Pause Button
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
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
                        ? const CupertinoActivityIndicator(radius: 10)
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
                  // Next Button
                  CupertinoButton(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
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
