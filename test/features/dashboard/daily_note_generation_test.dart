import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_note_service.dart';
import 'package:liflow_app/features/dashboard/widgets/dashboard_expanded.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final failWrite in [false, true]) {
    testWidgets(
      'generation responds before reading and ${failWrite ? 'allows retry after failure' : 'updates only the generated day'}',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = LocalDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: inMemoryDatabasePath,
        );
        final settings = _ConfiguredSettings(database);
        final noteService = _DelayedNoteService(
          MarkdownDirectoryService(settings),
        );
        final container = ProviderContainer(
          overrides: [
            localDatabaseProvider.overrideWithValue(database),
            appSettingsRepositoryProvider.overrideWithValue(settings),
            dashboardRepositoryProvider.overrideWithValue(
              _EmptyDashboard(database),
            ),
            trackersRepositoryProvider.overrideWithValue(
              _EmptyTrackers(database),
            ),
            markdownNoteServiceProvider.overrideWithValue(noteService),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await database.close();
        });
        final today = DateTime(2026, 9, 18);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: DailyNoteGenerationSection(
                  selectedDate: today,
                  today: today,
                  availableDates: List.generate(
                    3,
                    (i) => today.subtract(Duration(days: i)),
                  ),
                  onDateChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.widgetWithText(FilledButton, '生成最终稿');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(noteService.reads, hasLength(3));
        noteService.readGate = Completer<void>();
        await tester.tap(button);
        await tester.pump();
        expect(
          find.descendant(
            of: button,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();
        expect(noteService.reads, hasLength(4));
        noteService.readGate!.complete();
        await tester.pump();
        expect(noteService.writeStarted.isCompleted, isTrue);
        if (failWrite) {
          noteService.writeGate.completeError(StateError('Write failed'));
        } else {
          noteService.writeGate.complete('daily/today.md');
        }
        await tester.pumpAndSettle();
        expect(noteService.reads, hasLength(4));
        expect(noteService.writes, 1);
        expect(
          find.widgetWithText(FilledButton, failWrite ? '生成最终稿' : '修改笔记'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(noteService.content, contains('status: final'));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _ConfiguredSettings extends AppSettingsRepository {
  _ConfiguredSettings(super.database);
  @override
  Future<DatabaseRow?> findByKey(String key) async =>
      key == 'markdown_root_configured' ? {'value': 'true'} : null;
}

class _EmptyDashboard extends DashboardRepository {
  _EmptyDashboard(super.database);
  @override
  Future<DashboardDayBundle> loadDayBundle(DateTime date) async =>
      const DashboardDayBundle(
        activityRows: [],
        monthExpenseTotal: 0,
        review: null,
      );
}

class _EmptyTrackers extends TrackersRepository {
  _EmptyTrackers(super.database);
  @override
  Future<List<DatabaseRow>> findAll({String? orderBy}) async => [];
}

class _DelayedNoteService extends MarkdownNoteService {
  _DelayedNoteService(super.directoryService);
  final reads = <DateTime>[];
  Completer<void>? readGate;
  final writeStarted = Completer<void>();
  final writeGate = Completer<String>();
  int writes = 0;
  String? content;

  @override
  Future<({String location, String content})?> readDailyNoteIfExists(
    DateTime date,
  ) async {
    reads.add(date);
    await readGate?.future;
    return (
      location: 'daily/${dateKey(date)}.md',
      content: '---\nstatus: draft\n---\n# Draft',
    );
  }

  @override
  Future<String> saveDailyNote(DateTime date, String markdownContent) {
    writes++;
    content = markdownContent;
    writeStarted.complete();
    return writeGate.future;
  }
}
