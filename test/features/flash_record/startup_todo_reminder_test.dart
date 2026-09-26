import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/flash_record/flash_record_page.dart';
import 'package:liflow_app/features/flash_record/startup_todo_reminder_providers.dart';
import 'package:liflow_app/features/flash_record/widgets/startup_todo_reminder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('shows readable summaries and exposes 48dp close target', (
    tester,
  ) async {
    final snapshot = StartupTodoReminderSnapshot(
      items: [
        StartupTodoReminderItem(
          id: 1,
          title: '准备一个需要自然换行的长待办标题，保留用户原文',
          date: DateTime(2026, 9, 26),
          createdAt: DateTime(2026, 9, 26, 8),
          priority: 1,
          dueTime: '14:00',
        ),
        StartupTodoReminderItem(
          id: 2,
          title: '第二件待办',
          date: DateTime(2026, 9, 25),
          createdAt: DateTime(2026, 9, 8),
          priority: 0,
        ),
      ],
      todayCount: 1,
      previousCount: 1,
    );
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartupTodoReminder(
            snapshot: snapshot,
            onDismiss: () => dismissed = true,
            onOpen: () {},
          ),
        ),
      ),
    );

    expect(find.text('还有 2 件事待处理'), findsOneWidget);
    expect(find.textContaining('今天 1 件'), findsOneWidget);
    expect(find.textContaining('之前未完成 1 件'), findsOneWidget);
    expect(find.text('打开待办 →'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('startup-todo-reminder-dismiss')))
          .size,
      const Size(48, 48),
    );

    await tester.tap(
      find.byKey(const ValueKey('startup-todo-reminder-dismiss')),
    );
    expect(dismissed, isTrue);
  });

  testWidgets('entry can be tapped after the card is dismissed', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartupTodoReminderEntry(count: 3, onTap: () => opened = true),
        ),
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('startup-todo-reminder-entry')))
          .height,
      48,
    );
    await tester.tap(find.byKey(const ValueKey('startup-todo-reminder-entry')));
    expect(opened, isTrue);
  });

  testWidgets('record page reminder can be dismissed and reopened manually', (
    tester,
  ) async {
    sqfliteFfiInit();
    final now = DateTime.now();
    final snapshot = StartupTodoReminderSnapshot(
      items: [
        StartupTodoReminderItem(
          id: 1,
          title: '需要处理的待办',
          date: now,
          createdAt: now,
          priority: 1,
        ),
      ],
      todayCount: 1,
      previousCount: 0,
    );
    final settings = _FakeSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(settings),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
          startupTodoReminderProvider.overrideWith((ref) async => snapshot),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('startup-todo-reminder')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('startup-todo-reminder-dismiss')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('startup-todo-reminder-entry')),
      findsOneWidget,
    );
    expect(settings.closeCount, 1);

    await tester.tap(find.byKey(const ValueKey('startup-todo-reminder-entry')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('startup-todo-reminder')), findsOneWidget);
  });
}

class _FakeSettings extends AppSettingsRepository {
  _FakeSettings()
    : super(
        LocalDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      );

  int closeCount = 0;

  @override
  Future<DatabaseRow?> findByKey(String key) async => null;

  @override
  Future<void> create({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    closeCount++;
  }

  @override
  Future<int> update(String key, String value, {DateTime? updatedAt}) async {
    closeCount++;
    return 1;
  }
}
