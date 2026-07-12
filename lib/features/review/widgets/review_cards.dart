import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/export_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../review_providers.dart';

String _formatDate(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}

String _formatWeekday(DateTime date) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return weekdays[date.weekday - 1];
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class ReviewDateBar extends ConsumerWidget {
  const ReviewDateBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(reviewDateProvider);
    final notifier = ref.read(reviewDateProvider.notifier);
    final isToday = _isSameDay(date, DateTime.now());
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '前一天',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: notifier.goToPrevDay,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(_formatDate(date), style: theme.textTheme.titleMedium),
                    Text(
                      _formatWeekday(date),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (!isToday)
                      TextButton(
                        onPressed: notifier.goToToday,
                        child: const Text('回到今天'),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '后一天',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: notifier.goToNextDay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewBody extends ConsumerWidget {
  const ReviewBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dailySummaryProvider);

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (summary) {
        if (!summary.hasData) {
          return _EmptyReview(date: ref.watch(reviewDateProvider));
        }

        return ListView(
          key: const ValueKey('review-body-scroll'),
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            _SummaryCard(summary: summary),
            const SizedBox(height: AppSpacing.md),
            _StatsGrid(summary: summary),
            const SizedBox(height: AppSpacing.md),
            _ActivityPulseCard(summary: summary),
            if (summary.topTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _TopTagsCard(tags: summary.topTags),
            ],
            const SizedBox(height: AppSpacing.lg),
            _ExportBar(date: ref.watch(reviewDateProvider)),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.primary, width: 4)),
          borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusLg)),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primary.withAlpha(18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded, color: colors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日复盘', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    summary.summaryText,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatItem(Icons.edit_note_rounded, '记录', '${summary.recordCount}'),
      _StatItem(
        Icons.check_circle_outline,
        '待办',
        summary.totalTodos == 0
            ? '0%'
            : '${((summary.completedTodos / summary.totalTodos) * 100).round()}%',
        helper: '${summary.completedTodos}/${summary.totalTodos} 完成',
      ),
      _StatItem(Icons.timer_rounded, '专注', '${summary.focusMinutes} min'),
      _StatItem(
        Icons.payments_rounded,
        '消费',
        '¥${summary.expenseTotal.toStringAsFixed(2)}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - AppSpacing.sm) / 2;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final stat in stats)
              SizedBox(
                width: tileWidth,
                height: 190,
                child: _StatCard(stat: stat),
              ),
          ],
        );
      },
    );
  }
}

class _StatItem {
  const _StatItem(this.icon, this.label, this.value, {this.helper});

  final IconData icon;
  final String label;
  final String value;
  final String? helper;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final _StatItem stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  stat.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(stat.icon, size: 18, color: colors.onSurfaceVariant),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stat.value, style: theme.textTheme.displaySmall),
                if (stat.helper != null)
                  Text(stat.helper!, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPulseCard extends StatelessWidget {
  const _ActivityPulseCard({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final heights = [
      0.2,
      0.1,
      0.05,
      0.0,
      0.3,
      0.6,
      0.8,
      1.0,
      0.7,
      0.4,
      0.2,
      0.1,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('活跃脉冲', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in heights) ...[
                    Expanded(
                      child: FractionallySizedBox(
                        heightFactor: h,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.primary.withAlpha(
                              (35 + h * 160).round(),
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text('早晨', style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(
                  '活跃时段 ${summary.activeHourRange}',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Text('夜晚', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopTagsCard extends StatelessWidget {
  const _TopTagsCard({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日主题', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: tags
                  .map(
                    (tag) => Chip(
                      avatar: const Icon(Icons.tag, size: 14),
                      label: Text('#$tag'),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: colors.primary.withAlpha(15),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportBar extends ConsumerWidget {
  const _ExportBar({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('导出 Markdown'),
          onPressed: () => _exportMarkdown(context, ref, date),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton.icon(
          icon: const Icon(Icons.code_rounded, size: 18),
          label: const Text('导出 JSON'),
          onPressed: () => _exportJson(context, ref, date),
        ),
      ],
    );
  }

  Future<void> _exportMarkdown(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
  ) async {
    try {
      final path = await exportMarkdownToFile(ref, date);
      if (context.mounted) _showSuccess(context, path);
    } catch (e) {
      if (context.mounted) _showError(context, e.toString());
    }
  }

  Future<void> _exportJson(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
  ) async {
    try {
      final path = await exportJsonToFile(ref, date);
      if (context.mounted) _showSuccess(context, path);
    } catch (e) {
      if (context.mounted) _showError(context, e.toString());
    }
  }

  void _showSuccess(BuildContext context, String path) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已导出到：$path')));
  }

  void _showError(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('导出失败：$error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assessment_rounded,
              size: 64,
              color: colors.onSurfaceVariant.withAlpha(85),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isToday ? '今天还没有数据' : '这一天还没有数据',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('记录几件小事后，这里会生成复盘。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
