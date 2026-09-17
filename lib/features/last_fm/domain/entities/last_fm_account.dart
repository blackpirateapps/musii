import 'package:flutter/foundation.dart';

enum LastFmAccountStatus {
  connected,
  reauthRequired,
  disconnected;

  static LastFmAccountStatus fromString(String? val) {
    return switch (val) {
      'connected' => LastFmAccountStatus.connected,
      'reauth_required' => LastFmAccountStatus.reauthRequired,
      _ => LastFmAccountStatus.disconnected,
    };
  }

  String toDbString() => switch (this) {
    LastFmAccountStatus.connected => 'connected',
    LastFmAccountStatus.reauthRequired => 'reauth_required',
    LastFmAccountStatus.disconnected => 'disconnected',
  };
}

@immutable
class LastFmAccount {
  final String username;
  final String? realName;
  final String? avatarUrl;
  final String profileUrl;
  final int scrobbleCount;
  final LastFmAccountStatus status;
  final DateTime? lastSyncedAt;

  const LastFmAccount({
    required this.username,
    this.realName,
    this.avatarUrl,
    required this.profileUrl,
    this.scrobbleCount = 0,
    this.status = LastFmAccountStatus.connected,
    this.lastSyncedAt,
  });

  bool get isConnected => status == LastFmAccountStatus.connected;
  bool get requiresReauth => status == LastFmAccountStatus.reauthRequired;

  LastFmAccount copyWith({
    String? username,
    String? realName,
    String? avatarUrl,
    String? profileUrl,
    int? scrobbleCount,
    LastFmAccountStatus? status,
    DateTime? lastSyncedAt,
  }) {
    return LastFmAccount(
      username: username ?? this.username,
      realName: realName ?? this.realName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      profileUrl: profileUrl ?? this.profileUrl,
      scrobbleCount: scrobbleCount ?? this.scrobbleCount,
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LastFmAccount &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          realName == other.realName &&
          avatarUrl == other.avatarUrl &&
          profileUrl == other.profileUrl &&
          scrobbleCount == other.scrobbleCount &&
          status == other.status &&
          lastSyncedAt == other.lastSyncedAt;

  @override
  int get hashCode => Object.hash(
    username,
    realName,
    avatarUrl,
    profileUrl,
    scrobbleCount,
    status,
    lastSyncedAt,
  );

  @override
  String toString() =>
      'LastFmAccount(username: $username, status: $status, scrobbles: $scrobbleCount)';
}
