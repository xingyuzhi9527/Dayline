import '../../core/database/repositories.dart';
import '../../core/markdown/markdown_directory_service.dart';
import 'monthly_expense_markdown_service.dart';

Future<void> syncMonthlyExpenseReportForDate({
  required AppSettingsRepository settingsRepository,
  required ExpensesRepository expensesRepository,
  required DateTime date,
  DateTime? generatedAt,
}) async {
  final dirService = MarkdownDirectoryService(settingsRepository);
  final service = MonthlyExpenseMarkdownService(
    expensesRepository: expensesRepository,
    directoryService: dirService,
  );
  await service.refreshMonthIfConfigured(date, generatedAt: generatedAt);
}
