import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../library/presentation/widgets/empty_state.dart';
import '../../domain/entities/scrobble_history_item.dart';
import '../providers/last_fm_providers.dart';

class ScrobbleHistoryPage extends ConsumerWidget {
  const ScrobbleHistoryPage({super.key});

  String _formatScrobbleTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(dt.year, dt.month, dt.day);

    if (today == itemDay) {
      return DateFormat('h:mm a').format(dt);
    } else if (today.difference(itemDay).inDays == 1) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dt)}';
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(lastFmScrobbleHistoryProvider);
    final historyList = historyAsync.value ?? const <ScrobbleHistoryItem>[];
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Recent Scrobbles'),
      ),
      child: SafeArea(
        child: historyList.isEmpty
            ? const Center(
                child: EmptyState(
                  icon: CupertinoIcons.clock,
                  title: 'No Scrobbles Yet',
                  subtitle: 'Songs you listen to in Musii will appear here once submitted to Last.fm.',
                ),
              )
            : ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: historyList.length,
                separatorBuilder: (_, _) => Container(
                  height: 0.5,
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                ),
                itemBuilder: (context, index) {
                  final item = historyList[index];
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
                                item.trackTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.artistName +
                                    (item.albumName != null
                                        ? ' · ${item.albumName}'
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
                        Text(
                          _formatScrobbleTime(item.scrobbledAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
