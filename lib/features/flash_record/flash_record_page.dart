import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../focus/focus_session_page.dart';
import '../long_note/long_note_editor_page.dart';
import '../photo_moment/photo_moment_editor_page.dart';
import '../projects/project_store.dart';
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
  static const double _todoSwipeThreshold = 18;
  static const double _todoSwipeHorizontalTolerance = 52;
  static const double _toolSwipeThreshold = 18;
  static const Duration _intentSettleDuration = Duration(milliseconds: 340);
  static const Duration _intentContentSwapDuration = Duration(
    milliseconds: 180,
  );
  static const Curve _intentMotionCurve = Cubic(0.16, 1.0, 0.3, 1.0);

  final _textController = TextEditingController();
  final _recognizedTextController = TextEditingController();
  final _textFocusNode = FocusNode();
  final _imagePicker = ImagePicker();
  late final AnimationController _memoryController;
  Timer? _keyboardRevealTimer;
  bool _memoryExpanded = false;
  bool _intentExpanded = false;
  bool _intentLongPressActive = false;
  bool _toolsExpanded = false;
  bool _keyboardVisible = false;
  bool _keyboardLaunchExpanding = false;
  bool _keyboardHiding = false;
  bool _capturingPhoto = false;
  bool _recoveringLostPhoto = false;
  int _launchCompletedAt = 0;
  Offset _intentDragOffset = Offset.zero;

  void _logInput(String message) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final line = '[$ts] $message';
    developer.log(line, name: 'LiflowKB');
    debugPrint('LiflowKB $line');
  }

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
    unawaited(_recoverLostPhoto());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textFocusNode.removeListener(_handleTextFocusChange);
    _textController.dispose();
    _recognizedTextController.dispose();
    _textFocusNode.dispose();
    _keyboardRevealTimer?.cancel();
    _memoryController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final viewInsets = WidgetsBinding.instance.platformDispatcher.views
        .map((v) => v.viewInsets.bottom)
        .toList();
    final keyboardOpen = viewInsets.any((b) => b > 0);
    final wasKeyboardVisible = _keyboardVisible;
    if (keyboardOpen != _keyboardVisible) {
      _logInput(
        'metrics changed keyboardOpen=$keyboardOpen insets=$viewInsets expanded=$_intentExpanded focus=${_textFocusNode.hasFocus} launching=$_keyboardLaunchExpanding',
      );
    }
    if (keyboardOpen && _keyboardLaunchExpanding) {
      _logInput('keyboard detected, completing launch now');
      _keyboardRevealTimer?.cancel();
      _completeKeyboardLaunch('metrics');
    }
    if (wasKeyboardVisible &&
        !keyboardOpen &&
        (_intentExpanded || _keyboardLaunchExpanding)) {
      _logInput('metrics keyboard closed while expanded, collapsing');
      _collapseIntentInput(reason: 'metrics-keyboard-closed', unfocus: false);
    }
    if (mounted && _keyboardVisible != keyboardOpen) {
      setState(() => _keyboardVisible = keyboardOpen);
    } else {
      _keyboardVisible = keyboardOpen;
    }
  }

  void _handleTextFocusChange() {
    _logInput(
      'focus_change hasFocus=${_textFocusNode.hasFocus} expanded=$_intentExpanded launching=$_keyboardLaunchExpanding',
    );
    if (!_textFocusNode.hasFocus && _intentExpanded) {
      if (_keyboardLaunchExpanding) {
        _logInput('focus lost ignored during keyboard launch');
        return;
      }
      final sinceLaunch =
          DateTime.now().millisecondsSinceEpoch - _launchCompletedAt;
      if (sinceLaunch < 400) {
        _logInput(
          'focus lost ignored, within $sinceLaunch ms of launch complete',
        );
        return;
      }
      _collapseIntentInput(reason: 'focus-lost', unfocus: false);
    }
  }

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _collapseIntentInput(reason: 'submit');
    unawaited(ref.read(flashRecordProvider.notifier).saveAsText(text));
  }

  static void _openLongNoteEditor(BuildContext context) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const LongNoteEditorPage(),
      ),
    );
  }

  Future<void> _openFocusSession(BuildContext context) async {
    _closeToolDrawer();
    _collapseIntentInput(reason: 'open-focus-session');
    FocusScope.of(context).unfocus();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const FocusSessionPage(),
      ),
    );
    if (saved == true && mounted) {
      ref.invalidate(todayTodoPanelEventsProvider);
    }
  }

  void _expandIntentInput() {
    _closeToolDrawer();
    final phase = ref.read(flashRecordProvider).phase;
    _logInput(
      'expand_tap phase=${phase.name} expanded=$_intentExpanded launching=$_keyboardLaunchExpanding kbVis=$_keyboardVisible focus=${_textFocusNode.hasFocus}',
    );
    if (phase == FlashPhase.listening) {
      _logInput('expand ignored while listening');
      return;
    }
    if (_keyboardHiding) {
      _logInput('expand deferred — keyboard still hiding, retrying once');
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        _keyboardHiding = false;
        _expandIntentInput();
      });
      return;
    }
    if (_keyboardLaunchExpanding) {
      _logInput('expand repeat-tap kbVis=$_keyboardVisible');
      if (_keyboardVisible) {
        _completeKeyboardLaunch('repeat-tap');
      } else {
        _logInput('repeat tap while waiting for keyboard metrics');
      }
      _textFocusNode.requestFocus();
      return;
    }
    if (!_intentExpanded) {
      _logInput('expand starting launch — waiting for keyboard');
      setState(() {
        _keyboardLaunchExpanding = true;
      });
      _keyboardRevealTimer?.cancel();
      _keyboardRevealTimer = Timer(
        const Duration(milliseconds: 500),
        () => _completeKeyboardLaunch('fallback'),
      );
    } else {
      _logInput('expand already expanded, re-focusing');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _logInput('expand requestFocus in postFrame');
        _textFocusNode.requestFocus();
      }
    });
  }

  void _completeKeyboardLaunch(String reason) {
    _logInput(
      'launch_complete reason=$reason mounted=$mounted launching=$_keyboardLaunchExpanding expanded=$_intentExpanded focus=${_textFocusNode.hasFocus}',
    );
    if (!mounted || !_keyboardLaunchExpanding) {
      _logInput(
        'launch_complete ABORT mounted=$mounted launching=$_keyboardLaunchExpanding',
      );
      return;
    }
    _keyboardRevealTimer?.cancel();
    _logInput('launch_complete setting expanded=true');
    _launchCompletedAt = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _keyboardLaunchExpanding = false;
      _intentExpanded = true;
    });
    if (!_textFocusNode.hasFocus && reason == 'fallback') {
      _logInput('launch_complete focus not acquired after fallback, retrying');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }
  }

  void _collapseIntentInput({String reason = 'unknown', bool unfocus = true}) {
    final hadFocus = _textFocusNode.hasFocus;
    _logInput(
      'collapse reason=$reason expanded=$_intentExpanded focus=$hadFocus keyboard=$_keyboardVisible launching=$_keyboardLaunchExpanding',
    );
    if (!_intentExpanded &&
        !_keyboardLaunchExpanding &&
        (!unfocus || !hadFocus)) {
      _logInput('collapse SKIP nothing to do');
      return;
    }
    _keyboardRevealTimer?.cancel();
    if (_intentExpanded || _keyboardLaunchExpanding) {
      _logInput('collapse clearing expanded/launching state');
      setState(() {
        _intentExpanded = false;
        _keyboardLaunchExpanding = false;
      });
    }
    if (unfocus && (hadFocus || _keyboardVisible || _keyboardHiding)) {
      _logInput('collapse unfocusing');
      _keyboardHiding = true;
      FocusScope.of(context).unfocus();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _keyboardHiding = false;
      });
    }
  }

  void _handleIntentLongPress(FlashRecordState state) {
    _intentLongPressActive = true;
    HapticFeedback.lightImpact();
    _collapseIntentInput(reason: 'intent-long-press');
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
        _intentDragOffset.dy < -_todoSwipeThreshold || verticalVelocity < -250;
    final isDownwardIntent =
        _intentDragOffset.dy > _toolSwipeThreshold || verticalVelocity > 250;
    final isMostlyVertical =
        _intentDragOffset.dx.abs() <= _todoSwipeHorizontalTolerance;

    if (isUpwardIntent && isMostlyVertical) {
      HapticFeedback.selectionClick();
      _openMemoryScatter();
    } else if (isDownwardIntent && isMostlyVertical) {
      HapticFeedback.selectionClick();
      _openToolDrawer();
    }
    _intentDragOffset = Offset.zero;
  }

  void _openMemoryScatter() {
    FocusScope.of(context).unfocus();
    _closeToolDrawer();
    if (_memoryExpanded) return;
    _logInput('memory panel opened');
    setState(() => _memoryExpanded = true);
    _memoryController.forward(from: 0);
  }

  void _closeMemoryScatter() {
    if (!_memoryExpanded) return;
    _logInput('memory panel closing');
    unawaited(
      _memoryController.reverse().then((_) {
        if (mounted) {
          setState(() => _memoryExpanded = false);
        }
      }),
    );
  }

  void _openToolDrawer() {
    FocusScope.of(context).unfocus();
    if (_toolsExpanded) return;
    _logInput('tool drawer opened');
    setState(() => _toolsExpanded = true);
  }

  void _closeToolDrawer() {
    if (!_toolsExpanded) return;
    _logInput('tool drawer closed');
    setState(() => _toolsExpanded = false);
  }

  void _dismissAmbientState(FlashRecordState state) {
    _logInput(
      'ambient_dismiss phase=${state.phase.name} expanded=$_intentExpanded focus=${_textFocusNode.hasFocus} launching=$_keyboardLaunchExpanding hiding=$_keyboardHiding kbVis=$_keyboardVisible',
    );
    if (_keyboardLaunchExpanding) {
      _logInput('ambient_dismiss ignored during keyboard launch');
      return;
    }
    _collapseIntentInput(reason: 'ambient-tap');
    _closeMemoryScatter();
    _closeToolDrawer();
    FocusScope.of(context).unfocus();
    if (state.phase == FlashPhase.listening) {
      _handleIntentLongPressEnd();
      unawaited(ref.read(flashRecordProvider.notifier).stopListening());
    }
  }

  Future<void> _handleTakePhoto() async {
    if (_capturingPhoto) return;

    _closeToolDrawer();
    _collapseIntentInput(reason: 'open-camera');
    FocusScope.of(context).unfocus();

    setState(() => _capturingPhoto = true);

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 92,
      );

      if (!mounted || photo == null) return;

      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              PhotoMomentEditorPage.create(sourceImagePath: photo.path),
        ),
      );

      if (saved == true && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('已保存图片片刻'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('拍照失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _capturingPhoto = false);
      }
    }
  }

  Future<void> _recoverLostPhoto() async {
    if (_recoveringLostPhoto) return;
    _recoveringLostPhoto = true;

    try {
      final response = await _imagePicker.retrieveLostData();
      if (!mounted || response.isEmpty) return;

      final file =
          response.file ??
          (response.files?.isNotEmpty ?? false ? response.files!.first : null);
      if (file == null) return;

      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              PhotoMomentEditorPage.create(sourceImagePath: file.path),
        ),
      );

      if (saved == true && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('已恢复并保存拍照片刻'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
      }
    } catch (_) {
      // Lost data recovery is best-effort. Ignore failures and keep the main flow responsive.
    } finally {
      _recoveringLostPhoto = false;
    }
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

    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _dismissAmbientState(state),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main content
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: MediaQuery.viewInsetsOf(context).bottom > 0
                      ? 0.38
                      : 1,
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
                    onDismiss: () => _collapseIntentInput(reason: 'barrier'),
                  ),
                ),

              if (state.isInputActive) _buildTextInputDock(state, theme),

              if (_memoryExpanded)
                _buildMemoryScatterLayer(theme, memoryEvents),

              // Flash card overlay
              if (state.phase == FlashPhase.confirming &&
                  state.parsedInput != null)
                _buildCardOverlay(state, theme),
            ],
          ),
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
    final reduceMotion = _keyboardLaunchExpanding;
    final bottomOffset = keyboardInset > 0
        ? math.max(AppSpacing.sm, keyboardInset - 72)
        : AppSpacing.lg;

    return AnimatedPositioned(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
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
                            child: RepaintBoundary(
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
    return RepaintBoundary(
      child: ShaderMask(
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
      ),
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
        ? state.recordingMode == FlashRecordingMode.audioOnly
              ? '正在录音，松开后保存原音'
              : '正在本地识别...'
        : state.recordingMode == FlashRecordingMode.audioOnly
        ? '大话筒会保存原始录音'
        : state.sttLoading
        ? '正在唤醒离线大脑...'
        : state.sttReady
        ? '时刻准备记录你的灵感'
        : state.sttStatusMessage;

    final liveText = state.partialText.trim().isNotEmpty
        ? state.partialText.trim()
        : state.rawText.trim();
    final errorText = state.errorMessage?.trim();
    final voiceAvailable =
        state.recordingMode == FlashRecordingMode.audioOnly || state.sttReady;

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
        _RecordingModeToggle(
          mode: state.recordingMode,
          enabled: state.phase != FlashPhase.listening,
          onChanged: (mode) {
            ref.read(flashRecordProvider.notifier).setRecordingMode(mode);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!state.sttReady &&
            !state.sttLoading &&
            state.recordingMode == FlashRecordingMode.transcribe)
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
        _VoiceHelperText(
          text: errorText?.isNotEmpty == true
              ? errorText!
              : liveText.isNotEmpty
              ? liveText
              : state.phase == FlashPhase.listening
              ? state.recordingMode == FlashRecordingMode.audioOnly
                    ? '松开后保存为一条语音片段'
                    : '松开后整理成闪记卡片'
              : '',
          isError: errorText?.isNotEmpty == true,
          isFinal: state.transcriptFinal,
        ),
      ],
    );
  }

  Widget _buildRecognizedArea(FlashRecordState state, ThemeData theme) {
    if (state.recordingDraft != null && state.rawText.trim().isEmpty) {
      return _buildAudioDraftArea(state, theme);
    }

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

  Widget _buildAudioDraftArea(FlashRecordState state, ThemeData theme) {
    final draft = state.recordingDraft;
    final durationText = draft == null
        ? ''
        : _formatAudioDuration(draft.duration);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerMargin,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.graphic_eq_rounded,
              color: AppColors.primary,
              size: 42,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              durationText.isEmpty ? '语音片段' : '语音片段 $durationText',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (state.errorMessage?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    ref.read(flashRecordProvider.notifier).cancelConfirm();
                  },
                  child: const Text('放弃'),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () {
                    ref.read(flashRecordProvider.notifier).saveAudioOnly();
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('保存原音'),
                ),
              ],
            ),
          ],
        ),
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
    final expanded = _intentExpanded || _keyboardLaunchExpanding;
    final horizontalPadding = expanded ? AppSpacing.containerMargin + 12 : 0.0;
    final isListening = state.phase == FlashPhase.listening;
    final keyboardMotion = _keyboardLaunchExpanding;

    return AnimatedPadding(
      duration: keyboardMotion ? Duration.zero : _intentSettleDuration,
      curve: _intentMotionCurve,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        compact ? 0 : AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_toolsExpanded && !expanded && !compact) ...[
            _buildToolDrawer(theme),
            const SizedBox(height: AppSpacing.sm),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final expandedWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width - horizontalPadding * 2;

              return Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  key: const ValueKey('unified-intent-pill'),
                  duration: keyboardMotion
                      ? Duration.zero
                      : _intentSettleDuration,
                  curve: _intentMotionCurve,
                  width: expanded ? expandedWidth : _intentPillWidth,
                  height: _intentPillHeight,
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
                            (isListening
                                    ? AppColors.primary
                                    : AppColors.softShadow)
                                .withAlpha(isListening ? 36 : 24),
                        blurRadius: isListening ? 22 : 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: keyboardMotion
                        ? Duration.zero
                        : _intentContentSwapDuration,
                    switchInCurve: _intentMotionCurve,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: _intentMotionCurve,
                      );
                      return FadeTransition(
                        opacity: curved,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.985,
                            end: 1,
                          ).animate(curved),
                          child: child,
                        ),
                      );
                    },
                    child: expanded
                        ? _buildExpandedIntentInput(state, theme)
                        : _buildCollapsedIntentPill(state, theme),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolDrawer(ThemeData theme) {
    return Material(
      color: AppColors.surface.withAlpha(242),
      elevation: 6,
      shadowColor: AppColors.softShadow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border.withAlpha(145)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '记录一个片刻',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 2.2,
              children: [
                _ToolDrawerAction(
                  icon: Icons.timer_rounded,
                  label: '专注',
                  onTap: () => _openFocusSession(context),
                ),
                _ToolDrawerAction(
                  icon: Icons.edit_note_rounded,
                  label: '长笔记',
                  onTap: () {
                    _closeToolDrawer();
                    _openLongNoteEditor(context);
                  },
                ),
                _ToolDrawerAction(
                  icon: Icons.camera_alt_rounded,
                  label: _capturingPhoto ? '拍照中...' : '拍照',
                  onTap: _capturingPhoto ? null : _handleTakePhoto,
                ),
                const _ToolDrawerAction(
                  icon: Icons.image_outlined,
                  label: '图片',
                  enabled: false,
                ),
                const _ToolDrawerAction(
                  icon: Icons.mic_none_rounded,
                  label: '录音',
                  enabled: false,
                ),
              ],
            ),
          ],
        ),
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
        onTap: isListening ? null : _expandIntentInput,
        onLongPress: isListening ? null : () => _handleIntentLongPress(state),
        onLongPressEnd: isListening ? null : (_) => _handleIntentLongPressEnd(),
        onLongPressUp: isListening ? null : _handleIntentLongPressEnd,
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
            if (!isListening)
              Icon(Icons.keyboard_alt_rounded, color: foreground, size: 21),
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
            onTapOutside: (_) => _collapseIntentInput(reason: 'tap-outside'),
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
    final projects = switch (ref.watch(projectOptionsProvider)) {
      AsyncData(value: final value) => value,
      _ => const <ProjectOption>[],
    };

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
            onTextChanged: (text) {
              ref.read(flashRecordProvider.notifier).updateParsedText(text);
            },
            onTypeChanged: (type) {
              ref.read(flashRecordProvider.notifier).switchParsedType(type);
            },
            onTagsChanged: (tags) {
              ref.read(flashRecordProvider.notifier).updateParsedTags(tags);
            },
            projects: projects,
            selectedProjectId: state.selectedProjectId,
            onProjectChanged: (projectId) {
              ref.read(flashRecordProvider.notifier).selectProject(projectId);
            },
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

class _ToolDrawerAction extends StatelessWidget {
  const _ToolDrawerAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    final tint = active ? AppColors.primary : AppColors.muted.withAlpha(160);

    return Material(
      color: tint.withAlpha(active ? 18 : 8),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: active ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: tint.withAlpha(active ? 70 : 32)),
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w700,
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

class _RecordingModeToggle extends StatelessWidget {
  const _RecordingModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final FlashRecordingMode mode;
  final bool enabled;
  final ValueChanged<FlashRecordingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 132,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface.withAlpha(220),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withAlpha(180)),
      ),
      child: Row(
        children: [
          _RecordingModeSegment(
            icon: Icons.notes_rounded,
            label: '文',
            semanticsLabel: '转文字',
            selected: mode == FlashRecordingMode.transcribe,
            enabled: enabled,
            theme: theme,
            onTap: () => onChanged(FlashRecordingMode.transcribe),
          ),
          _RecordingModeSegment(
            icon: Icons.graphic_eq_rounded,
            label: '音',
            semanticsLabel: '留原音',
            selected: mode == FlashRecordingMode.audioOnly,
            enabled: enabled,
            theme: theme,
            onTap: () => onChanged(FlashRecordingMode.audioOnly),
          ),
        ],
      ),
    );
  }
}

class _RecordingModeSegment extends StatelessWidget {
  const _RecordingModeSegment({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.enabled,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final bool selected;
  final bool enabled;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? AppColors.primary : AppColors.muted;

    return Expanded(
      child: Semantics(
        label: semanticsLabel,
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withAlpha(28)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: tint.withAlpha(enabled ? 220 : 120),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tint.withAlpha(enabled ? 230 : 130),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceHelperText extends StatelessWidget {
  const _VoiceHelperText({
    required this.text,
    required this.isError,
    required this.isFinal,
  });

  final String text;
  final bool isError;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 300,
      height: 34,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: text.isEmpty
            ? const SizedBox.shrink(key: ValueKey('voice-helper-empty'))
            : Text(
                text,
                key: ValueKey(text),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isError
                      ? AppColors.accent
                      : isFinal
                      ? AppColors.ink
                      : AppColors.muted,
                ),
              ),
      ),
    );
  }
}

String _formatAudioDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
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
