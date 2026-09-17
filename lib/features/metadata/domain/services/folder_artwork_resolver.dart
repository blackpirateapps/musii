import '../../../../core/constants/app_constants.dart';
import '../../../google_drive/domain/entities/drive_item.dart';

class FolderArtworkResolver {
  const FolderArtworkResolver._();

  /// Resolves the best candidate image file for an album's folder.
  ///
  /// Priority:
  /// 1. Standard name in immediate folder (`cover`, `folder`, `front`, `albumart`, `album`, `artwork`).
  /// 2. Standard name in parent folder (for multi-disc layouts like CD1/CD2).
  /// 3. Any valid image file in immediate folder.
  /// 4. Any valid image file in parent folder.
  static DriveFileItem? resolveCandidate({
    required String? folderId,
    required Map<String, List<DriveFileItem>> folderImages,
    Map<String, String?>? folderParentMap,
  }) {
    if (folderId == null || folderId.isEmpty) return null;

    final immediateImages = folderImages[folderId] ?? [];
    final parentFolderId = folderParentMap?[folderId];
    final parentImages = (parentFolderId != null && parentFolderId.isNotEmpty)
        ? (folderImages[parentFolderId] ?? [])
        : <DriveFileItem>[];

    // 1. Standard name in immediate folder
    final immediateStandard = _findBestStandardMatch(immediateImages);
    if (immediateStandard != null) return immediateStandard;

    // 2. Standard name in parent folder
    if (parentImages.isNotEmpty) {
      final parentStandard = _findBestStandardMatch(parentImages);
      if (parentStandard != null) return parentStandard;
    }

    // 3. Fallback to any valid image in immediate folder
    if (immediateImages.isNotEmpty) {
      final firstValidImmediate = immediateImages
          .where(_isValidImage)
          .firstOrNull;
      if (firstValidImmediate != null) return firstValidImmediate;
    }

    // 4. Fallback to any valid image in parent folder
    if (parentImages.isNotEmpty) {
      final firstValidParent = parentImages.where(_isValidImage).firstOrNull;
      if (firstValidParent != null) return firstValidParent;
    }

    return null;
  }

  static DriveFileItem? _findBestStandardMatch(List<DriveFileItem> images) {
    if (images.isEmpty) return null;

    final validImages = images.where(_isValidImage).toList();
    if (validImages.isEmpty) return null;

    // Check by standard name priority
    for (final standardName in AppImageConstants.standardCoverNames) {
      for (final img in validImages) {
        final base = _extractBaseName(img.name);
        if (base == standardName) {
          return img;
        }
        // Handle albumart variants e.g. albumartsmall, albumart_large
        if (standardName == 'albumart' && base.startsWith('albumart')) {
          return img;
        }
      }
    }

    return null;
  }

  static bool _isValidImage(DriveFileItem item) {
    return AppImageConstants.isImageFile(item.name, item.mimeType);
  }

  static String _extractBaseName(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    final withoutExt = dotIndex != -1
        ? filename.substring(0, dotIndex)
        : filename;
    return withoutExt.trim().toLowerCase();
  }
}
