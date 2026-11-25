import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/app/router/app_router.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/google_drive/domain/entities/drive_item.dart';
import 'package:musii/features/google_drive/presentation/pages/drive_folder_picker_page.dart';
import 'package:musii/features/library/domain/entities/sync_progress.dart';

class MockGoogleDriveRepository implements GoogleDriveRepository {
  List<DriveFolderItem> foldersToReturn = [];

  @override
  Future<Result<List<DriveFolderItem>, AppFailure>> listFolders({
    String? parentFolderId,
  }) async {
    return Result.success(foldersToReturn);
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
    return const Result.success([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMusicLibraryRepository implements MusicLibraryRepository {
  String? lastRootFolderId;
  String? lastRootFolderName;

  @override
  Future<Result<void, AppFailure>> syncLibrary({
    required String rootFolderId,
    required String rootFolderName,
    void Function(SyncProgress progress)? onProgress,
    bool isResume = false,
    bool forceSync = false,
    String? requestedSyncRunId,
  }) async {
    lastRootFolderId = rootFolderId;
    lastRootFolderName = rootFolderName;
    return const Result.success(null);
  }

  @override
  Stream<SyncProgress> watchSyncProgress() =>
      Stream.value(const SyncProgress());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DriveFolderPickerPage Widget Tests', () {
    testWidgets('renders Select Here at root and allows selecting My Drive', (
      tester,
    ) async {
      final mockDrive = MockGoogleDriveRepository();
      mockDrive.foldersToReturn = [
        const DriveFolderItem(id: 'f_music', name: 'Music'),
      ];
      final fakeLib = FakeMusicLibraryRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            googleDriveRepositoryProvider.overrideWithValue(mockDrive),
            musicLibraryRepositoryProvider.overrideWithValue(fakeLib),
          ],
          child: CupertinoApp(
            navigatorKey: rootNavigatorKey,
            home: const DriveFolderPickerPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('My Drive'), findsOneWidget);
      expect(find.text('Select Here'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);

      // Tap Select Here to select root
      await tester.tap(find.text('Select Here'));
      await tester.pumpAndSettle();

      expect(find.text('Select "My Drive"?'), findsOneWidget);
      expect(find.text('Confirm & Sync'), findsOneWidget);

      // Tap Confirm & Sync
      await tester.tap(find.text('Confirm & Sync'));
      await tester.pumpAndSettle();

      expect(fakeLib.lastRootFolderId, equals('root'));
      expect(fakeLib.lastRootFolderName, equals('My Drive'));
    });

    testWidgets(
      'empty state Select This Folder selects root when initialParentId is null',
      (tester) async {
        final mockDrive = MockGoogleDriveRepository();
        mockDrive.foldersToReturn = []; // Empty Drive
        final fakeLib = FakeMusicLibraryRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              googleDriveRepositoryProvider.overrideWithValue(mockDrive),
              musicLibraryRepositoryProvider.overrideWithValue(fakeLib),
            ],
            child: CupertinoApp(
              navigatorKey: rootNavigatorKey,
              home: const DriveFolderPickerPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('No subfolders found'), findsOneWidget);
        expect(find.text('Select This Folder'), findsOneWidget);

        // Tap Select This Folder
        await tester.tap(find.text('Select This Folder'));
        await tester.pumpAndSettle();

        expect(find.text('Select "My Drive"?'), findsOneWidget);

        await tester.tap(find.text('Confirm & Sync'));
        await tester.pumpAndSettle();

        expect(fakeLib.lastRootFolderId, equals('root'));
        expect(fakeLib.lastRootFolderName, equals('My Drive'));
      },
    );

    testWidgets('selecting a folder in the list triggers sync with folder id', (
      tester,
    ) async {
      final mockDrive = MockGoogleDriveRepository();
      mockDrive.foldersToReturn = [
        const DriveFolderItem(id: 'folder_citypop', name: 'City Pop'),
      ];
      final fakeLib = FakeMusicLibraryRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            googleDriveRepositoryProvider.overrideWithValue(mockDrive),
            musicLibraryRepositoryProvider.overrideWithValue(fakeLib),
          ],
          child: CupertinoApp(
            navigatorKey: rootNavigatorKey,
            home: const DriveFolderPickerPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('City Pop'), findsOneWidget);

      // Tap Select button on the row
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.text('Select "City Pop"?'), findsOneWidget);

      await tester.tap(find.text('Confirm & Sync'));
      await tester.pumpAndSettle();

      expect(fakeLib.lastRootFolderId, equals('folder_citypop'));
      expect(fakeLib.lastRootFolderName, equals('City Pop'));
    });
  });
}
