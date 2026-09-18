import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/search_models.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({required this.item, required this.onTap, super.key});

  final SearchResultItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isProject = item.kind == SearchResultKind.project;
    return Semantics(
      button: true,
      label: '打开${isProject ? '项目' : '记录'} ${item.title}',
      child: InkWell(
        key: ValueKey('search-result-${item.stableId}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primary.withAlpha(18),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      isProject ? Icons.flag_outlined : Icons.notes_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isEmpty ? '无标题记录' : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _secondaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (item.tags.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          item.tags.take(3).map((tag) => '#$tag').join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 24,
                  height: 40,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _secondaryText {
    final source = switch (item.matchReason) {
      SearchMatchReason.content => '正文命中',
      SearchMatchReason.tags => '标签命中',
      SearchMatchReason.projectName => '项目名称命中',
      SearchMatchReason.projectInfo => '关联项目信息命中',
      SearchMatchReason.multipleFields => '多字段命中',
    };
    final detail = item.kind == SearchResultKind.project
        ? item.projectStatus
        : item.date;
    return detail == null || detail.isEmpty ? source : '$source · $detail';
  }
}
