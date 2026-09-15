import 'package:flutter/cupertino.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class MusiiApp extends StatelessWidget {
  const MusiiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp.router(
      title: 'Musii',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}
