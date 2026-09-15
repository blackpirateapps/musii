import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/widgets/empty_state.dart';
import '../../../library/presentation/widgets/sync_progress_sheet.dart';
import '../../domain/entities/drive_item.dart';

class DriveFolderPickerPage extends ConsumerStatefulWidget {
  final String? initialParentId;
  final String currentPath;

  const DriveFolderPickerPage({
    super.key,
    this.initialParentId,
    this.currentPath = 'My Drive',
  });

  @override
  ConsumerState<DriveFolderPickerPage> createState() =>
      _DriveFolderPickerPageState();
}

class _DriveFolderPickerPageState extends ConsumerState<DriveFolderPickerPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<DriveFolderItem> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final driveRepo = ref.read(googleDriveRepositoryProvider);
    final result = await driveRepo.listFolders(
      parentFolderId: widget.initialParentId,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _folders = result.dataOrNull ?? [];
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage =
            result.failureOrNull?.message ?? 'Failed to list folders';
        _isLoading = false;
      });
    }
  }

  void _selectFolder(String folderId, String folderName) async {
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Select "$folderName"?'),
        content: const Text(
          'Musii will recursively scan this folder for audio tracks and index your personal music library.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Confirm & Sync'),
            onPressed: () {
              Navigator.pop(ctx);
              _startSync(folderId, folderName);
            },
          ),
        ],
      ),
    );
  }

  void _startSync(String folderId, String folderName) async {
    // Show sync progress sheet
    showSyncProgressSheet(context);

    // Trigger sync in background
    final libraryRepo = ref.read(musicLibraryRepositoryProvider);
    await libraryRepo.syncLibrary(
      rootFolderId: folderId,
      rootFolderName: folderName,
    );

    if (mounted) {
      // Navigate to Home / main tabs
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.currentPath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: widget.initialParentId != null
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () =>
                    _selectFolder(widget.initialParentId!, widget.currentPath),
                child: const Text(
                  'Select Here',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemPink,
                  ),
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator(radius: 14))
            : _errorMessage != null
            ? EmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'Error reading Drive',
                subtitle: _errorMessage,
                actionLabel: 'Retry',
                onAction: _loadFolders,
              )
            : _folders.isEmpty
            ? EmptyState(
                icon: CupertinoIcons.folder,
                title: 'No subfolders found',
                subtitle:
                    'You can choose this folder as your music library root.',
                actionLabel: 'Select This Folder',
                onAction: () {
                  if (widget.initialParentId != null) {
                    _selectFolder(widget.initialParentId!, widget.currentPath);
                  }
                },
              )
            : ListView.separated(
                itemCount: _folders.length,
                separatorBuilder: (context, index) => Container(
                  margin: const EdgeInsets.only(left: 56),
                  height: 1,
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.08)
                      : CupertinoColors.black.withOpacity(0.06),
                ),
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  return CupertinoListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemPink.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        CupertinoIcons.folder_fill,
                        size: 20,
                        color: CupertinoColors.systemPink,
                      ),
                    ),
                    title: Text(
                      folder.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                    trailing: CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minSize: 0,
                      color: isDark
                          ? CupertinoColors.white.withOpacity(0.1)
                          : CupertinoColors.systemGrey6,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      onPressed: () => _selectFolder(folder.id, folder.name),
                      child: Text(
                        'Select',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                      ),
                    ),
                    onTap: () {
                      // Drill down into folder
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => DriveFolderPickerPage(
                            initialParentId: folder.id,
                            currentPath: folder.name,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
