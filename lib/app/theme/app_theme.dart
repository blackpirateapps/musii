import 'package:flutter/cupertino.dart';

abstract final class AppTheme {
  static const Color accentColor = CupertinoColors.systemPink;

  static CupertinoThemeData lightTheme = const CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: accentColor,
    primaryContrastingColor: CupertinoColors.white,
    barBackgroundColor: Color(0xCCF8F8F8),
    scaffoldBackgroundColor: CupertinoColors.systemBackground,
    textTheme: CupertinoTextThemeData(
      primaryColor: CupertinoColors.label,
      navLargeTitleTextStyle: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.37,
        color: CupertinoColors.black,
      ),
      navTitleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: CupertinoColors.black,
      ),
      textStyle: TextStyle(
        fontSize: 17,
        letterSpacing: -0.41,
        color: CupertinoColors.label,
      ),
    ),
  );

  static CupertinoThemeData darkTheme = const CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: accentColor,
    primaryContrastingColor: CupertinoColors.white,
    barBackgroundColor: Color(0xCC1A1A1A),
    scaffoldBackgroundColor: Color(0xFF0C0D12),
    textTheme: CupertinoTextThemeData(
      primaryColor: CupertinoColors.white,
      navLargeTitleTextStyle: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.37,
        color: CupertinoColors.white,
      ),
      navTitleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: CupertinoColors.white,
      ),
      textStyle: TextStyle(
        fontSize: 17,
        letterSpacing: -0.41,
        color: CupertinoColors.white,
      ),
    ),
  );
}
