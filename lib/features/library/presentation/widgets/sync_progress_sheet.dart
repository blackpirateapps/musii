import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/sync_progress.dart';

void showSyncProgressSheet(BuildContext context) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => const SyncProgressSheet(),
  );
}

class SyncProgressSheet extends ConsumerWidget {
  const SyncProgressSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncProgress =
        ref.watch(syncProgressProvider).value ?? const SyncProgress();
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final isBusy = syncProgress.isBusy;
    final isStopping = syncProgress.isStopping;
    final isStopped = syncProgress.isStopped;
    final isComplete = syncProgress.isComplete;
    final isFailed = syncProgress.isFailed;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        borderRadius: AppRadii.sheetRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: AppSpacing.md),
            Text(
              isStopped
                  ? 'Sync Stopped'
                  : isComplete
                  ? 'Library Synced'
                  : isFailed
                  ? 'Sync Interrupted'
                  : 'Library Synchronization',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isStopped
                  ? '${syncProgress.filesProcessed} of ${syncProgress.filesDiscovered} completed'
                  : syncProgress.phase.displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.secondaryLabel,
              ),
            ),
            if (syncProgress.currentFile != null && isBusy && !isStopping) ...[
              const SizedBox(height: 4),
              Text(
                syncProgress.currentFile!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.systemPink,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: isComplete ? 1.0 : syncProgress.progressPercent,
                  backgroundColor: isDark
                      ? CupertinoColors.white.withOpacity(0.1)
                      : CupertinoColors.black.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isStopped
                        ? CupertinoColors.systemOrange
                        : isFailed
                        ? CupertinoColors.destructiveRed
                        : CupertinoColors.systemPink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            CupertinoListSection.insetGrouped(
              margin: EdgeInsets.zero,
              children: [
                CupertinoListTile(
                  title: const Text('Files Discovered'),
                  trailing: Text('${syncProgress.filesDiscovered}'),
                ),
                CupertinoListTile(
                  title: const Text('Files Processed'),
                  trailing: Text('${syncProgress.filesProcessed}'),
                ),
                CupertinoListTile(
                  title: const Text('New Tracks Added'),
                  trailing: Text('${syncProgress.filesAdded}'),
                ),
                CupertinoListTile(
                  title: const Text('Tracks Updated'),
                  trailing: Text('${syncProgress.filesUpdated}'),
                ),
                CupertinoListTile(
                  title: const Text('Removed from Remote'),
                  trailing: Text('${syncProgress.filesRemoved}'),
                ),
                if (syncProgress.errorsCount > 0)
                  CupertinoListTile(
                    title: const Text('Errors Encountered'),
                    trailing: Text(
                      '${syncProgress.errorsCount}',
                      style: const TextStyle(
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                  ),
              ],
            ),
            if (syncProgress.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                syncProgress.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.destructiveRed,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            // Control Actions
            if (isStopping) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CupertinoActivityIndicator(radius: 12),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss to Background'),
              ),
            ] else if (isStopped || (isFailed && syncProgress.isResumable)) ...[
              CupertinoButton.filled(
                borderRadius: BorderRadius.circular(AppRadii.card),
                onPressed: () {
                  ref.read(musicLibraryRepositoryProvider).resumeSync();
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.play_arrow_solid, size: 18),
                    SizedBox(width: 8),
                    Text('Resume Sync'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss'),
              ),
            ] else if (isBusy) ...[
              CupertinoButton(
                color: CupertinoColors.destructiveRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadii.card),
                onPressed: () {
                  ref.read(musicLibraryRepositoryProvider).stopSync();
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.stop_fill,
                      color: CupertinoColors.destructiveRed,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Stop Sync',
                      style: TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss to Background'),
              ),
            ] else ...[
              if (syncProgress.rootFolderId != null ||
                  syncProgress.phase == SyncPhase.complete) ...[
                CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  onPressed: () {
                    ref
                        .read(musicLibraryRepositoryProvider)
                        .syncFromSavedFolder();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.arrow_2_circlepath, size: 18),
                      SizedBox(width: 8),
                      Text('Sync Now'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
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
    final clamped = value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(color: backgroundColor),
            Container(
              width: constraints.maxWidth * clamped,
              color: valueColor.value,
            ),
          ],
        );
      },
    );
  }
}
