import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bootstrap/providers.dart';
import '../../features/google_drive/presentation/pages/drive_connect_page.dart';
import '../../features/google_drive/presentation/pages/drive_folder_picker_page.dart';
import '../../features/library/presentation/pages/album_detail_page.dart';
import '../../features/library/presentation/pages/artist_detail_page.dart';
import '../../features/library/presentation/pages/home_page.dart';
import '../../features/library/presentation/pages/library_page.dart';
import '../../features/playback/presentation/pages/now_playing_page.dart';
import '../../features/playback/presentation/widgets/mini_player.dart';
import '../../features/playlists/presentation/pages/playlist_detail_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    // Top-level modal for Now Playing
    GoRoute(
      path: '/now-playing',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) =>
          const CupertinoPage(fullscreenDialog: true, child: NowPlayingPage()),
    ),

    // Stateful Nested Shell for 4 primary tabs
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return RootNavigationShell(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),

        // Branch 1: Library with subroutes
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryPage(),
              routes: [
                GoRoute(
                  path: 'album/:id',
                  builder: (context, state) =>
                      AlbumDetailPage(albumId: state.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'artist/:id',
                  builder: (context, state) =>
                      ArtistDetailPage(artistId: state.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'playlist/:id',
                  builder: (context, state) => PlaylistDetailPage(
                    playlistId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),

        // Branch 2: Search
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchPage(),
            ),
          ],
        ),

        // Branch 3: Settings with Drive subroutes
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
              routes: [
                GoRoute(
                  path: 'drive-setup',
                  builder: (context, state) => const DriveConnectPage(),
                ),
                GoRoute(
                  path: 'drive-folder-picker',
                  builder: (context, state) => const DriveFolderPickerPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

class RootNavigationShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const RootNavigationShell({super.key, required this.navigationShell});

  @override
  ConsumerState<RootNavigationShell> createState() =>
      _RootNavigationShellState();
}

class _RootNavigationShellState extends ConsumerState<RootNavigationShell> {
  @override
  Widget build(BuildContext context) {
    final playerSnapshot = ref.watch(playerStateProvider).value;
    final hasActiveTrack = playerSnapshot?.currentTrack != null;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          // Current branch's navigation stack
          widget.navigationShell,

          // Docked Mini-Player & CupertinoTabBar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasActiveTrack) const MiniPlayer(),
                CupertinoTabBar(
                  currentIndex: widget.navigationShell.currentIndex,
                  activeColor: CupertinoColors.systemPink,
                  inactiveColor: CupertinoColors.systemGrey,
                  iconSize: 24.0,
                  backgroundColor: isDark
                      ? const Color(0xE5121318)
                      : const Color(0xE5F8F8F8),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? const Color(0x1FFFFFFF)
                          : const Color(0x1F000000),
                      width: 0.5,
                    ),
                  ),
                  onTap: (index) {
                    widget.navigationShell.goBranch(
                      index,
                      initialLocation:
                          index == widget.navigationShell.currentIndex,
                    );
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 2.0),
                        child: Icon(CupertinoIcons.house_fill),
                      ),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 2.0),
                        child: Icon(CupertinoIcons.music_albums_fill),
                      ),
                      label: 'Library',
                    ),
                    BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 2.0),
                        child: Icon(CupertinoIcons.search),
                      ),
                      label: 'Search',
                    ),
                    BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 2.0),
                        child: Icon(CupertinoIcons.gear_solid),
                      ),
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
