import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ReorderableListView;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../domain/entities/playback_state.dart';

void showQueueSheet(BuildContext context) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => const QueuePage(),
  );
}

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerSnapshot =
        ref.watch(playerStateProvider).value ?? const PlayerStateSnapshot();
    final queue = playerSnapshot.queue;
    final currentIndex = playerSnapshot.queueIndex;
    final currentTrack = playerSnapshot.currentTrack;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final List<Track> upNextList = (currentIndex < queue.length - 1)
        ? queue.sublist(currentIndex + 1)
        : <Track>[];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        borderRadius: AppRadii.sheetRadius,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            // Sheet Handle
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Playing Next',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                  if (queue.isNotEmpty)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 0,
                      onPressed: () {
                        ref.read(playbackRepositoryProvider).clearQueue();
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.systemPink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // Now Playing Track Section
            if (currentTrack != null)
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 4.0,
                ),
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.06)
                      : CupertinoColors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Row(
                  children: [
                    AlbumArtwork(
                      artworkPath: currentTrack.artworkPath,
                      title: currentTrack.title,
                      artist: currentTrack.artistName,
                      size: 44,
                      borderRadius: AppRadii.small,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentTrack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemPink,
                            ),
                          ),
                          Text(
                            currentTrack.artistName ?? 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? CupertinoColors.systemGrey
                                  : CupertinoColors.secondaryLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(
                        CupertinoIcons.speaker_2_fill,
                        size: 16,
                        color: CupertinoColors.systemPink,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: AppSpacing.xs),

            // Up Next Reorderable List
            Expanded(
              child: upNextList.isEmpty
                  ? Center(
                      child: Text(
                        'Queue is empty',
                        style: TextStyle(
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.secondaryLabel,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: upNextList.length,
                      onReorder: (oldIndex, newIndex) {
                        final absoluteOld = currentIndex + 1 + oldIndex;
                        final absoluteNew = currentIndex + 1 + newIndex;
                        ref
                            .read(playbackRepositoryProvider)
                            .reorderQueue(absoluteOld, absoluteNew);
                      },
                      itemBuilder: (context, index) {
                        final track = upNextList[index];
                        final absoluteIndex = currentIndex + 1 + index;

                        return Container(
                          key: ValueKey('queue_${track.id}_$absoluteIndex'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs + 2,
                          ),
                          child: Row(
                            children: [
                              AlbumArtwork(
                                artworkPath: track.artworkPath,
                                title: track.title,
                                artist: track.artistName,
                                size: 40,
                                borderRadius: AppRadii.small,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? CupertinoColors.white
                                            : CupertinoColors.black,
                                      ),
                                    ),
                                    Text(
                                      track.artistName ?? 'Unknown Artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? CupertinoColors.systemGrey
                                            : CupertinoColors.secondaryLabel,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minSize: 0,
                                onPressed: () {
                                  ref
                                      .read(playbackRepositoryProvider)
                                      .removeFromQueue(absoluteIndex);
                                },
                                child: const Icon(
                                  CupertinoIcons.minus_circle,
                                  color: CupertinoColors.destructiveRed,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                CupertinoIcons.line_horizontal_3,
                                color: isDark
                                    ? CupertinoColors.systemGrey2
                                    : CupertinoColors.systemGrey3,
                                size: 20,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
