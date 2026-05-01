import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../today_providers.dart';

extension _AsyncValueX<T> on AsyncValue<T> {
  T? get valueOrNull => switch (this) {
    AsyncData(value: final v) => v,
    _ => null,
  };
}

String formatDate(DateTime date) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}

class DateHeaderCard extends StatelessWidget {
  const DateHeaderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '早上好，探索者',
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.secondaryContainer.withAlpha(48),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.secondaryContainer),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                '连续记录 4 天',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StatsSummaryCard extends ConsumerWidget {
  const StatsSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordCount = ref.watch(todayRecordCountProvider);
    final todoStats = ref.watch(todayTodoStatsProvider);
    final trackerCount = ref.watch(todayTrackerLogCountProvider);
    final focusMins = ref.watch(todayFocusMinutesProvider);

    final todoValue = todoStats.valueOrNull != null
        ? '${todoStats.valueOrNull!.$2}/${todoStats.valueOrNull!.$1}'
        : '-';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.55,
      children: [
        _MetricTile(
          icon: Icons.check_circle_outline,
          label: '待办进度',
          value: todoValue,
          helper: '已完成',
          color: AppColors.muted,
        ),
        _MetricTile(
          icon: Icons.timer_rounded,
          label: '专注时长',
          value: focusMins.valueOrNull != null
              ? '${focusMins.valueOrNull} 分钟'
              : '-',
          helper: '深度工作',
          color: AppColors.primary,
        ),
        _MetricTile(
          icon: Icons.sentiment_satisfied_alt_rounded,
          label: '当前心情',
          value: trackerCount.valueOrNull?.toString() ?? '-',
          helper: '今日打卡',
          color: AppColors.secondaryContainer,
        ),
        _MetricTile(
          icon: Icons.bolt_rounded,
          label: '能量消耗',
          value: recordCount.valueOrNull?.toString() ?? '-',
          helper: '生活片段',
          color: AppColors.accent,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.headlineMedium),
                Text(helper, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final progress = (now.hour * 60 + now.minute) / (24 * 60);
    final pct = (progress * 100).round();
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            children: [
              Text('日出', style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(
                '今天已过 $pct%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text('日落', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class StatusInsightCard extends StatelessWidget {
  const StatusInsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _TypeDot(color: AppColors.primary),
                          const SizedBox(width: AppSpacing.xs),
                          Text('状态洞察', style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '92%',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: AppColors.primary,
                              fontSize: 40,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '精力充沛',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.nightlight_round, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Text('睡眠记录', style: theme.textTheme.bodyLarge),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '7h 45m',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '基于昨晚充足的睡眠，建议今日开启深度工作模式。',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('开启专注'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeDot extends StatelessWidget {
  const _TypeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class TodayTrackersCard extends ConsumerWidget {
  const TodayTrackersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackers = ref.watch(todayActiveTrackersProvider);
    final loggedIds = ref.watch(todayLoggedTrackerIdsProvider);
    final trackerList = trackers.valueOrNull ?? [];

    return _SectionCard(
      title: '今日打卡',
      icon: Icons.mood_rounded,
      child: trackerList.isEmpty
          ? const _EmptyText('还没有打卡项，写一句“喝水”或“运动”开始记录。')
          : Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: trackerList.map((t) {
                final id = t['id'] as int;
                final name = t['name'] as String;
                final isDone = loggedIds.valueOrNull?.contains(id) ?? false;

                return ActionChip(
                  avatar: Icon(
                    isDone ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: isDone ? const Color(0xFF7CB342) : AppColors.muted,
                  ),
                  label: Text(name),
                  backgroundColor: isDone
                      ? const Color(0xFF7CB342).withAlpha(22)
                      : null,
                  onPressed: () => _logTracker(ref, id),
                );
              }).toList(),
            ),
    );
  }

  Future<void> _logTracker(WidgetRef ref, int trackerId) async {
    final today = DateTime.now();
    await ref
        .read(trackerLogsRepositoryProvider)
        .create(trackerId: trackerId, date: today);
    ref.invalidate(todayLoggedTrackerIdsProvider);
    ref.invalidate(todayTrackerLogCountProvider);
    ref.read(dataVersionProvider.notifier).increment();
  }
}

class TodayTodosCard extends ConsumerWidget {
  const TodayTodosCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todayTodoListProvider);
    final todoList = todos.valueOrNull ?? [];

    return _SectionCard(
      title: '今日待办',
      icon: Icons.check_circle_outline,
      child: todoList.isEmpty
          ? const _EmptyText('今天还没有待办。')
          : Column(
              children: todoList.map((t) {
                return _TodoRow(
                  id: t['id'] as int,
                  title: t['title'] as String,
                  isCompleted: (t['is_completed'] as int) == 1,
                );
              }).toList(),
            ),
    );
  }
}

class _TodoRow extends ConsumerWidget {
  const _TodoRow({
    required this.id,
    required this.title,
    required this.isCompleted,
  });

  final int id;
  final String title;
  final bool isCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isCompleted ? const Color(0xFF4A90D9) : AppColors.muted,
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          decoration: isCompleted ? TextDecoration.lineThrough : null,
          color: isCompleted ? AppColors.muted : null,
        ),
      ),
      dense: true,
      onTap: () => _toggle(ref),
    );
  }

  Future<void> _toggle(WidgetRef ref) async {
    final repo = ref.read(todosRepositoryProvider);
    if (isCompleted) {
      await repo.reopen(id);
    } else {
      await repo.complete(id);
    }
    ref.invalidate(todayTodoListProvider);
    ref.invalidate(todayTodoStatsProvider);
    ref.read(dataVersionProvider.notifier).increment();
  }
}

class RecentTimelineCard extends ConsumerWidget {
  const RecentTimelineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recentRecordsProvider);
    final recordList = records.valueOrNull ?? [];

    return _SectionCard(
      title: '最近记录',
      icon: Icons.timeline_rounded,
      child: recordList.isEmpty
          ? const _EmptyText('还没有记录，写下一句话开始。')
          : Column(
              children: recordList.map((r) {
                final type = r['type'] as String;
                final content = r['content'] as String;
                final date = r['date'] as String;
                final time = r['time'] as String?;

                return _RecentRecordRow(
                  type: type,
                  content: content,
                  trailing: time ?? date,
                );
              }).toList(),
            ),
    );
  }
}

class _RecentRecordRow extends StatelessWidget {
  const _RecentRecordRow({
    required this.type,
    required this.content,
    required this.trailing,
  });

  final String type;
  final String content;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(type);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconForType(type), size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              content,
              style: theme.textTheme.bodyLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(trailing, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

IconData _iconForType(String type) => switch (type) {
  'memo' => Icons.edit_note_rounded,
  'todo' => Icons.check_circle_outline,
  'tracker' => Icons.mood_rounded,
  'focus' => Icons.timer_rounded,
  'expense' => Icons.payments_rounded,
  'body' => Icons.monitor_weight_rounded,
  'sleep' => Icons.bedtime_rounded,
  _ => Icons.edit_note_rounded,
};

Color _colorForType(String type) => switch (type) {
  'memo' => AppColors.primary,
  'todo' => const Color(0xFF4A90D9),
  'tracker' => const Color(0xFF7CB342),
  'focus' => const Color(0xFFE67E22),
  'expense' => const Color(0xFFE74C3C),
  'body' => const Color(0xFF9B59B6),
  'sleep' => const Color(0xFF5C6BC0),
  _ => AppColors.muted,
};
