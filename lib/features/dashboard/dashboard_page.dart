import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'dashboard_providers.dart';
import 'widgets/dashboard_expanded.dart';
import 'widgets/review_orb.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(dataVersionProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          summaryAsync.when(
            data: (summary) => _expanded
                ? DashboardExpandedView(
                    summary: summary,
                    onCollapse: () => setState(() => _expanded = false),
                  )
                : _CollapsedView(
                    summary: summary,
                    onExpand: () => setState(() => _expanded = true),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('加载失败：$e', style: TextStyle(color: AppColors.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedView extends StatelessWidget {
  const _CollapsedView({required this.summary, required this.onExpand});

  final DashboardSummary summary;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isEvening = now.hour >= 18;

    String statusText;
    if (!summary.hasData) {
      statusText = '今天还没有碎片';
    } else {
      statusText = '今天 ${summary.recordCount} 条碎片';
    }

    return Align(
      alignment: const Alignment(0, -0.01),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.containerMargin,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReviewOrb(
              recordCount: summary.recordCount,
              hasUnfinishedTodos: summary.hasUnfinishedTodos,
              isEvening: isEvening,
              isReviewed: summary.isReviewed,
              onTap: onExpand,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ReviewRhythmDots(timestamps: summary.allTimestamps),
            const SizedBox(height: AppSpacing.md),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.ink,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _OpenReviewPill(onTap: onExpand),
            if (summary.isReviewed)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.tracker.withAlpha(180),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRhythmDots extends StatelessWidget {
  const _ReviewRhythmDots({required this.timestamps});

  final List<int> timestamps;

  static const int _dotCount = 21;

  @override
  Widget build(BuildContext context) {
    final activeBuckets = <int>{};
    for (final timestamp in timestamps) {
      final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final minutes = time.hour * 60 + time.minute;
      final bucket = (minutes / (24 * 60) * _dotCount).floor();
      activeBuckets.add(bucket.clamp(0, _dotCount - 1));
    }

    return SizedBox(
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _dotCount; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: activeBuckets.contains(i) ? 6 : 3,
              height: activeBuckets.contains(i) ? 28 : 18,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color:
                    (activeBuckets.contains(i)
                            ? AppColors.primary
                            : AppColors.muted)
                        .withAlpha(activeBuckets.contains(i) ? 150 : 80),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpenReviewPill extends StatelessWidget {
  const _OpenReviewPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '打开复盘',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('dashboard-open-review-pill'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            width: 120,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border.withAlpha(180)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withAlpha(12),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.visibility_rounded,
                size: 26,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
