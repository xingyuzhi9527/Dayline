import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../timeline_providers.dart';

class RecycleBinBar extends ConsumerStatefulWidget {
  const RecycleBinBar({super.key});

  @override
  ConsumerState<RecycleBinBar> createState() => _RecycleBinBarState();
}

class _RecycleBinBarState extends ConsumerState<RecycleBinBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final deletedAsync = ref.watch(deletedRecordsProvider);

    return deletedAsync.when(
      data: (deleted) {
        if (deleted.isEmpty) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.muted.withAlpha(20),
                  border: const Border(
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: AppColors.accent.withAlpha(160),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '回收站 (${deleted.length})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.accent.withAlpha(160),
                          ),
                    ),
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow.withAlpha(60),
                  border: const Border(
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  itemCount: deleted.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 28),
                  itemBuilder: (context, index) {
                    final row = deleted[index];
                    final content = row['content'] as String? ?? '';
                    final id = row['id'] as int;

                    return Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: AppColors.accent.withAlpha(100),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            content.length > 30
                                ? '${content.substring(0, 30)}…'
                                : content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.muted,
                                    ),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: '恢复',
                            onPressed: () => _restore(id),
                            icon: Icon(Icons.restore_rounded,
                                color: AppColors.tracker),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: '彻底删除',
                            onPressed: () => _permanentlyDelete(id),
                            icon: Icon(Icons.delete_forever_rounded,
                                color: AppColors.accent.withAlpha(160)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _restore(int id) async {
    await ref.read(recordsRepositoryProvider).restore(id);
    ref.invalidate(deletedRecordsProvider);
    ref.invalidate(timelineEventsProvider);
    ref.read(dataVersionProvider.notifier).increment();
  }

  Future<void> _permanentlyDelete(int id) async {
    await ref.read(recordsRepositoryProvider).permanentDelete(id);
    ref.invalidate(deletedRecordsProvider);
    ref.read(dataVersionProvider.notifier).increment();
  }
}
