import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../domain/entities/drive_item.dart';

class _AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _client = http.Client();
  final AuthRepository _authRepository;

  _AuthenticatedHttpClient(this._authRepository);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final tokenResult = await _authRepository.getAccessToken();
    if (tokenResult.isFailure) {
      throw const AuthenticationFailure('Not authenticated with Google');
    }
    final token = tokenResult.dataOrNull;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class GoogleDriveRepositoryImpl implements GoogleDriveRepository {
  final AuthRepository _authRepository;
  final http.Client _client;

  GoogleDriveRepositoryImpl({
    required AuthRepository authRepository,
    http.Client? client,
  }) : _authRepository = authRepository,
       _client = client ?? _AuthenticatedHttpClient(authRepository);

  drive.DriveApi _getDriveApi() => drive.DriveApi(_client);

  @override
  Future<Result<List<DriveFolderItem>, AppFailure>> listFolders({
    String? parentFolderId,
  }) async {
    try {
      final driveApi = _getDriveApi();
      final parentId = parentFolderId ?? 'root';
      final query =
          "mimeType = 'application/vnd.google-apps.folder' and '$parentId' in parents and trashed = false";

      AppLogger.debug(
        LogCategory.drive,
        'Listing folders for parent: $parentId',
      );

      final fileList = await driveApi.files.list(
        q: query,
        $fields: 'files(id, name, parents)',
        orderBy: 'name',
        pageSize: 100,
        spaces: 'drive',
      );

      final folders = (fileList.files ?? []).map((f) {
        return DriveFolderItem(
          id: f.id ?? '',
          name: f.name ?? 'Untitled Folder',
          parentFolderId: (f.parents != null && f.parents!.isNotEmpty)
              ? f.parents!.first
              : null,
        );
      }).toList();

      return Result.success(folders);
    } catch (e, st) {
      AppLogger.error(LogCategory.drive, 'Failed to list folders', e, st);
      return Result.failure(
        DriveApiFailure(
          'Failed to retrieve Google Drive folders',
          technicalDetails: e.toString(),
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<List<DriveFileItem>, AppFailure>> listAudioFilesRecursively(
    String rootFolderId, {
    void Function(int discoveredCount)? onProgress,
  }) async {
    try {
      final driveApi = _getDriveApi();
      final List<DriveFileItem> discoveredAudio = [];
      final List<String> folderQueue = [rootFolderId];
      final Set<String> visitedFolders = {};

      AppLogger.info(
        LogCategory.drive,
        'Beginning recursive scan of Drive folder: $rootFolderId',
      );

      while (folderQueue.isNotEmpty) {
        final currentFolderId = folderQueue.removeAt(0);
        if (visitedFolders.contains(currentFolderId)) continue;
        visitedFolders.add(currentFolderId);

        String? pageToken;
        do {
          final query = "'$currentFolderId' in parents and trashed = false";
          final result = await driveApi.files.list(
            q: query,
            $fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime, md5Checksum, parents)',
            pageSize: 100,
            pageToken: pageToken,
            spaces: 'drive',
          );

          final files = result.files ?? [];
          for (final f in files) {
            final fId = f.id;
            final name = f.name ?? '';
            final mime = f.mimeType ?? '';
            if (fId == null) continue;

            if (mime == 'application/vnd.google-apps.folder') {
              folderQueue.add(fId);
            } else {
              final ext = name.contains('.')
                  ? name.split('.').last.toLowerCase()
                  : '';
              final isAudioExt = AppAudioConstants.supportedExtensions.contains(
                ext,
              );
              final isAudioMime =
                  mime.startsWith('audio/') ||
                  AppAudioConstants.supportedMimeTypes.contains(mime);

              if (isAudioExt || isAudioMime) {
                final sizeBytes = int.tryParse(f.size ?? '0') ?? 0;
                final fileItem = DriveFileItem(
                  id: fId,
                  name: name,
                  mimeType: mime.isNotEmpty ? mime : 'audio/mpeg',
                  size: sizeBytes,
                  modifiedTime: f.modifiedTime,
                  md5Checksum: f.md5Checksum,
                  parentFolderId: currentFolderId,
                );
                discoveredAudio.add(fileItem);
                onProgress?.call(discoveredAudio.length);
              }
            }
          }
          pageToken = result.nextPageToken;
        } while (pageToken != null);
      }

      AppLogger.info(
        LogCategory.drive,
        'Recursive scan completed. Discovered ${discoveredAudio.length} audio tracks.',
      );

      return Result.success(discoveredAudio);
    } catch (e, st) {
      AppLogger.error(
        LogCategory.drive,
        'Error during recursive audio scan',
        e,
        st,
      );
      return Result.failure(
        DriveApiFailure(
          'Failed while scanning Google Drive for music files',
          technicalDetails: e.toString(),
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    try {
      final driveApi = _getDriveApi();
      AppLogger.debug(
        LogCategory.drive,
        'Downloading Drive file $fileId to ${destinationFile.path}',
      );

      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final totalBytes = media.length ?? 0;
      int receivedBytes = 0;

      final sink = destinationFile.openWrite();

      await for (final chunk in media.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();

      AppLogger.debug(
        LogCategory.drive,
        'Completed download of file $fileId ($receivedBytes bytes)',
      );
      return Result.success(destinationFile);
    } catch (e, st) {
      AppLogger.error(
        LogCategory.drive,
        'Download failed for file $fileId',
        e,
        st,
      );
      try {
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
      } catch (_) {}

      return Result.failure(
        DriveApiFailure(
          'Failed to download file from Google Drive',
          technicalDetails: e.toString(),
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<List<int>, AppFailure>> readByteRange({
    required String fileId,
    required int start,
    required int end,
  }) async {
    try {
      final tokenResult = await _authRepository.getAccessToken();
      if (tokenResult.isFailure) {
        return Result.failure(tokenResult.failureOrNull!);
      }
      final token = tokenResult.dataOrNull;

      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Range': 'bytes=$start-$end',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        return Result.success(response.bodyBytes);
      } else {
        return Result.failure(
          DriveApiFailure(
            'Failed range request: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          ),
        );
      }
    } catch (e, st) {
      AppLogger.error(
        LogCategory.drive,
        'Byte range request error for $fileId',
        e,
        st,
      );
      return Result.failure(
        DriveApiFailure(
          'Failed to read audio byte range',
          technicalDetails: e.toString(),
          cause: e,
        ),
      );
    }
  }
}
