import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/providers.dart';
import '../../features/library/presentation/pages/home_page.dart';
import '../../features/library/presentation/pages/library_page.dart';
import '../../features/playback/presentation/widgets/mini_player.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';

class RootNavigationShell extends ConsumerStatefulWidget {
  const RootNavigationShell({super.key});

  @override
  ConsumerState<RootNavigationShell> createState() =>
      _RootNavigationShellState();
}

class _RootNavigationShellState extends ConsumerState<RootNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    LibraryPage(),
    SearchPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final playerSnapshot = ref.watch(playerStateProvider).value;
    final hasActiveTrack = playerSnapshot?.currentTrack != null;

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          // Tab Content
          IndexedStack(index: _currentIndex, children: _pages),

          // Docked Mini-Player and CupertinoTabBar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasActiveTrack) const MiniPlayer(),
                CupertinoTabBar(
                  currentIndex: _currentIndex,
                  activeColor: CupertinoColors.systemPink,
                  onTap: (index) {
                    setState(() => _currentIndex = index);
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.house_fill),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.music_albums_fill),
                      label: 'Library',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.search),
                      label: 'Search',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.gear_solid),
                      label: 'Settings',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
