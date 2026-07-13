import 'package:path/path.dart' as p;

import '../../core/database/repositories.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/markdown/project_markdown_paths.dart';
import 'monthly_expense_providers.dart';

class MonthlyExpenseMarkdownService {
  MonthlyExpenseMarkdownService({
    required ExpensesRepository expensesRepository,
    required MarkdownDirectoryService directoryService,
  }) : _expensesRepository = expensesRepository,
       _directoryService = directoryService,
       _storage = MarkdownStorageService(directoryService);

  static const ledgerProjectId = 'system-monthly-expenses';
  static const ledgerProjectName = '月消费账本';

  final ExpensesRepository _expensesRepository;
  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storage;

  Future<String> exportMonth(DateTime date, {DateTime? generatedAt}) async {
    final month = DateTime(date.year, date.month);
    final now = generatedAt ?? DateTime.now();
    await _ensureLedgerProject(now);
    final content = await _buildReport(month, generatedAt: now);
    return _writeMonthReport(month, content);
  }

  Future<String> exportSummary(
    MonthlyExpenseSummary summary, {
    DateTime? generatedAt,
  }) async {
    final now = generatedAt ?? DateTime.now();
    await _ensureLedgerProject(now);
    final content = buildReportFromSummary(summary, generatedAt: now);
    return _writeMonthReport(summary.month, content);
  }

  Future<String> locationForMonth(DateTime date) {
    return _storage.locationForRelativePath(_relativeReportPath(date));
  }

  Future<String?> refreshMonthIfConfigured(
    DateTime date, {
    DateTime? generatedAt,
  }) async {
    if (!await _directoryService.isConfigured()) return null;
    return exportMonth(date, generatedAt: generatedAt);
  }

  Future<void> _ensureLedgerProject(DateTime now) async {
    final content =
        '''
---
type: project
source: liflow
project_id: "$ledgerProjectId"
project_name: "$ledgerProjectName"
created_at: ${now.toIso8601String()}
updated_at: ${now.toIso8601String()}
tags: [账本, 消费]
---

# $ledgerProjectName

这里自动收纳 Liflow 生成的月消费账单。
''';
    await _storage.writeRelativeTextFile(
      relativePath: p.posix.join(_ledgerFolder, 'project.md'),
      content: content,
    );
  }

  Future<String> _buildReport(
    DateTime month, {
    required DateTime generatedAt,
  }) async {
    final summary = await _summaryForMonth(month);
    return buildReportFromSummary(summary, generatedAt: generatedAt);
  }

  Future<MonthlyExpenseSummary> _summaryForMonth(DateTime month) async {
    final monthKey = monthlyExpenseMonthKey(month);
    final expenses = await _expensesRepository.findByMonth(month);
    final categoryTotals = await _expensesRepository
        .sumAmountByCategoryForMonth(month);
    final dailyTotals = await _expensesRepository.sumAmountByDayForMonth(month);
    final total = await _expensesRepository.sumAmountByMonth(month);
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final dailyAverage = dayCount == 0 ? 0.0 : total / dayCount;
    final highestDay = _highestDay(dailyTotals);

    return MonthlyExpenseSummary(
      month: month,
      monthKey: monthKey,
      total: total,
      count: expenses.length,
      dailyAverage: dailyAverage,
      categoryTotals: categoryTotals.entries
          .map(
            (entry) =>
                MonthlyExpenseBucket(label: entry.key, amount: entry.value),
          )
          .toList(),
      dailyTotals: dailyTotals.entries
          .map(
            (entry) =>
                MonthlyExpenseDayTotal(date: entry.key, amount: entry.value),
          )
          .toList(),
      highestDay: highestDay == null
          ? null
          : MonthlyExpenseDayTotal(
              date: highestDay.key,
              amount: highestDay.value,
            ),
      expenses: expenses,
    );
  }

  String buildReportFromSummary(
    MonthlyExpenseSummary summary, {
    required DateTime generatedAt,
  }) {
    final monthKey = summary.monthKey;
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('type: monthly_expense_report');
    buf.writeln('source: liflow');
    buf.writeln('month: $monthKey');
    buf.writeln('generated_at: ${generatedAt.toIso8601String()}');
    buf.writeln('total: ${summary.total.toStringAsFixed(2)}');
    buf.writeln('count: ${summary.count}');
    buf.writeln('currency: CNY');
    buf.writeln('---');
    buf.writeln();
    buf.writeln('# $monthKey 月消费账单');
    buf.writeln();
    buf.writeln('## 概览');
    buf.writeln();
    buf.writeln('- 总消费：¥${summary.total.toStringAsFixed(2)}');
    buf.writeln('- 消费次数：${summary.count}');
    buf.writeln('- 日均消费：¥${summary.dailyAverage.toStringAsFixed(2)}');
    final highestDay = summary.highestDay;
    if (highestDay != null) {
      buf.writeln(
        '- 最高消费日：${highestDay.date.substring(5)}，¥${highestDay.amount.toStringAsFixed(2)}',
      );
    }
    buf.writeln();

    if (summary.categoryTotals.isNotEmpty) {
      buf.writeln('## 分类');
      buf.writeln();
      for (final entry in summary.categoryTotals) {
        buf.writeln('- ${entry.label}：¥${entry.amount.toStringAsFixed(2)}');
      }
      buf.writeln();
    }

    buf.writeln('## 每日明细');
    buf.writeln();
    if (summary.expenses.isEmpty) {
      buf.writeln('这个月还没有消费记录。');
      buf.writeln();
      return buf.toString();
    }

    String? currentDate;
    for (final expense in summary.expenses) {
      final date = expense['date'] as String;
      if (currentDate != date) {
        currentDate = date;
        buf.writeln('### ${date.substring(5)}');
        buf.writeln();
      }
      buf.writeln('- ${_expenseLine(expense)}');
    }
    buf.writeln();

    return buf.toString();
  }

  Future<String> _writeMonthReport(DateTime date, String content) {
    return _storage.writeRelativeTextFile(
      relativePath: _relativeReportPath(date),
      content: content,
    );
  }

  String _relativeReportPath(DateTime date) {
    final monthKey = monthlyExpenseMonthKey(date);
    return p.posix.join(_ledgerFolder, 'months', '$monthKey.md');
  }

  MapEntry<String, double>? _highestDay(Map<String, double> dailyTotals) {
    if (dailyTotals.isEmpty) return null;
    return dailyTotals.entries.reduce((a, b) {
      if (a.value == b.value) return a.key.compareTo(b.key) <= 0 ? a : b;
      return a.value > b.value ? a : b;
    });
  }

  String _expenseLine(DatabaseRow expense) {
    final createdAt = expense['created_at'] as int?;
    final time = createdAt == null
        ? '--:--'
        : _timeLabel(DateTime.fromMillisecondsSinceEpoch(createdAt));
    final category = _oneLine(expense['category']);
    final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
    final note = _oneLine(expense['note']);
    final noteText = note.isEmpty ? '' : '，$note';
    return '$time $category：¥${amount.toStringAsFixed(2)}$noteText';
  }

  String _timeLabel(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _oneLine(Object? value) {
    return (value?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String get _ledgerFolder => ProjectMarkdownPaths.projectFolder(
    projectId: ledgerProjectId,
    projectName: ledgerProjectName,
  );
}

class MonthlyExpenseAutoExporter {
  MonthlyExpenseAutoExporter({
    required ExpensesRepository expensesRepository,
    required AppSettingsRepository settingsRepository,
    required MarkdownDirectoryService directoryService,
  }) : _settingsRepository = settingsRepository,
       _directoryService = directoryService,
       _markdownService = MonthlyExpenseMarkdownService(
         expensesRepository: expensesRepository,
         directoryService: directoryService,
       );

  static const lastGeneratedMonthKey =
      'monthly_expense_report.last_generated_month';

  final AppSettingsRepository _settingsRepository;
  final MarkdownDirectoryService _directoryService;
  final MonthlyExpenseMarkdownService _markdownService;

  Future<String?> ensurePreviousMonthReport({DateTime? now}) async {
    if (!await _directoryService.isConfigured()) return null;

    final anchor = now ?? DateTime.now();
    final previousMonth = DateTime(anchor.year, anchor.month - 1);
    final monthKey = monthlyExpenseMonthKey(previousMonth);
    final existing = await _settingsRepository.findByKey(lastGeneratedMonthKey);
    if (existing?['value'] == monthKey) return null;

    final location = await _markdownService.exportMonth(
      previousMonth,
      generatedAt: anchor,
    );
    await _upsertSetting(lastGeneratedMonthKey, monthKey, updatedAt: anchor);
    return location;
  }

  Future<void> _upsertSetting(
    String key,
    String value, {
    required DateTime updatedAt,
  }) async {
    final existing = await _settingsRepository.findByKey(key);
    if (existing == null) {
      await _settingsRepository.create(
        key: key,
        value: value,
        updatedAt: updatedAt,
      );
    } else {
      await _settingsRepository.update(key, value, updatedAt: updatedAt);
    }
  }
}
