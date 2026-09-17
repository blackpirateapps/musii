import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/google_drive/domain/entities/drive_item.dart';
import 'package:musii/features/metadata/domain/services/folder_artwork_resolver.dart';

void main() {
  group('FolderArtworkResolver', () {
    test('resolves standard cover image with case-insensitivity', () {
      final items = [
        const DriveFileItem(
          id: '1',
          name: 'COVER.PNG',
          mimeType: 'image/png',
          size: 1000,
          parentFolderId: 'f1',
          isImage: true,
        ),
      ];
      final map = {'f1': items};

      final candidate = FolderArtworkResolver.resolveCandidate(
        folderId: 'f1',
        folderImages: map,
      );

      expect(candidate, isNotNull);
      expect(candidate!.id, equals('1'));
      expect(candidate.name, equals('COVER.PNG'));
    });

    test('respects standard naming priority (cover > folder > front)', () {
      final items = [
        const DriveFileItem(
          id: 'front',
          name: 'front.jpg',
          mimeType: 'image/jpeg',
          size: 1000,
          parentFolderId: 'f1',
          isImage: true,
        ),
        const DriveFileItem(
          id: 'folder',
          name: 'folder.png',
          mimeType: 'image/png',
          size: 1000,
          parentFolderId: 'f1',
          isImage: true,
        ),
        const DriveFileItem(
          id: 'cover',
          name: 'cover.jpg',
          mimeType: 'image/jpeg',
          size: 1000,
          parentFolderId: 'f1',
          isImage: true,
        ),
      ];
      final map = {'f1': items};

      final candidate = FolderArtworkResolver.resolveCandidate(
        folderId: 'f1',
        folderImages: map,
      );

      expect(candidate, isNotNull);
      expect(candidate!.id, equals('cover'));
    });

    test('falls back to parent folder for multi-disc layouts', () {
      final cd1Items = [
        const DriveFileItem(
          id: 'random_photo',
          name: 'band_live.jpg',
          mimeType: 'image/jpeg',
          size: 1000,
          parentFolderId: 'f_cd1',
          isImage: true,
        ),
      ];
      final albumItems = [
        const DriveFileItem(
          id: 'album_cover',
          name: 'Cover.jpg',
          mimeType: 'image/jpeg',
          size: 1000,
          parentFolderId: 'f_album',
          isImage: true,
        ),
      ];
      final map = {'f_cd1': cd1Items, 'f_album': albumItems};
      final parentMap = {'f_cd1': 'f_album'};

      // Standard name in parent should win over arbitrary non-standard image in immediate folder
      final candidate = FolderArtworkResolver.resolveCandidate(
        folderId: 'f_cd1',
        folderImages: map,
        folderParentMap: parentMap,
      );

      expect(candidate, isNotNull);
      expect(candidate!.id, equals('album_cover'));
    });

    test(
      'falls back to any valid image in folder if no standard name found',
      () {
        final items = [
          const DriveFileItem(
            id: 'scan1',
            name: 'album_scan_art.webp',
            mimeType: 'image/webp',
            size: 1000,
            parentFolderId: 'f1',
            isImage: true,
          ),
        ];
        final map = {'f1': items};

        final candidate = FolderArtworkResolver.resolveCandidate(
          folderId: 'f1',
          folderImages: map,
        );

        expect(candidate, isNotNull);
        expect(candidate!.id, equals('scan1'));
      },
    );

    test('ignores non-image files', () {
      final items = [
        const DriveFileItem(
          id: 'doc',
          name: 'cover.txt',
          mimeType: 'text/plain',
          size: 100,
          parentFolderId: 'f1',
        ),
        const DriveFileItem(
          id: 'pdf',
          name: 'folder.pdf',
          mimeType: 'application/pdf',
          size: 200,
          parentFolderId: 'f1',
        ),
      ];
      final map = {'f1': items};

      final candidate = FolderArtworkResolver.resolveCandidate(
        folderId: 'f1',
        folderImages: map,
      );

      expect(candidate, isNull);
    });

    test('returns null for null or empty folder', () {
      expect(
        FolderArtworkResolver.resolveCandidate(
          folderId: null,
          folderImages: {},
        ),
        isNull,
      );
      expect(
        FolderArtworkResolver.resolveCandidate(folderId: '', folderImages: {}),
        isNull,
      );
    });
  });
}
