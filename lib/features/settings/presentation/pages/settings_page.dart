import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showLicensePage;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/notification_permission_service.dart';
import '../../../google_drive/presentation/pages/drive_connect_page.dart';
import '../../../google_drive/presentation/pages/drive_folder_picker_page.dart';
import '../../../library/domain/entities/sync_progress.dart';
import '../../../library/presentation/widgets/sync_progress_sheet.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _gapless = true;
  int _cacheLimitBytes = AppAudioConstants.defaultCacheSizeBytes;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final gapless = await settings.getGaplessPlayback();
    final limit = await settings.getCacheLimitBytes();
    final notifs =
        await NotificationPermissionService.isNotificationPermissionGranted();
    if (mounted) {
      setState(() {
        _gapless = gapless;
        _cacheLimitBytes = limit;
        _notificationsEnabled = notifs;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showClearCacheConfirm() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear Audio Cache?'),
        content: const Text(
          'This will remove temporarily cached songs. Pinned offline tracks will be preserved.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Clear Cache'),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(cacheRepositoryProvider)
                  .clearCache(includePinned: false);
            },
          ),
        ],
      ),
    );
  }

  void _showDisconnectConfirm() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Disconnect Google Drive?'),
        content: const Text(
          'You will be signed out from Google Drive. Your local offline downloads and indexed library will remain intact.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Disconnect'),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
    );
  }

  void _triggerSync(BuildContext context, WidgetRef ref, {
    bool forceSync = false,
  }) {
    final syncProgress =
        ref.read(syncProgressProvider).value ?? const SyncProgress();

    if (syncProgress.isBusy) {
      // Sync already running — just show the progress sheet
      showSyncProgressSheet(context);
      return;
    }

    // Show progress sheet immediately
    showSyncProgressSheet(context);

    // Trigger sync using the saved folder
    ref.read(musicLibraryRepositoryProvider).syncFromSavedFolder(
      forceSync: forceSync,
    );
  }

  void _triggerForceSync(BuildContext context, WidgetRef ref) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Force Full Re-sync?'),
        content: const Text(
          'This will re-process all audio files from Google Drive, '
          'including ones that haven\'t changed. This may take a while.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Force Re-sync'),
            onPressed: () {
              Navigator.pop(ctx);
              _triggerSync(context, ref, forceSync: true);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final cacheSizeAsync = ref.watch(cacheSizeProvider);
    final cacheSize = cacheSizeAsync.value ?? 0;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Settings'),
            border: null,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              // 1. Google Drive Account Section
              CupertinoListSection.insetGrouped(
                header: const Text('GOOGLE DRIVE'),
                children: [
                  if (user != null) ...[
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.person_crop_circle_fill,
                        color: CupertinoColors.systemPink,
                        size: 28,
                      ),
                      title: Text(user.displayName ?? user.email),
                      subtitle: Text(user.email),
                      trailing: const Text(
                        'Connected',
                        style: TextStyle(
                          color: CupertinoColors.activeGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    CupertinoListTile(
                      leading: const Icon(CupertinoIcons.folder, size: 24),
                      title: const Text('Change Music Folder'),
                      trailing: const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 18,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const DriveFolderPickerPage(),
                          ),
                        );
                      },
                    ),
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.arrow_2_circlepath,
                        size: 24,
                      ),
                      title: const Text('Sync Library Now'),
                      subtitle: const Text(
                        'Scan for new and changed tracks',
                      ),
                      onTap: () => _triggerSync(context, ref),
                    ),
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.arrow_counterclockwise,
                        size: 24,
                      ),
                      title: const Text('Force Full Re-sync'),
                      subtitle: const Text(
                        'Re-process all files from scratch',
                      ),
                      onTap: () => _triggerForceSync(context, ref),
                    ),
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.square_arrow_left,
                        color: CupertinoColors.destructiveRed,
                        size: 24,
                      ),
                      title: const Text(
                        'Disconnect Drive',
                        style: TextStyle(color: CupertinoColors.destructiveRed),
                      ),
                      onTap: _showDisconnectConfirm,
                    ),
                  ] else ...[
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.cloud,
                        color: CupertinoColors.systemPink,
                        size: 26,
                      ),
                      title: const Text('Connect Google Drive'),
                      subtitle: const Text(
                        'Sign in to sync your cloud music library',
                      ),
                      trailing: const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 18,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const DriveConnectPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),

              // 2. Playback Settings
              CupertinoListSection.insetGrouped(
                header: const Text('PLAYBACK'),
                children: [
                  CupertinoListTile(
                    title: const Text('Gapless Playback'),
                    trailing: CupertinoSwitch(
                      value: _gapless,
                      onChanged: (val) async {
                        setState(() => _gapless = val);
                        await ref
                            .read(settingsRepositoryProvider)
                            .setGaplessPlayback(val);
                      },
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('Playback Notifications'),
                    subtitle: const Text('Lock screen and media notification'),
                    trailing: CupertinoSwitch(
                      value: _notificationsEnabled,
                      onChanged: (val) async {
                        if (val) {
                          final granted =
                              await NotificationPermissionService.requestNotificationPermissionIfNeeded();
                          if (!granted && mounted) {
                            await NotificationPermissionService.openSettings();
                          }
                        } else {
                          await NotificationPermissionService.openSettings();
                        }
                        final finalStatus =
                            await NotificationPermissionService.isNotificationPermissionGranted();
                        if (mounted) {
                          setState(() => _notificationsEnabled = finalStatus);
                        }
                      },
                    ),
                  ),
                ],
              ),

              // 3. Storage & Cache
              CupertinoListSection.insetGrouped(
                header: const Text('STORAGE & CACHE'),
                children: [
                  CupertinoListTile(
                    title: const Text('Current Cache Usage'),
                    trailing: Text(
                      _formatBytes(cacheSize),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('Automatic Cache Limit'),
                    trailing: Text(
                      _formatBytes(_cacheLimitBytes),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text(
                      'Clear Cached Audio',
                      style: TextStyle(color: CupertinoColors.destructiveRed),
                    ),
                    onTap: _showClearCacheConfirm,
                  ),
                ],
              ),

              // 4. Appearance
              CupertinoListSection.insetGrouped(
                header: const Text('APPEARANCE'),
                children: const [
                  CupertinoListTile(
                    title: Text('Theme'),
                    trailing: Text(
                      'Follow System',
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  ),
                ],
              ),

              // 5. About
              CupertinoListSection.insetGrouped(
                header: const Text('ABOUT'),
                children: [
                  const CupertinoListTile(
                    title: Text('Musii'),
                    subtitle: Text(
                      'Cupertino Personal Music Player for Android',
                    ),
                    trailing: Text(
                      'v1.0.0 (1)',
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('Open Source Licenses'),
                    trailing: const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 18,
                    ),
                    onTap: () {
                      showLicensePage(context: context);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 120),
            ]),
          ),
        ],
      ),
    );
  }
}
