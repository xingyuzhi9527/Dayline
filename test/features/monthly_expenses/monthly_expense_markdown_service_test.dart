import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/project_markdown_paths.dart';
import 'package:liflow_app/features/monthly_expenses/monthly_expense_markdown_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late ExpensesRepository expensesRepository;
  late AppSettingsRepository settingsRepository;
  late Directory rootDir;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    expensesRepository = ExpensesRepository(database);
    settingsRepository = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-monthly-expense-');
    await MarkdownDirectoryService(
      settingsRepository,
    ).setRootPath(rootDir.path);
  });

  tearDown(() async {
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test('exports monthly expense report into ledger project folder', () async {
    final month = DateTime(2026, 6);
    await expensesRepository.create(
      date: DateTime(2026, 6, 1),
      amount: 35,
      category: '餐饮',
      note: '午饭',
      createdAt: DateTime(2026, 6, 1, 12, 10),
    );
    await expensesRepository.create(
      date: DateTime(2026, 6, 2),
      amount: 45,
      category: '交通',
      createdAt: DateTime(2026, 6, 2, 9),
    );

    final service = MonthlyExpenseMarkdownService(
      expensesRepository: expensesRepository,
      directoryService: MarkdownDirectoryService(settingsRepository),
    );

    final location = await service.exportMonth(
      month,
      generatedAt: DateTime(2026, 7, 1, 8),
    );
    final ledgerFolder = ProjectMarkdownPaths.projectFolder(
      projectId: MonthlyExpenseMarkdownService.ledgerProjectId,
      projectName: MonthlyExpenseMarkdownService.ledgerProjectName,
    );
    final reportFile = File(
      p.joinAll([
        rootDir.path,
        ...p.posix.split('$ledgerFolder/months/2026-06.md'),
      ]),
    );
    final projectFile = File(
      p.joinAll([rootDir.path, ...p.posix.split('$ledgerFolder/project.md')]),
    );

    expect(location, reportFile.path);
    expect(await projectFile.exists(), isTrue);
    expect(await reportFile.exists(), isTrue);
    final raw = await reportFile.readAsString();
    expect(raw, contains('type: monthly_expense_report'));
    expect(raw, contains('month: 2026-06'));
    expect(raw, contains('total: 80.00'));
    expect(raw, contains('# 2026-06 月消费账单'));
    expect(raw, contains('- 总消费：¥80.00'));
    expect(raw, contains('- 餐饮：¥35.00'));
    expect(raw, contains('### 06-01'));
    expect(raw, contains('- 12:10 餐饮：¥35.00，午饭'));
  });

  test(
    'refreshMonthIfConfigured rewrites report after expense deletion',
    () async {
      final month = DateTime(2026, 6);
      final firstId = await expensesRepository.create(
        date: DateTime(2026, 6, 1),
        amount: 35,
        category: '餐饮',
        note: '午饭',
        createdAt: DateTime(2026, 6, 1, 12, 10),
      );
      await expensesRepository.create(
        date: DateTime(2026, 6, 2),
        amount: 45,
        category: '交通',
        createdAt: DateTime(2026, 6, 2, 9),
      );

      final service = MonthlyExpenseMarkdownService(
        expensesRepository: expensesRepository,
        directoryService: MarkdownDirectoryService(settingsRepository),
      );

      final location = await service.exportMonth(
        month,
        generatedAt: DateTime(2026, 7, 1, 8),
      );
      await expensesRepository.delete(firstId);

      await service.refreshMonthIfConfigured(
        month,
        generatedAt: DateTime(2026, 7, 1, 9),
      );

      final raw = await File(location).readAsString();
      expect(raw, contains('total: 45.00'));
      expect(raw, contains('- 总消费：¥45.00'));
      expect(raw, contains('- 消费次数：1'));
      expect(raw, isNot(contains('12:10 餐饮：¥35.00，午饭')));
    },
  );
}
