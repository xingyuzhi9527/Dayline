import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../timeline_providers.dart';

extension _AsyncValueX<T> on AsyncValue<T> {
  T? get valueOrNull => switch (this) {
    AsyncData(value: final v) => v,
    _ => null,
  };
}

String _formatDate(DateTime date) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}

String _formatTime(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class TimelineDateBar extends ConsumerWidget {
  const TimelineDateBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(timelineDateProvider);
    final notifier = ref.read(timelineDateProvider.notifier);
    final isToday = _isSameDay(date, DateTime.now());
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('时间线', style: theme.textTheme.headlineMedium),
              const Spacer(),
              if (!isToday)
                TextButton(
                  onPressed: notifier.goToToday,
                  child: const Text('回到今天'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
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
                        Text(
                          _formatDate(date),
                          style: theme.textTheme.titleMedium,
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final events = ref.watch(timelineEventsProvider);
                            final count = events.valueOrNull?.length;
                            return Text(
                              count == null ? '加载中' : '$count 条记录',
                              style: theme.textTheme.bodySmall,
                            );
                          },
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
        ],
      ),
    );
  }
}

class TimelineBody extends ConsumerWidget {
  const TimelineBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(timelineEventsProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (events) {
        if (events.isEmpty) {
          return _EmptyTimeline(date: ref.watch(timelineDateProvider));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          itemCount: events.length + 1,
          itemBuilder: (context, index) {
            if (index == events.length) {
              return const _TimelineEndMarker();
            }

            return _TimelineTile(
              event: events[index],
              isLast: index == events.length - 1,
            );
          },
        );
      },
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.event, required this.isLast});

  final TimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(event.type);
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Icon(event.icon, size: 20, color: color),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : AppColors.muted.withAlpha(45),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                bottom: AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(event.timestamp),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TypeDot(color: color),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                _labelForType(event.type),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(event.title, style: theme.textTheme.bodyLarge),
                          if (event.description.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              event.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                          if (event.tags.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: event.tags
                                  .map(
                                    (tag) => Text(
                                      '#$tag',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

class _TimelineEndMarker extends StatelessWidget {
  const _TimelineEndMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_rounded,
              size: 64,
              color: AppColors.muted.withAlpha(85),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isToday ? '今天还没有记录' : '这一天还没有记录',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('写下一句话开始整理这一天。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

String _labelForType(String type) => switch (type) {
  'memo' => '备忘',
  'todo' => '待办',
  'tracker' => '打卡',
  'focus' => '专注',
  'expense' => '消费',
  'body' => '身体',
  'sleep' => '睡眠',
  _ => type,
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
