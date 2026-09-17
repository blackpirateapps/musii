import 'package:flutter/foundation.dart';

enum ScrobbleStatus {
  pending,
  sending,
  failedRetryable,
  failedReauth;

  static ScrobbleStatus fromString(String val) {
    return switch (val) {
      'sending' => ScrobbleStatus.sending,
      'failed_retryable' => ScrobbleStatus.failedRetryable,
      'failed_reauth' => ScrobbleStatus.failedReauth,
      _ => ScrobbleStatus.pending,
    };
  }

  String toDbString() => switch (this) {
    ScrobbleStatus.pending => 'pending',
    ScrobbleStatus.sending => 'sending',
    ScrobbleStatus.failedRetryable => 'failed_retryable',
    ScrobbleStatus.failedReauth => 'failed_reauth',
  };
}

@immutable
class PendingScrobble {
  final String id;
  final String? trackId;
  final String trackTitle;
  final String artistName;
  final String? albumName;
  final String? albumArtist;
  final int durationMs;
  final int timestamp; // Unix timestamp in seconds
  final ScrobbleStatus status;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? errorMessage;
  final DateTime createdAt;

  const PendingScrobble({
    required this.id,
    this.trackId,
    required this.trackTitle,
    required this.artistName,
    this.albumName,
    this.albumArtist,
    required this.durationMs,
    required this.timestamp,
    this.status = ScrobbleStatus.pending,
    this.attempts = 0,
    this.lastAttemptAt,
    this.errorMessage,
    required this.createdAt,
  });

  PendingScrobble copyWith({
    String? id,
    String? trackId,
    String? trackTitle,
    String? artistName,
    String? albumName,
    String? albumArtist,
    int? durationMs,
    int? timestamp,
    ScrobbleStatus? status,
    int? attempts,
    DateTime? lastAttemptAt,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return PendingScrobble(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      trackTitle: trackTitle ?? this.trackTitle,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      albumArtist: albumArtist ?? this.albumArtist,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingScrobble &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          timestamp == other.timestamp &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, timestamp, status);

  @override
  String toString() =>
      'PendingScrobble(id: $id, title: $trackTitle, artist: $artistName, status: $status)';
}
