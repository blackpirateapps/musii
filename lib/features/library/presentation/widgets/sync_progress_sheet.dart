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

    final isBusy =
        syncProgress.phase == SyncPhase.scanning ||
        syncProgress.phase == SyncPhase.extractingMetadata ||
        syncProgress.phase == SyncPhase.updatingDatabase;

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
              'Library Synchronization',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              syncProgress.phase.displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.secondaryLabel,
              ),
            ),
            if (syncProgress.currentFile != null && isBusy) ...[
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
            if (isBusy)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: syncProgress.progressPercent,
                    backgroundColor: isDark
                        ? CupertinoColors.white.withOpacity(0.1)
                        : CupertinoColors.black.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      CupertinoColors.systemPink,
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
            CupertinoButton.filled(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onPressed: () => Navigator.pop(context),
              child: Text(isBusy ? 'Dismiss to Background' : 'Done'),
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
