import 'dart:async';

import 'package:drift/drift.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_user.dart';

class GoogleAuthRepository implements AuthRepository {
  final GoogleSignIn _googleSignIn;
  final AppDatabase _database;
  final StreamController<AuthUser?> _userStreamController =
      StreamController<AuthUser?>.broadcast();

  GoogleAuthRepository({
    required AppDatabase database,
    GoogleSignIn? googleSignIn,
  }) : _database = database,
       _googleSignIn =
           googleSignIn ??
           GoogleSignIn(scopes: [drive.DriveApi.driveReadonlyScope]) {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      if (account != null) {
        final user = AuthUser(
          id: account.id,
          email: account.email,
          displayName: account.displayName,
          photoUrl: account.photoUrl,
        );
        _syncUserToDatabase(user);
        _userStreamController.add(user);
      } else {
        _userStreamController.add(null);
      }
    });
  }

  Future<void> _syncUserToDatabase(AuthUser user) async {
    try {
      await _database
          .into(_database.users)
          .insertOnConflictUpdate(
            UsersCompanion(
              id: Value(user.id),
              email: Value(user.email),
              displayName: Value(user.displayName),
              photoUrl: Value(user.photoUrl),
              createdAt: Value(DateTime.now()),
            ),
          );
    } catch (e) {
      AppLogger.warning(LogCategory.auth, 'Failed to save user in database', e);
    }
  }

  @override
  Future<Result<AuthUser?, AppFailure>> getCurrentUser() async {
    try {
      final account =
          _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (account != null) {
        final user = AuthUser(
          id: account.id,
          email: account.email,
          displayName: account.displayName,
          photoUrl: account.photoUrl,
        );
        await _syncUserToDatabase(user);
        return Result.success(user);
      }

      // Check if we have a cached user in the database
      final dbUsers = await (_database.select(_database.users)..limit(1)).get();
      if (dbUsers.isNotEmpty) {
        final u = dbUsers.first;
        return Result.success(
          AuthUser(
            id: u.id,
            email: u.email,
            displayName: u.displayName,
            photoUrl: u.photoUrl,
          ),
        );
      }

      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(LogCategory.auth, 'Failed to get current user', e, st);
      return Result.failure(
        AuthenticationFailure('Failed to get user session', cause: e),
      );
    }
  }

  @override
  Future<Result<AuthUser, AppFailure>> signInWithGoogle() async {
    try {
      AppLogger.info(LogCategory.auth, 'Initiating Google sign-in');
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return const Result.failure(
          AuthenticationFailure('Google sign-in was cancelled by user'),
        );
      }

      final user = AuthUser(
        id: account.id,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );

      await _syncUserToDatabase(user);
      _userStreamController.add(user);

      AppLogger.info(
        LogCategory.auth,
        'Google sign-in successful for ${user.email}',
      );
      return Result.success(user);
    } catch (e, st) {
      AppLogger.error(LogCategory.auth, 'Google sign-in error', e, st);
      return Result.failure(
        AuthenticationFailure(
          'Google sign-in failed. Please check network and Google Play Services.',
          technicalDetails: e.toString(),
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> signOut() async {
    try {
      AppLogger.info(LogCategory.auth, 'Signing out from Google');
      await _googleSignIn.signOut();
      await _database.delete(_database.users).go();
      _userStreamController.add(null);
      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(LogCategory.auth, 'Sign-out error', e, st);
      return Result.failure(
        AuthenticationFailure('Failed to sign out', cause: e),
      );
    }
  }

  @override
  Stream<AuthUser?> watchCurrentUser() async* {
    // Emit current user immediately on subscription so cold starts
    // don't show the "Connect Google Drive" empty state incorrectly.
    final currentResult = await getCurrentUser();
    yield currentResult.dataOrNull;
    // Then forward all future changes from sign-in / sign-out events.
    yield* _userStreamController.stream;
  }

  @override
  Future<Result<String, AppFailure>> getAccessToken() async {
    try {
      final account =
          _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (account == null) {
        return const Result.failure(
          AuthenticationFailure('No Google account currently signed in'),
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) {
        return const Result.failure(
          AuthenticationFailure('Failed to obtain Google access token'),
        );
      }

      return Result.success(token);
    } catch (e, st) {
      AppLogger.error(LogCategory.auth, 'Failed to obtain access token', e, st);
      return Result.failure(
        AuthenticationFailure('Failed to authenticate with Google', cause: e),
      );
    }
  }
}
