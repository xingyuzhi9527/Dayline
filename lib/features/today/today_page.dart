import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../record/widgets/quick_input_bar.dart';
import 'today_providers.dart';
import 'widgets/today_cards.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild the page header when the calendar day rolls over. Individual
    // cards subscribe to the narrower async providers they actually render.
    ref.watch(todayDateKeyProvider);

    return SafeArea(
      child: ListView(
        key: const ValueKey('today-page'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.lg,
          AppSpacing.containerMargin,
          AppSpacing.xl,
        ),
        children: const [
          DateHeaderCard(),
          SizedBox(height: AppSpacing.md),
          ProgressCard(),
          SizedBox(height: AppSpacing.lg),
          QuickInputBar(mode: QuickInputMode.saveImmediately),
          SizedBox(height: AppSpacing.md),
          StatusInsightCard(),
          SizedBox(height: AppSpacing.md),
          StatsSummaryCard(),
          SizedBox(height: AppSpacing.md),
          TodayTrackersCard(),
          SizedBox(height: AppSpacing.sm),
          TodayTodosCard(),
          SizedBox(height: AppSpacing.sm),
          RecentTimelineCard(),
          SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
