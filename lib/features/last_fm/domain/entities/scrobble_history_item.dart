import 'package:flutter/foundation.dart';

@immutable
class ScrobbleHistoryItem {
  final String id;
  final String? trackId;
  final String trackTitle;
  final String artistName;
  final String? albumName;
  final int timestamp;
  final DateTime scrobbledAt;

  const ScrobbleHistoryItem({
    required this.id,
    this.trackId,
    required this.trackTitle,
    required this.artistName,
    this.albumName,
    required this.timestamp,
    required this.scrobbledAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrobbleHistoryItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(id, timestamp);

  @override
  String toString() =>
      'ScrobbleHistoryItem(id: $id, title: $trackTitle, artist: $artistName, scrobbledAt: $scrobbledAt)';
}
