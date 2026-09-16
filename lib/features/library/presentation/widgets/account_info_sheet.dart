import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../google_drive/presentation/pages/drive_connect_page.dart';
import '../../../google_drive/presentation/pages/drive_folder_picker_page.dart';
import '../../../library/domain/entities/sync_progress.dart';
import 'sync_progress_sheet.dart';

Future<void> showAccountInfoSheet(
  BuildContext context,
  AuthUser? user,
  WidgetRef ref,
) async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => AccountInfoSheet(user: user),
  );
}

class AccountInfoSheet extends ConsumerWidget {
  final AuthUser? user;

  const AccountInfoSheet({super.key, this.user});

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Never';
    final local = dt.toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[local.month - 1];
    final d = local.day;
    final y = local.year;
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final min = local.minute.toString().padLeft(2, '0');
    return '$m $d, $y · $hour:$min $period';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final allTracks = ref.watch(allTracksProvider(null)).value ?? [];
    final allAlbums = ref.watch(allAlbumsProvider).value ?? [];
    final allArtists = ref.watch(allArtistsProvider).value ?? [];
    final syncProgress =
        ref.watch(syncProgressProvider).value ?? const SyncProgress();

    return Container(
      padding: EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grabber
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.3)
                      : CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Profile Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : CupertinoColors.systemGrey5,
                      border: Border.all(
                        color: CupertinoColors.systemPink.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child:
                          (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                          ? Image.network(
                              user!.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Center(
                                child: Text(
                                  (user?.displayName?.isNotEmpty == true)
                                      ? user!.displayName![0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: CupertinoColors.systemPink,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                user != null
                                    ? CupertinoIcons.person_fill
                                    : CupertinoIcons.cloud,
                                size: 28,
                                color: CupertinoColors.systemPink,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ??
                              (user != null
                                  ? 'Google User'
                                  : 'Google Drive Disconnected'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? 'Connect Drive to sync your music',
                          style: TextStyle(
                            fontSize: 14,
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

            const SizedBox(height: AppSpacing.lg),

            // Library Statistics Section
            CupertinoListSection.insetGrouped(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              header: const Text('MUSIC LIBRARY'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.music_note, size: 22),
                  title: const Text('Total Songs'),
                  trailing: Text(
                    '${allTracks.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.music_albums, size: 22),
                  title: const Text('Total Albums'),
                  trailing: Text(
                    '${allAlbums.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.person_2, size: 22),
                  title: const Text('Total Artists'),
                  trailing: Text(
                    '${allArtists.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
              ],
            ),

            // Google Drive Connection & Synchronization
            CupertinoListSection.insetGrouped(
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              header: const Text('GOOGLE DRIVE STATUS'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.cloud, size: 22),
                  title: const Text('Connection State'),
                  trailing: Text(
                    user != null ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: user != null
                          ? CupertinoColors.activeGreen
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ),
                if (syncProgress.rootFolderName != null &&
                    syncProgress.rootFolderName!.isNotEmpty)
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.folder, size: 22),
                    title: const Text('Music Folder'),
                    trailing: Text(
                      syncProgress.rootFolderName!,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.time, size: 22),
                  title: const Text('Last Synchronization'),
                  subtitle: Text(
                    _formatDate(syncProgress.lastCheckpointAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  if (user != null) ...[
                    CupertinoButton.filled(
                      onPressed: () {
                        Navigator.pop(context);
                        showSyncProgressSheet(context);
                        ref
                            .read(musicLibraryRepositoryProvider)
                            .syncFromSavedFolder();
                      },
                      child: const Text('Sync Library Now'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    CupertinoButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const DriveFolderPickerPage(),
                          ),
                        );
                      },
                      child: const Text('Change Music Folder'),
                    ),
                  ] else ...[
                    CupertinoButton.filled(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const DriveConnectPage(),
                          ),
                        );
                      },
                      child: const Text('Connect Google Drive'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
