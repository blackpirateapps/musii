import 'package:flutter/foundation.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';

@immutable
class AuthUser {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthUser &&
          other.id == id &&
          other.email == email &&
          other.displayName == displayName &&
          other.photoUrl == photoUrl);

  @override
  int get hashCode => Object.hash(id, email, displayName, photoUrl);

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, displayName: $displayName)';
}

abstract class AuthRepository {
  Future<Result<AuthUser?, AppFailure>> getCurrentUser();
  Future<Result<AuthUser, AppFailure>> signInWithGoogle();
  Future<Result<void, AppFailure>> signOut();
  Stream<AuthUser?> watchCurrentUser();
  Future<Result<String, AppFailure>> getAccessToken();
}
