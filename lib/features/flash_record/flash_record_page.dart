import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../timeline/timeline_providers.dart';
import 'flash_record_notifier.dart';
import 'flash_record_state.dart';
import 'widgets/flash_card.dart';
import 'widgets/voice_button.dart';

final todayMemoryEventsProvider = FutureProvider<List<TimelineEvent>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  return loadTimelineEventsForDate(ref, DateTime.now());
});

class FlashRecordPage extends ConsumerStatefulWidget {
  const FlashRecordPage({super.key});

  @override
  ConsumerState<FlashRecordPage> createState() => _FlashRecordPageState();
}

class _FlashRecordPageState extends ConsumerState<FlashRecordPage>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  late final AnimationController _memoryController;
  bool _memoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _memoryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      reverseDuration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _memoryController.dispose();
    super.dispose();
  }

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    ref.read(flashRecordProvider.notifier).saveAsText(text);
  }

  void _openMemoryScatter() {
    FocusScope.of(context).unfocus();
    if (_memoryExpanded) return;
    setState(() => _memoryExpanded = true);
    _memoryController.forward(from: 0);
  }

  void _closeMemoryScatter() {
    if (!_memoryExpanded) return;
    unawaited(
      _memoryController.reverse().then((_) {
        if (mounted) {
          setState(() => _memoryExpanded = false);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flashRecordProvider);
    final memoryEvents = ref.watch(todayMemoryEventsProvider);
    final theme = Theme.of(context);

    // Handle saved state — show snackbar and reset
    ref.listen(flashRecordProvider, (prev, next) {
      if (next.phase == FlashPhase.saved) {
        _textController.clear();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('已保存'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            ref.read(flashRecordProvider.notifier).resetAfterSaved();
          }
        });
      }
    });

    return SafeArea(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Main content
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 1),

                // Voice button area
                if (state.phase == FlashPhase.idle ||
                    state.phase == FlashPhase.listening)
                  Center(child: _buildVoiceArea(state, theme))
                else if (state.phase == FlashPhase.recognized)
                  Center(child: _buildRecognizedArea(state, theme))
                else if (state.phase == FlashPhase.saving)
                  Center(child: _buildSavingArea(theme))
                else
                  Center(child: _buildVoiceArea(state, theme)),

                const Spacer(flex: 2),

                // Bottom text input
                if (!state.isInputActive)
                  const SizedBox.shrink()
                else
                  _buildTextInput(theme),
              ],
            ),

            if (state.isInputActive)
              _buildTodayMemoryEntry(theme, memoryEvents),

            if (_memoryExpanded) _buildMemoryScatterLayer(theme, memoryEvents),

            // Flash card overlay
            if (state.phase == FlashPhase.confirming &&
                state.parsedInput != null)
              _buildCardOverlay(state, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayMemoryEntry(
    ThemeData theme,
    AsyncValue<List<TimelineEvent>> memoryEvents,
  ) {
    final subtitle = memoryEvents.when(
      data: (events) => events.isEmpty ? '今天还没有记录' : '${events.length} 条今天的记录',
      loading: () => '正在读取今天记录',
      error: (_, _) => '今天记录读取失败',
    );

    return Positioned(
      right: AppSpacing.containerMargin,
      bottom: 126,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330, minWidth: 260),
        child: Material(
          key: const ValueKey('today-memory-entry'),
          color: AppColors.surface,
          elevation: 8,
          shadowColor: AppColors.softShadow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            onTap: _openMemoryScatter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(90),
                      ),
                    ),
                    child: const Icon(
                      Icons.favorite_border_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '今日回忆',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted.withAlpha(190),
                    size: 32,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryScatterLayer(
    ThemeData theme,
    AsyncValue<List<TimelineEvent>> memoryEvents,
  ) {
    return Positioned.fill(
      key: const ValueKey('memory-scatter-layer'),
      child: AnimatedBuilder(
        animation: _memoryController,
        builder: (context, child) {
          final fade = Curves.easeOutCubic.transform(_memoryController.value);
          final sheetProgress = Curves.easeOutBack.transform(
            _memoryController.value,
          );

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeMemoryScatter,
                  child: ColoredBox(
                    color: Colors.black.withAlpha((38 * fade).round()),
                  ),
                ),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sheetHeight = (constraints.maxHeight * 0.36)
                        .clamp(260.0, 380.0)
                        .toDouble();

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.containerMargin,
                        0,
                        AppSpacing.containerMargin,
                        AppSpacing.md,
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          height: sheetHeight,
                          width: double.infinity,
                          child: Opacity(
                            opacity: fade.clamp(0.0, 1.0).toDouble(),
                            child: Transform.translate(
                              offset: Offset(0, (1 - sheetProgress) * 44),
                              child: Transform.scale(
                                alignment: Alignment.bottomCenter,
                                scaleY: 0.92 + sheetProgress * 0.08,
                                child: _buildMemoryBottomSheet(
                                  theme,
                                  memoryEvents,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMemoryBottomSheet(
    ThemeData theme,
    AsyncValue<List<TimelineEvent>> memoryEvents,
  ) {
    return GestureDetector(
      onTap: () {},
      child: Material(
        key: const ValueKey('memory-bottom-sheet'),
        color: AppColors.surface.withAlpha(248),
        elevation: 14,
        shadowColor: AppColors.softShadow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.favorite_border_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: memoryEvents.when(
                      data: (events) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '今日回忆',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            events.isEmpty
                                ? '今天还没有记录'
                                : '${events.length} 条真实记录',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      loading: () => Text(
                        '正在读取今日回忆',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      error: (_, _) => Text(
                        '今日回忆',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('memory-scatter-close'),
                    tooltip: '收起今日回忆',
                    onPressed: _closeMemoryScatter,
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: memoryEvents.when(
                  data: (events) {
                    if (events.isEmpty) {
                      return _buildMemoryPanelMessage(
                        theme,
                        icon: Icons.inbox_outlined,
                        title: '今天还没有记录',
                        message: '说一句或输入一条，回忆会从这里长出来。',
                      );
                    }

                    return ListView.separated(
                      key: const ValueKey('memory-scroll-field'),
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      itemCount: events.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        return _buildFoldedMemoryCard(events[index], index);
                      },
                    );
                  },
                  loading: () => _buildMemoryPanelMessage(
                    theme,
                    icon: Icons.hourglass_empty_rounded,
                    title: '正在读取',
                    message: '今天的记录马上就来。',
                  ),
                  error: (_, _) => _buildMemoryPanelMessage(
                    theme,
                    icon: Icons.error_outline_rounded,
                    title: '读取失败',
                    message: '稍后再打开今日回忆试试。',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryPanelMessage(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.muted.withAlpha(150), size: 34),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildFoldedMemoryCard(TimelineEvent event, int index) {
    final delay = index * 0.055;
    final start = delay.clamp(0.0, 0.62).toDouble();
    final end = math.min(1.0, start + 0.34);
    final rawProgress = ((_memoryController.value - start) / (end - start))
        .clamp(0.0, 1.0)
        .toDouble();
    final progress = Curves.easeOutCubic.transform(rawProgress);
    final rotation = (index.isEven ? -0.006 : 0.006) * progress;

    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 26),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            alignment: Alignment.topCenter,
            scaleY: 0.86 + progress * 0.14,
            child: _MemoryEventCard(
              key: ValueKey('memory-card-$index'),
              event: event,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceArea(FlashRecordState state, ThemeData theme) {
    final effectiveLabel = state.phase == FlashPhase.listening
        ? '正在聆听…'
        : state.speechAvailable
        ? '点击开始记录'
        : '点击生成测试记录';

    final liveText = state.rawText.trim();
    final errorText = state.errorMessage?.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VoiceButton(
          phase: state.phase.name,
          speechAvailable: state.speechAvailable,
          onStart: () {
            unawaited(ref.read(flashRecordProvider.notifier).startListening());
          },
          onStop: () {
            unawaited(ref.read(flashRecordProvider.notifier).stopListening());
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!state.speechAvailable && !state.speechChecking)
          Text(
            '模拟器语音不可用 · 使用测试模式',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.muted.withAlpha(140),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        const SizedBox(height: AppSpacing.md),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            effectiveLabel,
            key: ValueKey(effectiveLabel),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: state.phase == FlashPhase.listening
                  ? AppColors.primary
                  : AppColors.muted,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 300,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              errorText?.isNotEmpty == true
                  ? errorText!
                  : liveText.isNotEmpty
                  ? liveText
                  : state.phase == FlashPhase.listening
                  ? '再次点击或松开后完成识别'
                  : '也可以长按话筒说话',
              key: ValueKey('${errorText ?? ''}-$liveText'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: errorText?.isNotEmpty == true
                    ? AppColors.accent
                    : AppColors.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecognizedArea(FlashRecordState state, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerMargin,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  state.rawText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        ref.read(flashRecordProvider.notifier).cancelConfirm();
                      },
                      child: const Text('重新说'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () {
                        ref.read(flashRecordProvider.notifier).confirmParsed();
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('确认'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingArea(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '保存中…',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }

  Widget _buildTextInput(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.containerMargin,
        0,
        AppSpacing.containerMargin,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(),
              decoration: InputDecoration(
                hintText: '或输入文字…',
                hintStyle: TextStyle(color: AppColors.muted.withAlpha(160)),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            onPressed: _submitText,
            icon: const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildCardOverlay(FlashRecordState state, ThemeData theme) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        color: Colors.black.withAlpha(80),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.containerMargin,
          ),
          child: FlashCard(
            rawText: state.rawText,
            parsedInput: state.parsedInput!,
            onSave: () {
              ref.read(flashRecordProvider.notifier).save();
            },
            onCancel: () {
              ref.read(flashRecordProvider.notifier).cancelConfirm();
            },
          ),
        ),
      ),
    );
  }
}

class _MemoryEventCard extends StatelessWidget {
  const _MemoryEventCard({required this.event, super.key});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _tintForType(event.type);
    final tag = event.tags.isNotEmpty
        ? event.tags.first
        : _labelForType(event.type);
    final note = event.description.trim().isEmpty
        ? _formatEventTime(event.timestamp)
        : event.description.trim();

    return Material(
      color: AppColors.surface.withAlpha(248),
      elevation: 4,
      shadowColor: AppColors.softShadow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border.withAlpha(210)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withAlpha(38),
                shape: BoxShape.circle,
              ),
              child: Icon(event.icon, color: tint, size: 21),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: tint.withAlpha(30),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                tag,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatEventTime(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _labelForType(String type) => switch (type) {
  'todo' => '待办',
  'tracker' => '打卡',
  'focus' => '专注',
  'expense' => '消费',
  'body' => '身体',
  'sleep' => '睡眠',
  'mood' => '情绪',
  _ => '记录',
};

Color _tintForType(String type) => switch (type) {
  'todo' => AppColors.todo,
  'tracker' => AppColors.tracker,
  'focus' => AppColors.focus,
  'expense' => AppColors.expense,
  'body' => AppColors.body,
  'sleep' => const Color(0xFF7A6EA8),
  'mood' => const Color(0xFFD5952F),
  _ => AppColors.primary,
};
