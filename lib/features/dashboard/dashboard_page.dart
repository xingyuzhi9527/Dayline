import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../today/today_providers.dart';
import '../today/widgets/today_cards.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dataVersionProvider);

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('dashboard-page'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.lg,
          AppSpacing.containerMargin,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            DateHeaderCard(),
            SizedBox(height: AppSpacing.md),
            StatsSummaryCard(),
            SizedBox(height: AppSpacing.md),
            TodayTrackersCard(),
            SizedBox(height: AppSpacing.sm),
            TodayTodosCard(),
            SizedBox(height: AppSpacing.lg),
            _DividerLabel(label: '分类统计'),
            SizedBox(height: AppSpacing.sm),
            _CategoryBreakdownCard(),
            SizedBox(height: AppSpacing.lg),
            _DividerLabel(label: '今日关键词'),
            SizedBox(height: AppSpacing.sm),
            _TodayKeywordsCard(),
            SizedBox(height: AppSpacing.lg),
            _DividerLabel(label: '今日总结'),
            SizedBox(height: AppSpacing.sm),
            _TodaySummaryCard(),
            SizedBox(height: AppSpacing.lg),
            _DividerLabel(label: '晚间复盘'),
            SizedBox(height: AppSpacing.sm),
            _EveningReviewCard(),
            SizedBox(height: AppSpacing.lg),
            _ExportSection(),
            SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Divider(),
        ),
      ],
    );
  }
}

class _CategoryBreakdownCard extends ConsumerWidget {
  const _CategoryBreakdownCard();

  static const _categories = [
    ('工作', Icons.work_outline, AppColors.todo),
    ('学习', Icons.school_outlined, AppColors.focus),
    ('运动', Icons.directions_run_rounded, AppColors.tracker),
    ('情绪', Icons.emoji_emotions_outlined, AppColors.body),
    ('生活', Icons.local_cafe_outlined, AppColors.primary),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayData = ref.watch(todayRecordCountProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            for (final (label, icon, color) in _categories)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(label,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    todayData.when(
                      data: (_) {
                        final random = (label.hashCode % 5) + 1;
                        return Text(
                          '$random 条',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.muted),
                        );
                      },
                      loading: () => const Text('…'),
                      error: (_, _) => const Text('--'),
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

class _TodayKeywordsCard extends StatelessWidget {
  const _TodayKeywordsCard();

  static const _mockKeywords = ['跑步', '工作', '学习', '情绪', '生活'];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final kw in _mockKeywords)
              Chip(
                label: Text(kw),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                backgroundColor: AppColors.primary.withAlpha(20),
                side: BorderSide.none,
              ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard();

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
                const Icon(Icons.auto_awesome_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'AI 每日总结',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '今天有不错的运动记录，整体节奏比较积极。'
              '下午的专注时段保持得不错，晚上可以适当放松一下。',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EveningReviewCard extends StatelessWidget {
  const _EveningReviewCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewPrompt(
              icon: Icons.thumb_up_alt_outlined,
              iconColor: AppColors.tracker,
              question: '今天做得不错的是',
              hint: '点击填写…',
            ),
            const SizedBox(height: AppSpacing.md),
            _ReviewPrompt(
              icon: Icons.tune_rounded,
              iconColor: AppColors.focus,
              question: '今天可以调整的是',
              hint: '点击填写…',
            ),
            const SizedBox(height: AppSpacing.md),
            _ReviewPrompt(
              icon: Icons.lightbulb_outline_rounded,
              iconColor: AppColors.body,
              question: '明天想关注的是',
              hint: '点击填写…',
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewPrompt extends StatelessWidget {
  const _ReviewPrompt({
    required this.icon,
    required this.iconColor,
    required this.question,
    required this.hint,
  });

  final IconData icon;
  final Color iconColor;
  final String question;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted.withAlpha(160),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportSection extends StatelessWidget {
  const _ExportSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Icon(Icons.code_rounded, color: AppColors.muted, size: 20),
            Text(
              '导出 Markdown',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Icon(Icons.data_object_rounded, color: AppColors.muted, size: 20),
            Text(
              '导出 JSON',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
