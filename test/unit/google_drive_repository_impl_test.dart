import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/authentication/domain/entities/auth_user.dart';
import 'package:musii/features/google_drive/data/repositories/google_drive_repository_impl.dart';

class MockAuthRepository implements AuthRepository {
  @override
  Future<Result<String, AppFailure>> getAccessToken() async {
    return const Result.success('test_token');
  }

  @override
  Future<Result<AuthUser?, AppFailure>> getCurrentUser() async {
    return const Result.success(null);
  }

  @override
  Future<Result<AuthUser, AppFailure>> signInWithGoogle() async {
    throw UnimplementedError();
  }

  @override
  Future<Result<void, AppFailure>> signOut() async {
    return const Result.success(null);
  }

  @override
  Stream<AuthUser?> watchCurrentUser() => Stream.value(null);
}

void main() {
  group('GoogleDriveRepositoryImpl', () {
    test('listFolders uses compact \$fields with NO whitespace and returns folders', () async {
      String? requestedFields;
      String? requestedQuery;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/drive/v3/files')) {
          requestedFields = request.url.queryParameters['fields'];
          requestedQuery = request.url.queryParameters['q'];

          final responseJson = {
            'files': [
              {
                'id': 'folder_music',
                'name': 'Music',
                'mimeType': 'application/vnd.google-apps.folder',
                'parents': ['root'],
              },
              {
                'id': 'folder_podcasts',
                'name': 'Podcasts',
                'mimeType': 'application/vnd.google-apps.folder',
                'parents': ['root'],
              },
            ],
          };
          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/drives')) {
          return http.Response(
            '{"drives":[]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final repo = GoogleDriveRepositoryImpl(
        authRepository: MockAuthRepository(),
        client: mockClient,
      );

      final result = await repo.listFolders(parentFolderId: 'root');

      expect(result.isSuccess, isTrue);
      final folders = result.dataOrNull!;
      expect(folders.length, equals(2));
      expect(folders[0].name, equals('Music'));
      expect(folders[1].name, equals('Podcasts'));

      // CRITICAL: fields parameter must be compact without whitespace
      expect(
        requestedFields,
        equals(
          'nextPageToken,incompleteSearch,files(id,name,mimeType,parents,shortcutDetails(targetId,targetMimeType))',
        ),
      );
      expect(requestedFields!.contains(' '), isFalse);
      expect(requestedQuery, contains("'root' in parents"));
    });

    test('listAudioFilesRecursively uses compact \$fields with NO whitespace and parses audio items', () async {
      String? requestedFields;
      final requestedQueries = <String>[];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/drive/v3/files')) {
          requestedFields = request.url.queryParameters['fields'];
          final q = request.url.queryParameters['q'];
          if (q != null) requestedQueries.add(q);

          final responseJson = {
            'files': [
              {
                'id': 'df_1',
                'name': 'Stay With Me.mp3',
                'mimeType': 'audio/mpeg',
                'size': '5000000',
                'modifiedTime': '2026-09-15T12:00:00.000Z',
                'md5Checksum': 'md5_1',
                'parents': ['folder_music'],
              },
              {
                'id': 'df_cover',
                'name': 'cover.jpg',
                'mimeType': 'image/jpeg',
                'size': '100000',
                'modifiedTime': '2026-09-15T12:00:00.000Z',
                'md5Checksum': 'md5_cover',
                'parents': ['folder_music'],
              },
            ],
          };
          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not found', 404);
      });

      final repo = GoogleDriveRepositoryImpl(
        authRepository: MockAuthRepository(),
        client: mockClient,
      );

      final result = await repo.listAudioFilesRecursively('folder_music');

      expect(result.isSuccess, isTrue);
      final items = result.dataOrNull!;
      expect(items.length, equals(2));
      expect(items[0].name, equals('Stay With Me.mp3'));
      expect(items[0].isLrc, isFalse);
      expect(items[0].isImage, isFalse);
      expect(items[1].name, equals('cover.jpg'));
      expect(items[1].isImage, isTrue);

      // CRITICAL: fields parameter must be compact without whitespace
      expect(
        requestedFields,
        equals(
          'nextPageToken,incompleteSearch,files(id,name,mimeType,size,modifiedTime,md5Checksum,shortcutDetails(targetId,targetMimeType))',
        ),
      );
      expect(requestedFields!.contains(' '), isFalse);
      expect(requestedQueries.first, contains("'folder_music' in parents"));
    });
  });
}
