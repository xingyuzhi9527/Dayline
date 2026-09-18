import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_storage_service.dart';
import 'package:liflow_app/features/projects/project_stored_image.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('tree preview requests a thumbnail and reuses it across rebuilds', (
    tester,
  ) async {
    final storage = _ImageStorage();
    final location = const MarkdownStorageLocation.documentTree(
      treeUri: 'content://images/tree/root',
      relativePath: 'photo.png',
    ).serialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [markdownStorageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Scaffold(
            body: ProjectStoredImage(location: location, thumbnail: true),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(storage.requests, [true]);
    storage.result.complete(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    await tester.pump();
    expect(storage.requests, [true]);
  });

  testWidgets(
    'full image read failure offers a retry without creating a disk copy',
    (tester) async {
      final storage = _ImageStorage();
      final location = const MarkdownStorageLocation.documentTree(
        treeUri: 'content://images/tree/root',
        relativePath: 'photo.png',
      ).serialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [markdownStorageProvider.overrideWithValue(storage)],
          child: MaterialApp(
            home: Scaffold(body: ProjectStoredImage(location: location)),
          ),
        ),
      );
      expect(storage.requests, [false]);
      storage.result.completeError(StateError('Permission revoked'));
      await tester.pump();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      storage.result = Completer<Uint8List>();
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      expect(storage.requests, [false, false]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      storage.result.completeError(StateError('Still unavailable'));
      await tester.pump();
    },
  );
}

class _ImageStorage extends MarkdownStorageService {
  _ImageStorage()
    : super(
        MarkdownDirectoryService(
          AppSettingsRepository(
            LocalDatabase(databaseFactory: databaseFactoryFfi),
          ),
        ),
      );
  Completer<Uint8List> result = Completer<Uint8List>();
  final requests = <bool>[];

  @override
  Future<Uint8List> readImageLocation(
    String location, {
    bool thumbnail = false,
  }) {
    requests.add(thumbnail);
    return result.future;
  }
}
