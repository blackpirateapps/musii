import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

enum LogCategory {
  auth('Auth'),
  drive('Drive'),
  sync('Sync'),
  metadata('Metadata'),
  database('Database'),
  cache('Cache'),
  playback('Playback'),
  ui('UI');

  final String label;
  const LogCategory(this.label);
}

class AppLogger {
  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static String _sanitize(String message) {
    // Redact OAuth tokens or potential secret strings
    return message
        .replaceAll(RegExp(r'(ya29\.[a-zA-Z0-9_-]+)'), '[REDACTED_TOKEN]')
        .replaceAll(RegExp(r'(Bearer\s+[a-zA-Z0-9._-]+)'), 'Bearer [REDACTED]');
  }

  static void debug(
    LogCategory category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (kReleaseMode) return;
    _logger.d(
      '[${category.label}] ${_sanitize(message)}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void info(
    LogCategory category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _logger.i(
      '[${category.label}] ${_sanitize(message)}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void warning(
    LogCategory category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _logger.w(
      '[${category.label}] ${_sanitize(message)}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    LogCategory category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _logger.e(
      '[${category.label}] ${_sanitize(message)}',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
