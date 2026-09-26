import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../startup_todo_reminder_providers.dart';

class StartupTodoReminder extends StatelessWidget {
  const StartupTodoReminder({
    required this.snapshot,
    required this.onDismiss,
    required this.onOpen,
    super.key,
  });

  final StartupTodoReminderSnapshot snapshot;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('startup-todo-reminder'),
      color: colors.surface,
      elevation: 8,
      shadowColor: colors.shadow.withAlpha(46),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '还有 ${snapshot.totalCount} 件事待处理',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('startup-todo-reminder-dismiss'),
                  tooltip: '收起提醒',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded),
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            if (snapshot.todayCount > 0 || snapshot.previousCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  [
                    if (snapshot.todayCount > 0) '今天 ${snapshot.todayCount} 件',
                    if (snapshot.previousCount > 0)
                      '之前未完成 ${snapshot.previousCount} 件',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            for (final item in snapshot.items)
              InkWell(
                key: ValueKey('startup-todo-reminder-item-${item.id}'),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: colors.onSurface,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.dateLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('startup-todo-reminder-open'),
                onPressed: onOpen,
                child: const Text('打开待办 →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StartupTodoReminderEntry extends StatelessWidget {
  const StartupTodoReminderEntry({
    required this.count,
    required this.onTap,
    super.key,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('startup-todo-reminder-entry'),
      color: colors.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: const SizedBox(
          height: 48,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Center(child: Text('待办')),
          ),
        ),
      ),
    );
  }
}
