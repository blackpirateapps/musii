import 'package:flutter/foundation.dart';

@immutable
class ScrobbleSettings {
  final bool scrobblingEnabled;
  final bool nowPlayingEnabled;

  const ScrobbleSettings({
    this.scrobblingEnabled = true,
    this.nowPlayingEnabled = true,
  });

  ScrobbleSettings copyWith({
    bool? scrobblingEnabled,
    bool? nowPlayingEnabled,
  }) {
    return ScrobbleSettings(
      scrobblingEnabled: scrobblingEnabled ?? this.scrobblingEnabled,
      nowPlayingEnabled: nowPlayingEnabled ?? this.nowPlayingEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrobbleSettings &&
          runtimeType == other.runtimeType &&
          scrobblingEnabled == other.scrobblingEnabled &&
          nowPlayingEnabled == other.nowPlayingEnabled;

  @override
  int get hashCode => Object.hash(scrobblingEnabled, nowPlayingEnabled);

  @override
  String toString() =>
      'ScrobbleSettings(scrobbling: $scrobblingEnabled, nowPlaying: $nowPlayingEnabled)';
}
