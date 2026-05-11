import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/database/repository_providers.dart';
import '../../core/parser/lui_lite_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../timeline/timeline_providers.dart';
import 'flash_record_notifier.dart';
import 'flash_record_state.dart';
import 'widgets/audio_waveform.dart';
import 'widgets/flash_card.dart';
import 'widgets/voice_button.dart';

final todayTodoPanelEventsProvider = FutureProvider<List<TimelineEvent>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  final todayEvents = await loadTimelineEventsForDate(ref, today);
  final dailyEvents = todayEvents
      .where((event) => event.source != TimelineEventSource.todo)
      .toList();
  final agendaTodos = await ref
      .read(todosRepositoryProvider)
      .findAgenda(anchorDate: today);
  final todoEvents = agendaTodos.map(_todoRowToTimelineEvent);
  return [...dailyEvents, ...todoEvents]
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});

TimelineEvent _todoRowToTimelineEvent(Map<String, Object?> row) {
  final isCompleted = (row['is_completed'] as int? ?? 0) == 1;
  return TimelineEvent(
    source: TimelineEventSource.todo,
    sourceId: row['id'] as int,
    type: 'todo',
    title: row['title'] as String,
    description: (row['note'] as String?) ?? (isCompleted ? 'done' : ''),
    timestamp: row['created_at'] as int,
    date: row['date'] as String,
    icon: isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
    tags: const [],
    data: row,
  );
}

class FlashRecordPage extends ConsumerStatefulWidget {
  const FlashRecordPage({super.key});

  @override
  ConsumerState<FlashRecordPage> createState() => _FlashRecordPageState();
}

class _FlashRecordPageState extends ConsumerState<FlashRecordPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _intentPillWidth = 120;
  static const double _intentPillHeight = 48;
  static const double _todoSwipeThreshold = 30;
  static const double _todoSwipeHorizontalTolerance = 34;

  final _textController = TextEditingController();
  final _recognizedTextController = TextEditingController();
  final _textFocusNode = FocusNode();
  late final AnimationController _memoryController;
  bool _memoryExpanded = false;
  bool _intentExpanded = false;
  bool _intentLongPressActive = false;
  bool _keyboardVisible = false;
  Offset _intentDragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textFocusNode.addListener(_handleTextFocusChange);
    _memoryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      reverseDuration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textFocusNode.removeListener(_handleTextFocusChange);
    _textController.dispose();
    _recognizedTextController.dispose();
    _textFocusNode.dispose();
    _memoryController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyboardOpen = WidgetsBinding.instance.platformDispatcher.views.any(
        (view) => view.viewInsets.bottom > 0,
      );
      if (_keyboardVisible && !keyboardOpen && _intentExpanded) {
        _collapseIntentInput();
      }
      _keyboardVisible = keyboardOpen;
    });
  }

  void _handleTextFocusChange() {
    if (!_textFocusNode.hasFocus && _intentExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_textFocusNode.hasFocus) {
          _collapseIntentInput();
        }
      });
    }
  }

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _collapseIntentInput();
    unawaited(ref.read(flashRecordProvider.notifier).saveAsText(text));
  }

  void _expandIntentInput() {
    if (!_intentExpanded) {
      setState(() => _intentExpanded = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFocusNode.requestFocus();
      }
    });
  }

  void _collapseIntentInput() {
    if (_intentExpanded) {
      setState(() => _intentExpanded = false);
    }
    _textFocusNode.unfocus();
  }

  void _handleIntentLongPress(FlashRecordState state) {
    _intentLongPressActive = true;
    HapticFeedback.lightImpact();
    _collapseIntentInput();
    unawaited(ref.read(flashRecordProvider.notifier).startListening());
  }

  void _handleIntentLongPressEnd() {
    if (!_intentLongPressActive) return;
    _intentLongPressActive = false;
    unawaited(ref.read(flashRecordProvider.notifier).stopListening());
  }

  void _handleIntentPanStart(DragStartDetails details) {
    _intentDragOffset = Offset.zero;
  }

  void _handleIntentPanUpdate(DragUpdateDetails details) {
    _intentDragOffset += details.delta;
  }

  void _handleIntentPanEnd(DragEndDetails details) {
    final verticalVelocity = details.velocity.pixelsPerSecond.dy;
    final isUpwardIntent =
        _intentDragOffset.dy < -_todoSwipeThreshold || verticalVelocity < -420;
    final isMostlyVertical =
        _intentDragOffset.dx.abs() <= _todoSwipeHorizontalTolerance;

    if (isUpwardIntent && isMostlyVertical) {
      HapticFeedback.selectionClick();
      _openMemoryScatter();
    }
    _intentDragOffset = Offset.zero;
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
    final memoryEvents = ref.watch(todayTodoPanelEventsProvider);
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
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _collapseIntentInput();
          FocusScope.of(context).unfocus();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Main content
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: MediaQuery.viewInsetsOf(context).bottom > 0 ? 0.38 : 1,
                child: Align(
                  alignment: const Alignment(0, -0.03),
                  child: _buildPrimaryStage(state, theme),
                ),
              ),
            ),

            if (_intentExpanded)
              Positioned.fill(
                child: ModalBarrier(
                  key: const ValueKey('intent-dismiss-layer'),
                  color: Colors.transparent,
                  dismissible: true,
                  onDismiss: _collapseIntentInput,
                ),
              ),

            if (state.isInputActive) _buildTextInputDock(state, theme),

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

  // ignore: unused_element
  Widget _buildTodayMemoryEntry(
    ThemeData theme,
    AsyncValue<List<TimelineEvent>> memoryEvents,
  ) {
    final subtitle = memoryEvents.when(
      data: (events) {
        final todoCount = events
            .where((event) => event.source == TimelineEventSource.todo)
            .length;
        return '$todoCount 个';
      },
      loading: () => '读取中',
      error: (_, _) => '读取失败',
    );

    return Positioned(
      right: AppSpacing.containerMargin,
      bottom: 82,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 88, minWidth: 76),
        child: Material(
          key: const ValueKey('today-todo-entry'),
          color: AppColors.surface.withAlpha(232),
          elevation: 1,
          shadowColor: AppColors.softShadow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            onTap: _openMemoryScatter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withAlpha(90),
                      ),
                    ),
                    child: const Icon(
                      Icons.checklist_rounded,
                      color: AppColors.primary,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      subtitle == '0 个' ? '待办' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryStage(FlashRecordState state, ThemeData theme) {
    if (state.phase == FlashPhase.idle || state.phase == FlashPhase.listening) {
      return _buildVoiceArea(state, theme);
    }
    if (state.phase == FlashPhase.recognized) {
      return _buildRecognizedArea(state, theme);
    }
    if (state.phase == FlashPhase.saving) {
      return _buildSavingArea(theme);
    }
    return _buildVoiceArea(state, theme);
  }

  Widget _buildTextInputDock(FlashRecordState state, ThemeData theme) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomOffset = keyboardInset > 0 ? 72.0 : AppSpacing.lg;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: bottomOffset,
      child: _buildUnifiedIntentInput(state, theme, compact: keyboardInset > 0),
    );
  }

  Widget _buildMemoryScatterLayer(
    ThemeData theme,
    AsyncValue<List<TimelineEvent>> memoryEvents,
  ) {
    return Positioned.fill(
      key: const ValueKey('todo-panel-layer'),
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
                    final sheetHeight = (constraints.maxHeight * 0.58)
                        .clamp(360.0, 560.0)
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
        key: const ValueKey('todo-panel-bottom-sheet'),
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.checklist_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('todo-panel-close'),
                    tooltip: '收起',
                    onPressed: _closeMemoryScatter,
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Expanded(
                child: memoryEvents.when(
                  data: (events) => _buildTodoPanelAgenda(events),
                  loading: () => _buildMemoryPanelMessage(
                    icon: Icons.hourglass_empty_rounded,
                  ),
                  error: (_, _) => _buildMemoryPanelMessage(
                    icon: Icons.error_outline_rounded,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodoPanelAgenda(List<TimelineEvent> events) {
    final dailyEvents = events
        .where((event) => event.source != TimelineEventSource.todo)
        .toList();
    final todoEvents = events
        .where((event) => event.source == TimelineEventSource.todo)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildTodoPanelColumn(
            key: const ValueKey('todo-panel-daily-column'),
            listKey: const ValueKey('todo-panel-daily-list'),
            events: dailyEvents,
            todoColumn: false,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: _buildTodoPanelColumn(
            key: const ValueKey('todo-panel-todo-column'),
            listKey: const ValueKey('todo-panel-todo-list'),
            events: todoEvents,
            todoColumn: true,
          ),
        ),
      ],
    );
  }

  Widget _buildTodoPanelColumn({
    required Key key,
    required Key listKey,
    required List<TimelineEvent> events,
    required bool todoColumn,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withAlpha(160),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border.withAlpha(210)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: events.isEmpty
                ? _buildMemoryPanelMessage(
                    icon: todoColumn
                        ? Icons.check_circle_outline
                        : Icons.timeline_rounded,
                  )
                : _buildFadedScrollable(
                    ListView.separated(
                      key: listKey,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxs,
                      ),
                      itemCount: events.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: todoColumn ? AppSpacing.xxs : 2),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final child = todoColumn
                            ? _TodoPanelEventCard(event: event)
                            : _MiniTimelineEvent(
                                event: event,
                                isLast: index == events.length - 1,
                              );
                        return _buildFoldedPanelCard(
                          child,
                          index,
                          keyPrefix: todoColumn ? 'todo' : 'daily',
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryPanelMessage({required IconData icon}) {
    return Center(
      child: Icon(icon, color: AppColors.muted.withAlpha(110), size: 30),
    );
  }

  Widget _buildFadedScrollable(Widget child) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, 0.08, 0.92, 1],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }

  Widget _buildFoldedPanelCard(
    Widget child,
    int index, {
    required String keyPrefix,
  }) {
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
            child: KeyedSubtree(
              key: ValueKey('todo-panel-$keyPrefix-card-$index'),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceArea(FlashRecordState state, ThemeData theme) {
    final effectiveLabel = state.phase == FlashPhase.listening
        ? '正在本地识别...'
        : state.sttLoading
        ? '正在唤醒离线大脑...'
        : state.sttReady
        ? '时刻准备记录你的灵感'
        : state.sttStatusMessage;

    final liveText = state.partialText.trim().isNotEmpty
        ? state.partialText.trim()
        : state.rawText.trim();
    final errorText = state.errorMessage?.trim();
    final voiceAvailable = state.sttReady;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: VoiceButton(
            phase: state.phase.name,
            voiceAvailable: voiceAvailable,
            onStart: () {
              unawaited(
                ref.read(flashRecordProvider.notifier).startListening(),
              );
            },
            onStop: () {
              unawaited(ref.read(flashRecordProvider.notifier).stopListening());
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!state.sttReady && !state.sttLoading)
          Text(
            state.sttStatusMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.muted.withAlpha(140),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        RepaintBoundary(
          child: AudioWaveform(
            level: state.audioLevel,
            active: state.phase == FlashPhase.listening,
          ),
        ),
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
                  ? '松开后整理成闪记卡片'
                  : state.sttLoading
                  ? '首次加载稍慢，之后会热启动'
                  : '也可以长按话筒说话',
              key: ValueKey('${errorText ?? ''}-$liveText'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: errorText?.isNotEmpty == true
                    ? AppColors.accent
                    : state.transcriptFinal
                    ? AppColors.ink
                    : AppColors.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecognizedArea(FlashRecordState state, ThemeData theme) {
    if (_recognizedTextController.text != state.rawText) {
      _recognizedTextController.text = state.rawText;
      _recognizedTextController.selection = TextSelection.fromPosition(
        TextPosition(offset: state.rawText.length),
      );
    }

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
                TextField(
                  controller: _recognizedTextController,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
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
                    contentPadding: const EdgeInsets.all(AppSpacing.sm),
                    hintText: '修改识别结果…',
                    hintStyle: TextStyle(color: AppColors.muted.withAlpha(120)),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        _recognizedTextController.clear();
                        ref.read(flashRecordProvider.notifier).cancelConfirm();
                      },
                      child: const Text('重新说'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () {
                        final edited = _recognizedTextController.text.trim();
                        ref
                            .read(flashRecordProvider.notifier)
                            .confirmParsed(edited);
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

  Widget _buildUnifiedIntentInput(
    FlashRecordState state,
    ThemeData theme, {
    bool compact = false,
  }) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    _keyboardVisible = keyboardOpen;
    final expanded = _intentExpanded;
    final horizontalPadding = expanded ? AppSpacing.containerMargin + 12 : 0.0;
    final isListening = state.phase == FlashPhase.listening;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        compact ? 0 : AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandedWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width - horizontalPadding * 2;

          return Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              key: const ValueKey('unified-intent-pill'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: expanded ? expandedWidth : _intentPillWidth,
              height: expanded ? 54 : _intentPillHeight,
              decoration: BoxDecoration(
                color: (isListening ? AppColors.primary : AppColors.surface)
                    .withAlpha(isListening ? 232 : 218),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                border: Border.all(
                  color: isListening
                      ? AppColors.primary.withAlpha(90)
                      : AppColors.border.withAlpha(132),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isListening ? AppColors.primary : AppColors.softShadow)
                            .withAlpha(isListening ? 36 : 24),
                    blurRadius: isListening ? 22 : 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: expanded
                    ? _buildExpandedIntentInput(state, theme)
                    : _buildCollapsedIntentPill(state, theme),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCollapsedIntentPill(FlashRecordState state, ThemeData theme) {
    final isListening = state.phase == FlashPhase.listening;
    final foreground = isListening ? Colors.white : AppColors.primary;

    return Listener(
      key: const ValueKey('collapsed-intent-pill'),
      behavior: HitTestBehavior.opaque,
      onPointerUp: (_) => _handleIntentLongPressEnd(),
      onPointerCancel: (_) => _handleIntentLongPressEnd(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _expandIntentInput,
        onLongPress: () => _handleIntentLongPress(state),
        onLongPressEnd: (_) => _handleIntentLongPressEnd(),
        onLongPressUp: _handleIntentLongPressEnd,
        onPanStart: _handleIntentPanStart,
        onPanUpdate: _handleIntentPanUpdate,
        onPanEnd: _handleIntentPanEnd,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              opacity: isListening ? 0.8 : 0.34,
              child: Container(
                width: 58,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  gradient: LinearGradient(
                    colors: [
                      foreground.withAlpha(0),
                      foreground.withAlpha(isListening ? 92 : 44),
                      foreground.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
            Icon(
              isListening
                  ? Icons.graphic_eq_rounded
                  : Icons.keyboard_alt_rounded,
              color: foreground,
              size: isListening ? 24 : 21,
            ),
            Positioned(
              top: 6,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: foreground.withAlpha(isListening ? 170 : 105),
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedIntentInput(FlashRecordState state, ThemeData theme) {
    return Row(
      key: const ValueKey('expanded-intent-input'),
      children: [
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: TextField(
            key: const ValueKey('record-text-input'),
            focusNode: _textFocusNode,
            controller: _textController,
            onTapOutside: (_) => _collapseIntentInput(),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submitText(),
            maxLines: 1,
            decoration: InputDecoration(
              hintText: '文字',
              hintStyle: TextStyle(color: AppColors.muted.withAlpha(145)),
              filled: false,
              fillColor: Colors.transparent,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
            ),
          ),
        ),
        Semantics(
          label: 'record-text-submit',
          button: true,
          child: IconButton(
            key: const ValueKey('record-text-submit'),
            onPressed: _submitText,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: state.textSaving
                  ? const SizedBox(
                      key: ValueKey('record-text-saving'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      key: ValueKey('record-text-send-icon'),
                      color: AppColors.primary,
                    ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildTextInput(
    FlashRecordState state,
    ThemeData theme, {
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.containerMargin + 12,
        0,
        AppSpacing.containerMargin + 12,
        compact ? 0 : AppSpacing.md,
      ),
      child: Material(
        color: AppColors.surface.withAlpha(218),
        elevation: 0,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(color: AppColors.border.withAlpha(130)),
          ),
          child: Row(
            children: [
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('record-text-input'),
                  controller: _textController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitText(),
                  maxLines: 1,
                  decoration: InputDecoration(
                    hintText: '文字',
                    hintStyle: TextStyle(color: AppColors.muted.withAlpha(145)),
                    filled: false,
                    fillColor: Colors.transparent,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              Semantics(
                label: 'record-text-submit',
                button: true,
                child: IconButton(
                  key: const ValueKey('record-text-submit'),
                  onPressed: _submitText,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: state.textSaving
                        ? const SizedBox(
                            key: ValueKey('record-text-saving'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            key: ValueKey('record-text-send-icon'),
                            color: AppColors.primary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyTextInput(
    FlashRecordState state,
    ThemeData theme, {
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.containerMargin,
        0,
        AppSpacing.containerMargin,
        compact ? 0 : AppSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('record-text-input'),
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(),
              maxLines: 1,
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
          Semantics(
            label: 'record-text-submit',
            button: true,
            child: IconButton(
              key: const ValueKey('record-text-submit'),
              onPressed: _submitText,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: state.textSaving
                    ? const SizedBox(
                        key: ValueKey('record-text-saving'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        key: ValueKey('record-text-send-icon'),
                        color: AppColors.primary,
                      ),
              ),
            ),
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
            onSwitchToTodo: state.parsedInput?.type != ParsedInputType.todo
                ? () {
                    ref
                        .read(flashRecordProvider.notifier)
                        .switchParsedType(ParsedInputType.todo);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

class _MiniTimelineEvent extends StatelessWidget {
  const _MiniTimelineEvent({required this.event, required this.isLast});

  final TimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _tintForType(event.type);
    final note = event.description.trim();
    final tags = event.tags.take(2).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Column(
            children: [
              Container(
                width: 28,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: tint.withAlpha(24),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  _formatEventTime(event.timestamp),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.only(top: 2),
                  color: AppColors.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.xxs),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.surface.withAlpha(232),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border.withAlpha(190)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.xxs,
                      runSpacing: AppSpacing.xxs,
                      children: tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tint.withAlpha(22),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm,
                                ),
                              ),
                              child: Text(
                                tag,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: tint,
                                  fontWeight: FontWeight.w600,
                                ),
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
        ),
      ],
    );
  }
}

class _TodoPanelEventCard extends ConsumerWidget {
  const _TodoPanelEventCard({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCompleted = (event.data['is_completed'] as int? ?? 0) == 1;

    return Material(
      color: AppColors.surface.withAlpha(248),
      elevation: 4,
      shadowColor: AppColors.softShadow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () => _toggleTodo(ref, isCompleted),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border.withAlpha(210)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isCompleted ? AppColors.todo : AppColors.muted,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.xs),
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
                        color: isCompleted
                            ? AppColors.muted
                            : AppColors.primary,
                        fontWeight: FontWeight.w700,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleTodo(WidgetRef ref, bool isCompleted) async {
    final repo = ref.read(todosRepositoryProvider);
    if (isCompleted) {
      await repo.reopen(event.sourceId);
    } else {
      await repo.complete(event.sourceId);
    }
    ref.invalidate(todayTodoPanelEventsProvider);
    ref.read(dataVersionProvider.notifier).increment();
  }
}

String _formatEventTime(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

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
