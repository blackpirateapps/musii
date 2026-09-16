import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, ReorderableListView;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../../library/presentation/widgets/track_overflow_sheet.dart';
import '../../domain/entities/playback_state.dart';

void showQueueSheet(BuildContext context) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => const QueuePage(),
  );
}

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  void _showQueueActions(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Queue Options'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();
              ref.read(playbackRepositoryProvider).clearUpNext();
            },
            child: const Text('Clear Up Next'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).toggleShuffle();
            },
            child: const Text('Shuffle Queue'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerSnapshot =
        ref.watch(playerStateProvider).value ?? const PlayerStateSnapshot();
    final currentIndex = playerSnapshot.queueIndex;
    final currentTrack = playerSnapshot.currentTrack;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final List<QueueItem> upNextList =
        playerSnapshot.effectiveQueueItems.length > currentIndex + 1
        ? playerSnapshot.effectiveQueueItems.sublist(currentIndex + 1)
        : <QueueItem>[];

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            // Cupertino Sheet Grabber Pill
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
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Playing Next',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${upNextList.length} ${upNextList.length == 1 ? 'song' : 'songs'} up next',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (upNextList.isNotEmpty)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 4,
                          ),
                          minSize: 0,
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            ref.read(playbackRepositoryProvider).clearUpNext();
                          },
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: CupertinoColors.systemPink,
                            ),
                          ),
                        ),
                      CupertinoButton(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        minSize: 0,
                        onPressed: () => _showQueueActions(context, ref),
                        child: Icon(
                          CupertinoIcons.ellipsis_circle,
                          size: 24,
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // NOW PLAYING Header
            if (currentTrack != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 4.0,
                ),
                child: Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
              // Now Playing Track Card
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  showTrackActionSheet(
                    context: context,
                    track: currentTrack,
                    ref: ref,
                    trackContext: TrackActionContext.nowPlaying,
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 4.0,
                  ),
                  padding: const EdgeInsets.all(AppSpacing.xs + 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? CupertinoColors.white.withOpacity(0.08)
                        : CupertinoColors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Row(
                    children: [
                      AlbumArtwork(
                        artworkPath: currentTrack.artworkPath,
                        title: currentTrack.title,
                        artist: currentTrack.artistName,
                        size: 46,
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
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: CupertinoColors.systemPink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${currentTrack.artistName ?? 'Unknown Artist'} · ${currentTrack.albumName ?? 'Unknown Album'}',
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
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(
                          CupertinoIcons.speaker_2_fill,
                          size: 18,
                          color: CupertinoColors.systemPink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.sm),

            // UP NEXT Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 4.0,
              ),
              child: Text(
                'UP NEXT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.secondaryLabel,
                ),
              ),
            ),

            // Up Next Reorderable List
            Expanded(
              child: upNextList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.music_note_list,
                            size: 42,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.systemGrey3,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Queue is empty',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tracks you add will appear here.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? CupertinoColors.systemGrey
                                  : CupertinoColors.secondaryLabel,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      proxyDecorator:
                          (
                            Widget child,
                            int index,
                            Animation<double> animation,
                          ) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) {
                                final double animValue = Curves.easeInOut
                                    .transform(animation.value);
                                final double elevation =
                                    lerpDouble(0, 8, animValue) ?? 0;
                                final double scale =
                                    lerpDouble(1.0, 1.02, animValue) ?? 1.0;
                                return Transform.scale(
                                  scale: scale,
                                  child: Material(
                                    elevation: elevation,
                                    color: isDark
                                        ? const Color(0xFF2C2C2E)
                                        : CupertinoColors.systemBackground,
                                    shadowColor: CupertinoColors.black
                                        .withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.card,
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                              child: child,
                            );
                          },
                      itemCount: upNextList.length,
                      onReorder: (oldIndex, newIndex) {
                        HapticFeedback.lightImpact();
                        final absoluteOld = currentIndex + 1 + oldIndex;
                        final absoluteNew = currentIndex + 1 + newIndex;
                        ref
                            .read(playbackRepositoryProvider)
                            .reorderQueue(absoluteOld, absoluteNew);
                      },
                      itemBuilder: (context, index) {
                        final queueItem = upNextList[index];
                        final track = queueItem.track;
                        final absoluteIndex = currentIndex + 1 + index;

                        return Dismissible(
                          key: ValueKey('dismiss_${queueItem.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(
                              right: AppSpacing.md,
                            ),
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: CupertinoColors.destructiveRed,
                              borderRadius: BorderRadius.circular(
                                AppRadii.card,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  CupertinoIcons.trash_fill,
                                  color: CupertinoColors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Remove',
                                  style: TextStyle(
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onDismissed: (_) {
                            HapticFeedback.mediumImpact();
                            ref
                                .read(playbackRepositoryProvider)
                                .removeQueueItem(queueItem.id);
                          },
                          child: GestureDetector(
                            key: ValueKey('queue_item_${queueItem.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              ref
                                  .read(playbackRepositoryProvider)
                                  .skipToQueueItemById(queueItem.id);
                            },
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              showTrackActionSheet(
                                context: context,
                                track: track,
                                ref: ref,
                                trackContext: TrackActionContext.queue,
                                queueItemId: queueItem.id,
                                queueIndex: absoluteIndex,
                              );
                            },
                            child: Container(
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
                                    size: 42,
                                    borderRadius: AppRadii.small,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: -0.2,
                                            color: isDark
                                                ? CupertinoColors.white
                                                : CupertinoColors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${track.artistName ?? 'Unknown Artist'} · ${track.albumName ?? 'Unknown Album'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDark
                                                ? CupertinoColors.systemGrey
                                                : CupertinoColors
                                                      .secondaryLabel,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    minSize: 0,
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      showTrackActionSheet(
                                        context: context,
                                        track: track,
                                        ref: ref,
                                        trackContext: TrackActionContext.queue,
                                        queueItemId: queueItem.id,
                                        queueIndex: absoluteIndex,
                                      );
                                    },
                                    child: Icon(
                                      CupertinoIcons.ellipsis,
                                      size: 18,
                                      color: isDark
                                          ? CupertinoColors.systemGrey2
                                          : CupertinoColors.systemGrey,
                                    ),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Container(
                                      padding: const EdgeInsets.only(
                                        left: 8,
                                        right: 2,
                                        top: 8,
                                        bottom: 8,
                                      ),
                                      child: Icon(
                                        CupertinoIcons.line_horizontal_3,
                                        color: isDark
                                            ? CupertinoColors.systemGrey2
                                            : CupertinoColors.systemGrey3,
                                        size: 20,
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
          ],
        ),
      ),
    );
  }
}
