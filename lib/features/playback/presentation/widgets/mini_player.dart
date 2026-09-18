import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../pages/now_playing_page.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only rebuild when the track, play state, or buffering changes
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack),
    );
    final isPlaying = ref.watch(
      playerStateProvider.select((s) => s.value?.isPlaying ?? false),
    );
    final isBuffering = ref.watch(
      playerStateProvider.select((s) => s.value?.isBuffering ?? false),
    );

    if (track == null) {
      return const SizedBox.shrink();
    }

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xE51C1C1E) : const Color(0xE5F2F2F7),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0x0F000000),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isDark ? 0.4 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
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
                    padding: const EdgeInsets.fromLTRB(8.0, 6.0, 12.0, 6.0),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'current_artwork_${track.id}',
                          child: AlbumArtwork(
                            artworkPath: track.artworkPath,
                            title: track.title,
                            artist: track.artistName,
                            size: 36,
                            borderRadius: 6.0,
                          ),
                        ),
                        const SizedBox(width: 10),
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                track.artistName ?? 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? CupertinoColors.white.withOpacity(0.6)
                                      : CupertinoColors.black.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Play/Pause Button
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          minSize: 0,
                          onPressed: () {
                            if (isPlaying) {
                              ref.read(playbackRepositoryProvider).pause();
                            } else {
                              ref.read(playbackRepositoryProvider).resume();
                            }
                          },
                          child: isBuffering
                              ? CupertinoActivityIndicator(
                                  radius: 8,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                )
                              : Icon(
                                  isPlaying
                                      ? CupertinoIcons.pause_fill
                                      : CupertinoIcons.play_fill,
                                  size: 20,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                ),
                        ),
                        // Next Track Button
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            ref.read(playbackRepositoryProvider).skipToNext();
                          },
                          child: Icon(
                            CupertinoIcons.forward_fill,
                            size: 20,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Hairline Progress Bar — isolated in its own Consumer
                const _MiniPlayerProgressBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Isolated progress bar that watches the high-frequency position stream.
/// Only this 1px bar rebuilds on position ticks — not the entire MiniPlayer.
class _MiniPlayerProgressBar extends ConsumerWidget {
  const _MiniPlayerProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(playbackPositionProvider);
    final dur = ref.watch(
      playerStateProvider.select((s) => s.value?.duration ?? Duration.zero),
    );
    final progress = (dur.inMilliseconds > 0)
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      height: 1.0,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: CupertinoColors.transparent,
        valueColor: const AlwaysStoppedAnimation<Color>(
          CupertinoColors.systemPink,
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
