import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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
    final pendingToken = _authRepository.getAccessToken();
    final abort = request is http.AbortableRequest
        ? request.abortTrigger
        : null;
    final tokenResult = abort == null
        ? await pendingToken
        : await Future.any([
            pendingToken,
            abort.then<Result<String, AppFailure>>(
              (_) => throw http.RequestAbortedException(request.url),
            ),
          ]);
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

class _AbortableClient extends http.BaseClient {
  final http.Client _delegate;
  final Future<void> _abortTrigger;

  _AbortableClient(this._delegate, this._abortTrigger);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortable =
        http.AbortableRequest(
            request.method,
            request.url,
            abortTrigger: _abortTrigger,
          )
          ..headers.addAll(request.headers)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;
    if (request is http.Request) abortable.bodyBytes = request.bodyBytes;
    return _delegate.send(abortable);
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

  drive.DriveApi _getDriveApi([Future<void>? abortTrigger]) => drive.DriveApi(
    abortTrigger == null ? _client : _AbortableClient(_client, abortTrigger),
  );

  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _shortcutMime = 'application/vnd.google-apps.shortcut';

  Future<void> _forEachFolderPage(
    drive.DriveApi api,
    String parentId,
    String fields,
    Future<void> Function(List<drive.File>) visit, {
    bool Function()? isCancelled,
    String? filter,
  }) async {
    String? token;
    final seenTokens = <String>{};
    do {
      if (isCancelled?.call() == true) return;
      final page = await api.files.list(
        q: "'$parentId' in parents and trashed = false${filter == null ? '' : ' and $filter'}",
        $fields: 'nextPageToken,incompleteSearch,files($fields)',
        orderBy: 'name',
        pageSize: 100,
        pageToken: token,
        spaces: 'drive',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (isCancelled?.call() == true) return;
      if (page.incompleteSearch == true) {
        throw const DriveApiFailure(
          'Google Drive returned an incomplete folder listing.',
        );
      }
      await visit(page.files ?? const []);
      token = page.nextPageToken;
      if (token != null && !seenTokens.add(token)) {
        throw const DriveApiFailure(
          'Google Drive repeated a folder page token.',
        );
      }
    } while (token != null);
  }

  @override
  Future<Result<List<DriveFolderItem>, AppFailure>> listFolders({
    String? parentFolderId,
  }) async {
    try {
      final api = _getDriveApi();
      final parentId = parentFolderId ?? 'root';
      final folders = <String, DriveFolderItem>{};
      await _forEachFolderPage(
        api,
        parentId,
        'id,name,mimeType,parents,shortcutDetails(targetId,targetMimeType)',
        (files) async {
          for (final file in files) {
            final id = _folderTargetId(file);
            if (id == null || id == parentId) continue;
            folders.putIfAbsent(
              id,
              () => DriveFolderItem(
                id: id,
                name: file.name ?? 'Untitled Folder',
                parentFolderId: parentId,
              ),
            );
          }
        },
        filter: "(mimeType = '$_folderMime' or mimeType = '$_shortcutMime')",
      );
      if (parentId == 'root') {
        String? token;
        final seenTokens = <String>{};
        do {
          final page = await api.drives.list(
            $fields: 'nextPageToken,drives(id,name)',
            pageSize: 100,
            pageToken: token,
          );
          for (final sharedDrive in page.drives ?? <drive.Drive>[]) {
            final id = sharedDrive.id;
            if (id == null) continue;
            folders.putIfAbsent(
              id,
              () => DriveFolderItem(
                id: id,
                name: sharedDrive.name ?? 'Shared drive',
              ),
            );
          }
          token = page.nextPageToken;
          if (token != null && !seenTokens.add(token)) {
            throw const DriveApiFailure(
              'Google Drive repeated a shared drive page token.',
            );
          }
        } while (token != null);
      }
      return Result.success(folders.values.toList());
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

  String? _folderTargetId(drive.File file) {
    if (file.mimeType == _folderMime) return file.id;
    final shortcut = file.shortcutDetails;
    return file.mimeType == _shortcutMime &&
            shortcut?.targetMimeType == _folderMime
        ? shortcut?.targetId
        : null;
  }

  @override
  Future<Result<List<DriveFileItem>, AppFailure>> listAudioFilesRecursively(
    String rootFolderId, {
    void Function(int discoveredCount)? onProgress,
    void Function(DriveFileItem file)? onFileDiscovered,
    FutureOr<void> Function(
      List<String> pendingFolders,
      Set<String> visitedFolders,
    )?
    onFolderStateChanged,
    List<String>? initialFolderQueue,
    Set<String>? initialVisitedFolders,
    bool Function()? isCancelled,
    Map<String, String?>? folderParentMap,
    void Function(String folderId, String parentId)? onFolderDiscovered,
    Future<void>? abortTrigger,
  }) async {
    try {
      final api = _getDriveApi(abortTrigger);
      final discovered = <String, DriveFileItem>{};
      final queue = Queue<String>.of(initialFolderQueue ?? [rootFolderId]);
      final queued = queue.toSet();
      final visited = {...?initialVisitedFolders};
      var audioCount = 0;

      while (queue.isNotEmpty && isCancelled?.call() != true) {
        final folderId = queue.removeFirst();
        queued.remove(folderId);
        if (visited.contains(folderId)) continue;
        final filesInFolder = <String, DriveFileItem>{};
        final children = <String>{};

        await _forEachFolderPage(
          api,
          folderId,
          'id,name,mimeType,size,modifiedTime,md5Checksum,shortcutDetails(targetId,targetMimeType)',
          (files) async {
            for (final file in files) {
              if (isCancelled?.call() == true) return;
              final child = _folderTargetId(file);
              if (child != null) {
                if (child != folderId &&
                    !visited.contains(child) &&
                    !queued.contains(child)) {
                  children.add(child);
                }
                continue;
              }
              final item = await _readMusicItem(api, file, folderId);
              if (item != null && !discovered.containsKey(item.id)) {
                filesInFolder.putIfAbsent(item.id, () => item);
              }
            }
          },
          isCancelled: isCancelled,
        );
        if (isCancelled?.call() == true) break;

        for (final child in children) {
          queue.add(child);
          queued.add(child);
          folderParentMap?[child] = folderId;
          onFolderDiscovered?.call(child, folderId);
        }
        visited.add(folderId);
        for (final item in filesInFolder.values) {
          discovered[item.id] = item;
          onFileDiscovered?.call(item);
          if (!item.isLrc && !item.isImage) audioCount++;
        }
        await onFolderStateChanged?.call(queue.toList(), visited);
        onProgress?.call(audioCount);
      }

      return Result.success(discovered.values.toList());
    } catch (e, st) {
      if (isCancelled?.call() == true) return const Result.success([]);
      AppLogger.error(
        LogCategory.drive,
        'Error during recursive audio scan',
        e,
        st,
      );
      return Result.failure(
        e is AppFailure
            ? e
            : DriveApiFailure(
                'Failed while scanning Google Drive for music files',
                technicalDetails: e.toString(),
                cause: e,
              ),
      );
    }
  }

  Future<DriveFileItem?> _readMusicItem(
    drive.DriveApi api,
    drive.File file,
    String folderId,
  ) async {
    final shortcut = file.mimeType == _shortcutMime
        ? file.shortcutDetails
        : null;
    final id = shortcut?.targetId ?? file.id;
    if (id == null || (shortcut != null && shortcut.targetId == null)) {
      return null;
    }
    final name = file.name ?? '';
    final mime = shortcut?.targetMimeType ?? file.mimeType ?? '';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isLrc = ext == 'lrc';
    final isImage = AppImageConstants.isImageFile(name, mime);
    if (!isLrc &&
        !isImage &&
        !mime.startsWith('audio/') &&
        !AppAudioConstants.supportedMimeTypes.contains(mime) &&
        !AppAudioConstants.supportedExtensions.contains(ext)) {
      return null;
    }
    final metadata = shortcut == null
        ? file
        : await api.files.get(
            id,
            supportsAllDrives: true,
            $fields: 'size,modifiedTime,md5Checksum,trashed',
          ) as drive.File;
    if (metadata.trashed == true) return null;
    return DriveFileItem(
      id: id,
      name: name,
      mimeType: mime,
      size: int.tryParse(metadata.size ?? '') ?? 0,
      modifiedTime: metadata.modifiedTime,
      md5Checksum: metadata.md5Checksum,
      parentFolderId: folderId,
      isLrc: isLrc,
      isImage: isImage,
    );
  }

  @override
  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    IOSink? sink;
    try {
      final driveApi = _getDriveApi(abortTrigger);
      AppLogger.debug(
        LogCategory.drive,
        'Downloading Drive file $fileId to ${destinationFile.path}',
      );

      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
      ) as drive.Media;

      final totalBytes = media.length ?? 0;
      int receivedBytes = 0;

      sink = destinationFile.openWrite();
      unawaited(sink.done.catchError((Object _) {}));

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
        await sink?.close();
      } catch (_) {}
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
  Future<Result<String, AppFailure>> downloadTextFile(
    String fileId, {
    Future<void>? abortTrigger,
  }) async {
    try {
      final driveApi = _getDriveApi(abortTrigger);
      AppLogger.debug(LogCategory.drive, 'Downloading text file $fileId');

      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      return Result.success(content);
    } catch (e, st) {
      AppLogger.error(
        LogCategory.drive,
        'Failed to download text file $fileId',
        e,
        st,
      );
      return Result.failure(
        DriveApiFailure(
          'Failed to download text file from Google Drive',
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
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&supportsAllDrives=true',
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
