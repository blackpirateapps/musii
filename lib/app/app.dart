import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/domain/entities/app_theme_mode.dart';
import 'bootstrap/providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class MusiiApp extends ConsumerStatefulWidget {
  const MusiiApp({super.key});

  @override
  ConsumerState<MusiiApp> createState() => _MusiiAppState();
}

class _MusiiAppState extends ConsumerState<MusiiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final platformBrightness =
        View.maybeOf(context)?.platformDispatcher.platformBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    final isDark = switch (themeMode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system => platformBrightness == Brightness.dark,
    };

    return CupertinoApp.router(
      title: 'Musii',
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}
