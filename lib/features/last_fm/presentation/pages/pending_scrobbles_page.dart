import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/widgets/empty_state.dart';
import '../../domain/entities/pending_scrobble.dart';
import '../providers/last_fm_providers.dart';

class PendingScrobblesPage extends ConsumerStatefulWidget {
  const PendingScrobblesPage({super.key});

  @override
  ConsumerState<PendingScrobblesPage> createState() =>
      _PendingScrobblesPageState();
}

class _PendingScrobblesPageState extends ConsumerState<PendingScrobblesPage> {
  bool _isSyncing = false;

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    try {
      await ref.read(lastFmRepositoryProvider).syncPendingScrobbles();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Widget _buildStatusBadge(ScrobbleStatus status, bool isDark) {
    final (label, color) = switch (status) {
      ScrobbleStatus.pending => ('Waiting', CupertinoColors.systemGrey),
      ScrobbleStatus.sending => ('Syncing…', CupertinoColors.activeBlue),
      ScrobbleStatus.failedRetryable => (
        'Retry scheduled',
        CupertinoColors.systemOrange,
      ),
      ScrobbleStatus.failedReauth => (
        'Requires reconnect',
        CupertinoColors.destructiveRed,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(lastFmPendingScrobblesProvider);
    final pendingList = pendingAsync.value ?? const <PendingScrobble>[];
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Offline Scrobbles'),
        trailing: pendingList.isNotEmpty
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _isSyncing ? null : _manualSync,
                child: _isSyncing
                    ? const CupertinoActivityIndicator(radius: 8)
                    : const Text('Sync Now', style: TextStyle(fontSize: 14)),
              )
            : null,
      ),
      child: SafeArea(
        child: pendingList.isEmpty
            ? const Center(
                child: EmptyState(
                  icon: CupertinoIcons.checkmark_seal_fill,
                  title: 'All Scrobbles Synced',
                  subtitle: 'There are no pending scrobbles waiting in the offline queue.',
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          '${pendingList.length} track${pendingList.length == 1 ? '' : 's'} waiting to sync',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: pendingList.length,
                      separatorBuilder: (_, _) => Container(
                        height: 0.5,
                        color: isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFE5E5EA),
                      ),
                      itemBuilder: (context, index) {
                        final scrobble = pendingList[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF22232A)
                                      : const Color(0xFFE5E5EA),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    CupertinoIcons.music_note,
                                    size: 20,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      scrobble.trackTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      scrobble.artistName +
                                          (scrobble.albumName != null
                                              ? ' · ${scrobble.albumName}'
                                              : ''),
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
                              const SizedBox(width: 8),
                              _buildStatusBadge(scrobble.status, isDark),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFE5E5EA),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isSyncing ? 'Syncing scrobbles with Last.fm…' : 'Scrobbles will sync automatically when online.',
                          style: TextStyle(
                            fontSize: 12,
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
    );
  }
}
