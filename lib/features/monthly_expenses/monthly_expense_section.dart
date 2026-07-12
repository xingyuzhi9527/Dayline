import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../long_note/long_note_reader_page.dart';
import '../markdown_setup/markdown_directory_dialog.dart';
import 'monthly_expense_markdown_service.dart';
import 'monthly_expense_providers.dart';

class MonthlyExpenseSection extends ConsumerStatefulWidget {
  const MonthlyExpenseSection({super.key, this.initialMonth});

  final DateTime? initialMonth;

  @override
  ConsumerState<MonthlyExpenseSection> createState() =>
      _MonthlyExpenseSectionState();
}

class _MonthlyExpenseSectionState extends ConsumerState<MonthlyExpenseSection> {
  late DateTime _selectedMonth;
  var _openingReport = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _selectedMonth = DateTime(initial.year, initial.month);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summaryAsync = ref.watch(
      monthlyExpenseSummaryProvider(_selectedMonth),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthlyExpenseHeader(
              month: _selectedMonth,
              onPrevious: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
            ),
            const SizedBox(height: AppSpacing.sm),
            summaryAsync.when(
              data: (summary) => _MonthlyExpenseContent(
                summary: summary,
                isOpeningReport: _openingReport,
                onOpenReport: () => _openMonthReport(summary),
              ),
              loading: () => const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                '月账单加载失败：$error',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  Future<void> _openMonthReport(MonthlyExpenseSummary summary) async {
    if (_openingReport) return;

    final settings = ref.read(appSettingsRepositoryProvider);
    final dirService = MarkdownDirectoryService(settings);
    if (!await dirService.isConfigured()) {
      if (!mounted) return;
      final configured = await showMarkdownDirectoryDialog(context, dirService);
      if (!configured || !mounted) return;
    }

    setState(() => _openingReport = true);
    try {
      final service = MonthlyExpenseMarkdownService(
        expensesRepository: ref.read(expensesRepositoryProvider),
        directoryService: dirService,
      );
      final location = await service.exportMonth(summary.month);
      final storage = MarkdownStorageService(dirService);
      final raw = await storage.readTextFileLocation(location);
      final document = parseMarkdownDocument(
        raw,
        fallbackTitle: '${summary.monthKey} 月消费账单',
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => LongNoteReaderPage(
            title: document.title.isEmpty
                ? '${summary.monthKey} 月消费账单'
                : document.title,
            filePath: location,
            body: document.body.isEmpty ? raw : document.body,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('打开月账单失败：$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _openingReport = false);
      }
    }
  }
}

class _MonthlyExpenseHeader extends StatelessWidget {
  const _MonthlyExpenseHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Text(
          '月账单',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          monthlyExpenseMonthKey(month),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: '上个月',
          color: colors.onSurfaceVariant,
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: '下个月',
          color: colors.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _MonthlyExpenseContent extends StatelessWidget {
  const _MonthlyExpenseContent({
    required this.summary,
    required this.isOpeningReport,
    required this.onOpenReport,
  });

  final MonthlyExpenseSummary summary;
  final bool isOpeningReport;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (!summary.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              '这个月还没有消费记录。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          _MonthlyExpenseReportButton(
            isLoading: isOpeningReport,
            onPressed: onOpenReport,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _BillMetric(
              label: '总额',
              value: _money(summary.total),
              icon: Icons.payments_rounded,
            ),
            const SizedBox(width: AppSpacing.xs),
            _BillMetric(
              label: '笔数',
              value: '${summary.count}',
              icon: Icons.receipt_long_rounded,
            ),
            const SizedBox(width: AppSpacing.xs),
            _BillMetric(
              label: '日均',
              value: _money(summary.dailyAverage),
              icon: Icons.calendar_view_month_rounded,
            ),
          ],
        ),
        if (summary.highestDay != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.trending_up_rounded, size: 16, color: AppColors.body),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '最高消费日 ${summary.highestDay!.date.substring(5)}，${_money(summary.highestDay!.amount)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          '详细消费记录已归档到月消费 Markdown。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _MonthlyExpenseReportButton(
          isLoading: isOpeningReport,
          onPressed: onOpenReport,
        ),
      ],
    );
  }
}

class _BillMetric extends StatelessWidget {
  const _BillMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withAlpha(120),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.expense),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.primary,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyExpenseReportButton extends StatelessWidget {
  const _MonthlyExpenseReportButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.description_outlined),
        label: Text(isLoading ? '生成中…' : '查看月账单 MD'),
      ),
    );
  }
}

String _money(double value) => '¥${value.toStringAsFixed(1)}';
