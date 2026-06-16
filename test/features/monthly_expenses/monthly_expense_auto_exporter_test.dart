import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/features/monthly_expenses/monthly_expense_markdown_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late ExpensesRepository expensesRepository;
  late AppSettingsRepository settingsRepository;
  late MarkdownDirectoryService directoryService;
  late Directory rootDir;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    expensesRepository = ExpensesRepository(database);
    settingsRepository = AppSettingsRepository(database);
    directoryService = MarkdownDirectoryService(settingsRepository);
    rootDir = await Directory.systemTemp.createTemp(
      'liflow-monthly-auto-export-',
    );
    await directoryService.setRootPath(rootDir.path);
  });

  tearDown(() async {
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test('auto exporter generates previous month once', () async {
    await expensesRepository.create(
      date: DateTime(2026, 6, 8),
      amount: 88,
      category: '购物',
      createdAt: DateTime(2026, 6, 8, 18),
    );
    final exporter = MonthlyExpenseAutoExporter(
      expensesRepository: expensesRepository,
      settingsRepository: settingsRepository,
      directoryService: directoryService,
    );

    final firstLocation = await exporter.ensurePreviousMonthReport(
      now: DateTime(2026, 7, 2, 8),
    );
    final setting = await settingsRepository.findByKey(
      MonthlyExpenseAutoExporter.lastGeneratedMonthKey,
    );

    expect(firstLocation, isNotNull);
    expect(setting?['value'], '2026-06');

    final report = File(firstLocation!);
    expect(await report.readAsString(), contains('# 2026-06 月消费账单'));
    await report.writeAsString('already generated');

    final secondLocation = await exporter.ensurePreviousMonthReport(
      now: DateTime(2026, 7, 3, 8),
    );

    expect(secondLocation, isNull);
    expect(await report.readAsString(), 'already generated');
  });

  test(
    'auto exporter skips when markdown directory is not configured',
    () async {
      final unconfigured = MonthlyExpenseAutoExporter(
        expensesRepository: expensesRepository,
        settingsRepository: settingsRepository,
        directoryService: MarkdownDirectoryService(settingsRepository),
      );
      await settingsRepository.delete('markdown_root_configured');

      final location = await unconfigured.ensurePreviousMonthReport(
        now: DateTime(2026, 7, 2),
      );

      expect(location, isNull);
      expect(
        await settingsRepository.findByKey(
          MonthlyExpenseAutoExporter.lastGeneratedMonthKey,
        ),
        isNull,
      );
    },
  );
}
