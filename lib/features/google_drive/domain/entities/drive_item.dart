import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';

@immutable
class DriveFolderItem {
  final String id;
  final String name;
  final String? parentFolderId;
  final String path;

  const DriveFolderItem({
    required this.id,
    required this.name,
    this.parentFolderId,
    this.path = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DriveFolderItem && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DriveFolderItem(id: $id, name: $name, path: $path)';
}

@immutable
class DriveFileItem {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime? modifiedTime;
  final String? md5Checksum;
  final String? parentFolderId;
  final bool isLrc;

  const DriveFileItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.modifiedTime,
    this.md5Checksum,
    this.parentFolderId,
    this.isLrc = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DriveFileItem && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DriveFileItem(id: $id, name: $name, size: $size, isLrc: $isLrc)';
}

abstract class GoogleDriveRepository {
  Future<Result<List<DriveFolderItem>, AppFailure>> listFolders({
    String? parentFolderId,
  });

  Future<Result<List<DriveFileItem>, AppFailure>> listAudioFilesRecursively(
    String rootFolderId, {
    void Function(int discoveredCount)? onProgress,
  });

  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });

  Future<Result<String, AppFailure>> downloadTextFile(String fileId);

  Future<Result<List<int>, AppFailure>> readByteRange({
    required String fileId,
    required int start,
    required int end,
  });
}
