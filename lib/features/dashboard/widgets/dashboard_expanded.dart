import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/repositories.dart';
import '../../../core/database/repository_providers.dart';
import '../../../core/markdown/markdown_directory_service.dart';
import '../../../core/markdown/markdown_document_parser.dart';
import '../../../core/markdown/markdown_note_service.dart';
import '../../../core/markdown/markdown_storage_service.dart';
import '../../markdown_setup/markdown_directory_dialog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../today/widgets/today_cards.dart';
import '../daily_note_draft.dart';
import '../daily_review_writer.dart';
import '../dashboard_providers.dart';

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _relativeDateLabel(DateTime date, DateTime today) {
  if (_sameDate(date, today)) return '今天';
  if (_sameDate(date, today.subtract(const Duration(days: 1)))) return '昨天';
  if (_sameDate(date, today.subtract(const Duration(days: 2)))) return '前天';
  return dateKey(date);
}

class DashboardExpandedView extends StatefulWidget {
  const DashboardExpandedView({
    required this.summary,
    required this.onCollapse,
    required this.onOpenLibrary,
    super.key,
  });

  final DashboardSummary summary;
  final VoidCallback onCollapse;
  final VoidCallback onOpenLibrary;

  @override
  State<DashboardExpandedView> createState() => _DashboardExpandedViewState();
}

class _DashboardExpandedViewState extends State<DashboardExpandedView> {
  late final DateTime _today;
  late final List<DateTime> _availableDates;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now());
    _selectedDate = _today;
    _availableDates = List.generate(
      3,
      (index) => _today.subtract(Duration(days: index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.summary.hasData) {
      return _EmptyExpanded(theme: theme, onBack: widget.onCollapse);
    }

    return SingleChildScrollView(
      key: const PageStorageKey<String>('dashboard-expanded-scroll'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.containerMargin,
        AppSpacing.lg,
        AppSpacing.containerMargin,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExpandedHeader(
            summary: widget.summary,
            onCollapse: widget.onCollapse,
            onOpenLibrary: widget.onOpenLibrary,
          ),
          const SizedBox(height: AppSpacing.md),
          _TodayStatusCard(summary: widget.summary),
          const SizedBox(height: AppSpacing.md),
          _DayRhythmBar(summary: widget.summary),
          const SizedBox(height: AppSpacing.md),
          TodayTrackersCard(),
          const SizedBox(height: AppSpacing.sm),
          TodayTodosCard(),
          const SizedBox(height: AppSpacing.lg),
          _DividerLabel(label: '今天由什么组成'),
          const SizedBox(height: AppSpacing.sm),
          _CompositionCapsules(summary: widget.summary),
          const SizedBox(height: AppSpacing.lg),
          _DividerLabel(label: '今日洞察'),
          const SizedBox(height: AppSpacing.sm),
          _TodayInsights(summary: widget.summary),
          const SizedBox(height: AppSpacing.lg),
          _DividerLabel(label: '晚间复盘'),
          const SizedBox(height: AppSpacing.sm),
          _JournalDateSelector(
            today: _today,
            availableDates: _availableDates,
            selectedDate: _selectedDate,
            onChanged: (date) => setState(() => _selectedDate = date),
          ),
          const SizedBox(height: AppSpacing.sm),
          _EveningReviewInput(date: _selectedDate, today: _today),
          const SizedBox(height: AppSpacing.lg),
          _DividerLabel(label: '日记'),
          const SizedBox(height: AppSpacing.sm),
          _GenerateNoteSection(
            selectedDate: _selectedDate,
            today: _today,
            availableDates: _availableDates,
            onDateChanged: (date) => setState(() => _selectedDate = date),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}

class _ExpandedHeader extends StatelessWidget {
  const _ExpandedHeader({
    required this.summary,
    required this.onCollapse,
    required this.onOpenLibrary,
  });

  final DashboardSummary summary;
  final VoidCallback onCollapse;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          '今日复盘',
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          summary.date,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(width: AppSpacing.sm),
        _CompactStreakBadge(recordCount: summary.recordCount),
        const Spacer(),
        IconButton(
          onPressed: onOpenLibrary,
          icon: const Icon(Icons.folder_special_rounded),
          tooltip: '资料库',
          color: AppColors.muted,
        ),
        IconButton(
          onPressed: onCollapse,
          icon: const Icon(Icons.close_rounded),
          tooltip: '收起',
          color: AppColors.muted,
        ),
      ],
    );
  }
}

class _CompactStreakBadge extends StatelessWidget {
  const _CompactStreakBadge({required this.recordCount});

  final int recordCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer.withAlpha(64),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: 14,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 2),
          Text(
            '$recordCount',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExpanded extends StatelessWidget {
  const _EmptyExpanded({required this.theme, required this.onBack});

  final ThemeData theme;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: AppColors.primary.withAlpha(80),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '今天还没有内容',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '先去「记」里留下第一句话。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onBack, child: const Text('返回')),
          ],
        ),
      ),
    );
  }
}

// ── Section 1: Today Status ──

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日状态',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _buildStatusText(),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _StatTile(
                  icon: Icons.notes_rounded,
                  label: '记录',
                  value: '${summary.recordCount}',
                ),
                const SizedBox(width: AppSpacing.xs),
                _StatTile(
                  icon: Icons.check_circle_outline,
                  label: '待办',
                  value: '${summary.completedTodos}/${summary.totalTodos}',
                ),
                const SizedBox(width: AppSpacing.xs),
                _StatTile(
                  icon: Icons.timer_rounded,
                  label: '专注',
                  value: '${summary.focusMinutes}min',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                _StatTile(
                  icon: Icons.payments_rounded,
                  label: '日消费',
                  value: '¥${summary.expenseTotal.toStringAsFixed(1)}',
                ),
                const SizedBox(width: AppSpacing.xs),
                _StatTile(
                  icon: Icons.calendar_month_rounded,
                  label: '月消费',
                  value: '¥${summary.monthExpenseTotal.toStringAsFixed(1)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatusText() {
    final buf = StringBuffer();
    buf.write('今天留下了 ${summary.recordCount} 条记录');
    if (summary.totalTodos > 0) {
      buf.write('，完成 ${summary.completedTodos}/${summary.totalTodos} 个待办');
    }
    if (summary.focusMinutes > 0) {
      buf.write('，专注 ${summary.focusMinutes} 分钟');
    }
    if (summary.longestGapMinutes >= 120) {
      final h = summary.longestGapMinutes ~/ 60;
      final m = summary.longestGapMinutes % 60;
      final gap = h > 0
          ? '$h小时${m > 0 ? '$m分钟' : ''}'
          : '${summary.longestGapMinutes}分钟';
      buf.write('，最长空白 $gap');
    }
    buf.write('。');
    return buf.toString();
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceLow.withAlpha(120),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.primary.withAlpha(180)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
              ),
            ),
            Text(
              label,
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

// ── Section 2: Day Rhythm Bar ──

class _DayRhythmBar extends StatelessWidget {
  const _DayRhythmBar({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final firstTime = summary.firstActivityTime != null
        ? _fmtMs(summary.firstActivityTime!)
        : '-';
    final lastTime = summary.lastActivityTime != null
        ? _fmtMs(summary.lastActivityTime!)
        : '-';
    final densest = summary.densestHourRange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日节奏',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildBar(summary.allTimestamps),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _RhythmLabel(label: '首条', value: firstTime),
                const SizedBox(width: AppSpacing.xl),
                _RhythmLabel(label: '末条', value: lastTime),
                const SizedBox(width: AppSpacing.xl),
                _RhythmLabel(label: '最密集', value: densest),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(List<int> timestamps) {
    final hourCounts = List.filled(24, 0);
    for (final ts in timestamps) {
      final hour = DateTime.fromMillisecondsSinceEpoch(ts).hour;
      hourCounts[hour]++;
    }
    final maxCount = hourCounts.isEmpty
        ? 1
        : hourCounts.reduce((a, b) => a > b ? a : b).clamp(1, 100);

    return SizedBox(
      height: 24,
      child: Row(
        children: List.generate(24, (hour) {
          final count = hourCounts[hour];
          final intensity = count / maxCount;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: count > 0
                    ? AppColors.primary.withAlpha(
                        (60 + (intensity * 195).round()).clamp(60, 255),
                      )
                    : AppColors.border.withAlpha(100),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  String _fmtMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _RhythmLabel extends StatelessWidget {
  const _RhythmLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}

// ── Section 3: Composition Capsules ──

class _CompositionCapsules extends StatelessWidget {
  const _CompositionCapsules({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final entries = summary.categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text('暂无分类数据', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final entry in entries.take(10))
              Chip(
                label: Text('${entry.key} ${entry.value}'),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                backgroundColor: AppColors.primary.withAlpha(22),
                side: BorderSide.none,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Section 4: Today Insights ──

class _TodayInsights extends StatelessWidget {
  const _TodayInsights({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (summary.insights.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            '多记录几条，就能看到今日洞察。',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final insight in summary.insights)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 16,
                      color: AppColors.body,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        insight,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
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

// ── Section 5: Evening Review Input ──

class _JournalDateSelector extends StatelessWidget {
  const _JournalDateSelector({
    required this.today,
    required this.availableDates,
    required this.selectedDate,
    required this.onChanged,
  });

  final DateTime today;
  final List<DateTime> availableDates;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final date in availableDates)
          ChoiceChip(
            label: Text(_relativeDateLabel(date, today)),
            selected: _sameDate(date, selectedDate),
            onSelected: (_) => onChanged(date),
          ),
      ],
    );
  }
}

class _EveningReviewInput extends ConsumerStatefulWidget {
  const _EveningReviewInput({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  @override
  ConsumerState<_EveningReviewInput> createState() =>
      _EveningReviewInputState();
}

class _EveningReviewInputState extends ConsumerState<_EveningReviewInput> {
  final _keptController = TextEditingController();
  final _adjustController = TextEditingController();
  final _nextActionController = TextEditingController();
  bool _saving = false;
  DateTime? _loadingDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EveningReviewInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDate(oldWidget.date, widget.date)) {
      _keptController.clear();
      _adjustController.clear();
      _nextActionController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _keptController.dispose();
    _adjustController.dispose();
    _nextActionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final date = DateTime(widget.date.year, widget.date.month, widget.date.day);
    _loadingDate = date;
    final review = await ref
        .read(dailyReviewsRepositoryProvider)
        .findByDate(dateKey(date));
    if (!mounted) return;
    if (_loadingDate != date) return;
    if (review != null) {
      _keptController.text = review['kept'] as String? ?? '';
      _adjustController.text = review['adjust'] as String? ?? '';
      _nextActionController.text = review['next_action'] as String? ?? '';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final day = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
      );
      final kept = _keptController.text.trim();
      final adjust = _adjustController.text.trim();
      final nextAction = _nextActionController.text.trim();
      final result = await saveDailyReviewForDate(
        ref,
        date: day,
        kept: kept,
        adjust: adjust,
        nextAction: nextAction,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.syncError != null
                  ? '复盘已保存，但${_relativeDateLabel(day, widget.today)}日记更新失败：${result.syncError}'
                  : result.syncedNote
                  ? '复盘已保存，${_relativeDateLabel(day, widget.today)}日记已更新'
                  : '复盘已保存',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = _relativeDateLabel(widget.date, widget.today);
    final nextActionLabel = _sameDate(widget.date, widget.today)
        ? '明天最小行动是'
        : '下一天最小行动是';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewField(
              controller: _keptController,
              icon: Icons.thumb_up_alt_outlined,
              iconColor: AppColors.tracker,
              question: '$dayLabel值得保留的是',
              hint: '记录$dayLabel做得好的地方…',
            ),
            const SizedBox(height: AppSpacing.md),
            _ReviewField(
              controller: _adjustController,
              icon: Icons.tune_rounded,
              iconColor: AppColors.focus,
              question: '$dayLabel可以调整的是',
              hint: '哪些地方可以改进…',
            ),
            const SizedBox(height: AppSpacing.md),
            _ReviewField(
              controller: _nextActionController,
              icon: Icons.lightbulb_outline_rounded,
              iconColor: AppColors.body,
              question: nextActionLabel,
              hint:
                  '${_sameDate(widget.date, widget.today) ? '明天' : '下一天'}最重要的一件事…',
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_saving ? '保存中…' : '保存复盘'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.question,
    required this.hint,
  });

  final TextEditingController controller;
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
              TextField(
                controller: controller,
                maxLines: 2,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: AppColors.muted.withAlpha(140),
                    fontSize: 12,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(AppSpacing.xs),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section 6: Generate Note ──

class _GenerateNoteSection extends ConsumerStatefulWidget {
  const _GenerateNoteSection({
    required this.selectedDate,
    required this.today,
    required this.availableDates,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final DateTime today;
  final List<DateTime> availableDates;
  final ValueChanged<DateTime> onDateChanged;

  @override
  ConsumerState<_GenerateNoteSection> createState() =>
      _GenerateNoteSectionState();
}

class _GenerateNoteSectionState extends ConsumerState<_GenerateNoteSection> {
  bool _checkingNote = true;
  bool _isGenerating = false;
  Map<String, DailyNoteInfo> _noteInfoByDate = const {};

  @override
  void initState() {
    super.initState();
    _loadDailyNoteState();
  }

  Future<void> _loadDailyNoteState() async {
    final settings = ref.read(appSettingsRepositoryProvider);
    final dirService = MarkdownDirectoryService(settings);
    if (!await dirService.isConfigured()) {
      if (mounted) {
        setState(() {
          _noteInfoByDate = {
            for (final date in widget.availableDates)
              dateKey(date): DailyNoteInfo(
                date: date,
                status: DailyNoteStatus.missing,
              ),
          };
          _checkingNote = false;
        });
      }
      return;
    }

    final entries = await Future.wait(
      widget.availableDates.map((date) async {
        final info = await loadDailyNoteInfo(ref, date);
        return MapEntry(dateKey(date), info);
      }),
    );
    if (!mounted) return;
    setState(() {
      _noteInfoByDate = Map.fromEntries(entries);
      _checkingNote = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedInfo = _infoFor(widget.selectedDate);
    final buttonLabel = _buttonLabel(selectedInfo);
    final pendingDraft = _pendingPastDraft();
    final reviewAsync = ref.watch(
      dashboardReviewForDateProvider(widget.selectedDate),
    );
    final isReviewed = reviewAsync.maybeWhen(
      data: (review) => review != null,
      orElse: () => false,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Stack(
          children: [
            Opacity(
              opacity: _isGenerating ? 0.34 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '日记草稿',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (isReviewed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tracker.withAlpha(20),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                          ),
                          child: Text(
                            '已复盘',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.tracker,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (pendingDraft != null &&
                      !_sameDate(pendingDraft.date, widget.selectedDate)) ...[
                    _NoteHintBanner(
                      icon: Icons.edit_calendar_rounded,
                      text:
                          '${_relativeDateLabel(pendingDraft.date, widget.today)}还有日记草稿未生成最终稿。',
                      actionLabel: '继续补写',
                      onPressed: _isGenerating
                          ? null
                          : () => widget.onDateChanged(pendingDraft.date),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (!_sameDate(widget.selectedDate, widget.today)) ...[
                    _NoteHintBanner(
                      icon: Icons.schedule_rounded,
                      text: '当前内容会保存到 ${dateKey(widget.selectedDate)}，跨天后也不会丢。',
                      actionLabel: '改存今天',
                      onPressed: _isGenerating
                          ? null
                          : () => widget.onDateChanged(widget.today),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    children: [
                      Icon(
                        _statusIcon(selectedInfo.status),
                        size: 16,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _statusText(selectedInfo.status),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 56),
                ],
              ),
            ),
            if (_isGenerating)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(78),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: AbsorbPointer(
                    absorbing: _checkingNote || _isGenerating,
                    child: FilledButton.icon(
                      onPressed: () => _handleNoteAction(context),
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              selectedInfo.exists && !selectedInfo.isDraft
                                  ? Icons.edit_note_rounded
                                  : Icons.description_outlined,
                              size: 18,
                            ),
                      label: Text(buttonLabel),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNoteAction(BuildContext context) async {
    if (_checkingNote || _isGenerating) return;

    final scaffold = ScaffoldMessenger.of(context);
    final settings = ref.read(appSettingsRepositoryProvider);
    final dirService = MarkdownDirectoryService(settings);
    if (!await dirService.isConfigured()) {
      if (!context.mounted) return;
      final configured = await showMarkdownDirectoryDialog(context, dirService);
      if (!configured) return;
      if (!context.mounted) return;
    }

    final noteService = MarkdownNoteService(dirService);
    final date = widget.selectedDate;
    final existingLocation = await noteService.findDailyNote(date);
    if (!context.mounted) return;
    if (existingLocation != null) {
      final storage = MarkdownStorageService(dirService);
      final raw = await storage.readTextFileLocation(existingLocation);
      if (!context.mounted) return;
      if (!isDailyNoteDraftContent(raw)) {
        await _openDailyNoteEditor(context, existingLocation, date);
        await _loadDailyNoteState();
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isGenerating = true);

    try {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(existingLocation == null ? '正在生成日记…' : '正在生成最终稿…'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );

      final path = await _exportDashboardMarkdown(date);
      if (!context.mounted) return;
      setState(() => _isGenerating = false);
      await _loadDailyNoteState();

      final normalizedPath = path.replaceAll('\\', '/');
      final displayPath = normalizedPath.contains('Liflow/')
          ? 'Liflow/${normalizedPath.split('Liflow/').last}'
          : normalizedPath;
      scaffold
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已生成日记：$displayPath'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('生成日记失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openDailyNoteEditor(
    BuildContext context,
    String location,
    DateTime noteDate,
  ) async {
    final settings = ref.read(appSettingsRepositoryProvider);
    final storage = MarkdownStorageService(MarkdownDirectoryService(settings));
    final raw = await storage.readTextFileLocation(location);
    if (!context.mounted) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _DailyNoteEditorPage(
          location: location,
          initialContent: raw,
          noteDate: noteDate,
        ),
      ),
    );
  }

  Future<String> _exportDashboardMarkdown(DateTime date) async {
    final day = _dateOnly(date);
    final summaryAsync = ref.read(dashboardSummaryForDateProvider(day).future);
    final reviewAsync = ref.read(dashboardReviewForDateProvider(day).future);
    final results = await Future.wait([summaryAsync, reviewAsync]);
    final summary = results[0] as DashboardSummary;
    final review = results[1] as Map<String, Object?>?;
    final now = DateTime.now();
    final isToday = _sameDate(day, DateTime(now.year, now.month, now.day));
    final dayLabel = isToday ? '今天' : '这一天';
    final sectionPrefix = isToday ? '今日' : '当日';
    final nextActionTitle = isToday ? '明天最小行动是' : '下一天最小行动是';

    final buf = StringBuffer();

    final tagsYaml = summary.topTags.map((t) => '  - $t').join('\n');
    buf.writeln('---');
    buf.writeln('date: ${summary.date}');
    buf.writeln('title: ${summary.date} 日记');
    buf.writeln('source: liflow');
    buf.writeln('version: 1');
    buf.writeln('status: final');
    buf.writeln('generated_at: ${now.toIso8601String()}');
    buf.writeln('record_count: ${summary.recordCount}');
    buf.writeln('todo_completed: ${summary.completedTodos}');
    buf.writeln('todo_total: ${summary.totalTodos}');
    buf.writeln('focus_minutes: ${summary.focusMinutes}');
    buf.writeln('tags:');
    if (tagsYaml.isEmpty) {
      buf.writeln('  []');
    } else {
      buf.writeln(tagsYaml);
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('# ${summary.date} 日记');
    buf.writeln();
    buf.writeln('## $sectionPrefix概览');
    buf.writeln();
    final statusBuf = StringBuffer();
    statusBuf.write('$dayLabel留下了 ${summary.recordCount} 条记录');
    if (summary.totalTodos > 0) {
      statusBuf.write(
        '，完成 ${summary.completedTodos}/${summary.totalTodos} 个待办',
      );
    }
    if (summary.focusMinutes > 0) {
      statusBuf.write('，专注 ${summary.focusMinutes} 分钟');
    }
    if (summary.longestGapMinutes >= 120) {
      final h = summary.longestGapMinutes ~/ 60;
      final m = summary.longestGapMinutes % 60;
      final gap = h > 0
          ? '$h小时${m > 0 ? '$m分钟' : ''}'
          : '${summary.longestGapMinutes}分钟';
      statusBuf.write('，最长空白 $gap');
    }
    statusBuf.write('。');
    buf.writeln(statusBuf.toString());
    buf.writeln();
    buf.writeln('## $sectionPrefix节奏');
    buf.writeln();
    final firstTime = summary.firstActivityTime != null
        ? _fmtMs(summary.firstActivityTime!)
        : '-';
    final lastTime = summary.lastActivityTime != null
        ? _fmtMs(summary.lastActivityTime!)
        : '-';
    buf.writeln('- 第一条记录：$firstTime');
    buf.writeln('- 最后一条记录：$lastTime');
    buf.writeln('- 最密集时段：${summary.densestHourRange}');
    if (summary.longestGapMinutes > 0) {
      buf.writeln('- 最长空白：${summary.longestGapMinutes} 分钟');
    }
    buf.writeln();

    final entries = summary.categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isNotEmpty) {
      buf.writeln('## ${isToday ? '今天' : '这一天'}由什么组成');
      buf.writeln();
      for (final entry in entries) {
        buf.writeln('- ${entry.key}：${entry.value}');
      }
      buf.writeln();
    }

    if (summary.insights.isNotEmpty) {
      buf.writeln('## $sectionPrefix洞察');
      buf.writeln();
      for (final insight in summary.insights) {
        buf.writeln('- $insight');
      }
      buf.writeln();
    }

    buf.writeln('## 晚间复盘');
    buf.writeln();
    buf.writeln('### $dayLabel值得保留的是');
    buf.writeln();
    buf.writeln(review?['kept'] as String? ?? '...');
    buf.writeln();
    buf.writeln('### $dayLabel可以调整的是');
    buf.writeln();
    buf.writeln(review?['adjust'] as String? ?? '...');
    buf.writeln();
    buf.writeln('### $nextActionTitle');
    buf.writeln();
    buf.writeln(review?['next_action'] as String? ?? '...');
    buf.writeln();

    buf.writeln('## 原始记录索引');
    buf.writeln();
    buf.writeln('本节保留给未来 AI 检索与结构化分析。');

    final mdContent = buf.toString();

    final settings = ref.read(appSettingsRepositoryProvider);
    final dirService = MarkdownDirectoryService(settings);
    final noteService = MarkdownNoteService(dirService);

    return noteService.saveDailyNote(day, mdContent);
  }

  DailyNoteInfo _infoFor(DateTime date) {
    return _noteInfoByDate[dateKey(date)] ??
        DailyNoteInfo(date: date, status: DailyNoteStatus.missing);
  }

  DailyNoteInfo? _pendingPastDraft() {
    for (final date in widget.availableDates.skip(1)) {
      final info = _infoFor(date);
      if (info.isDraft) return info;
    }
    return null;
  }

  String _buttonLabel(DailyNoteInfo info) {
    if (_checkingNote) return '检查中…';
    if (info.isDraft) return '生成最终稿';
    if (info.exists) return '修改笔记';
    return '生成日记';
  }

  String _statusText(DailyNoteStatus status) {
    return switch (status) {
      DailyNoteStatus.missing => '还没有日记',
      DailyNoteStatus.draft => '已有草稿，晚上可生成最终稿',
      DailyNoteStatus.finalNote => '最终稿已生成',
    };
  }

  IconData _statusIcon(DailyNoteStatus status) {
    return switch (status) {
      DailyNoteStatus.missing => Icons.note_add_outlined,
      DailyNoteStatus.draft => Icons.edit_calendar_rounded,
      DailyNoteStatus.finalNote => Icons.check_circle_outline_rounded,
    };
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _fmtMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _NoteHintBanner extends StatelessWidget {
  const _NoteHintBanner({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer.withAlpha(70),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.secondary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _DailyNoteEditorPage extends ConsumerStatefulWidget {
  const _DailyNoteEditorPage({
    required this.location,
    required this.initialContent,
    required this.noteDate,
  });

  final String location;
  final String initialContent;
  final DateTime noteDate;

  @override
  ConsumerState<_DailyNoteEditorPage> createState() =>
      _DailyNoteEditorPageState();
}

class _DailyNoteEditorPageState extends ConsumerState<_DailyNoteEditorPage> {
  late final TextEditingController _controller;
  late String _location;
  late DateTime _noteDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _location = widget.location;
    _noteDate = DateTime(
      widget.noteDate.year,
      widget.noteDate.month,
      widget.noteDate.day,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final storage = MarkdownStorageService(
        MarkdownDirectoryService(settings),
      );
      await storage.writeTextFileLocation(_location, _controller.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('笔记已保存'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _saveAsToday() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final settings = ref.read(appSettingsRepositoryProvider);
      final noteService = MarkdownNoteService(
        MarkdownDirectoryService(settings),
      );
      final updatedContent = _retargetDailyNoteContent(_controller.text, day);
      final location = await noteService.saveDailyNote(day, updatedContent);
      if (!mounted) return;
      setState(() {
        _location = location;
        _noteDate = day;
        _controller.text = updatedContent;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('已改存到今天'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('改存失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _retargetDailyNoteContent(String raw, DateTime date) {
    final day = dateKey(date);
    var updated = raw.replaceFirst(
      RegExp(r'^date:\s*.*$', multiLine: true),
      'date: $day',
    );
    updated = updated.replaceFirst(
      RegExp(r'^title:\s*.*日记.*$', multiLine: true),
      'title: $day 日记',
    );
    updated = updated.replaceFirst(
      RegExp(r'^#\s+.*日记.*$', multiLine: true),
      '# $day 日记',
    );
    return updated;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseMarkdownDocument(
      _controller.text,
      fallbackTitle: '今日日记',
    );
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final isPastNote = _noteDate.isBefore(todayOnly);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          parsed.title.isEmpty ? '修改笔记' : parsed.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              if (isPastNote) ...[
                _NoteHintBanner(
                  icon: Icons.schedule_rounded,
                  text: '当前会保存到 ${dateKey(_noteDate)}。',
                  actionLabel: '改存今天',
                  onPressed: _saving ? null : _saveAsToday,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_saving,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Markdown 日记',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
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
        const Expanded(child: Divider()),
      ],
    );
  }
}
