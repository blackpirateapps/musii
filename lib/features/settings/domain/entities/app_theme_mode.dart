enum AppThemeMode {
  system,
  dark,
  light;

  String get label => switch (this) {
    AppThemeMode.system => 'Follow System',
    AppThemeMode.dark => 'Dark',
    AppThemeMode.light => 'Light',
  };

  static AppThemeMode fromString(String? value) {
    return switch (value?.toLowerCase()) {
      'dark' => AppThemeMode.dark,
      'light' => AppThemeMode.light,
      _ => AppThemeMode.system,
    };
  }
}
