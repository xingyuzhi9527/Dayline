import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({super.key, this.initialStartedAt});

  final DateTime? initialStartedAt;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;
  late DateTime _startedAt;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _paused = false;
  bool _saving = false;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startedAt = widget.initialStartedAt ?? DateTime.now();
    _elapsed = DateTime.now().difference(_startedAt);
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breathController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _tick() {
    if (_paused || _saving) return;
    setState(() => _elapsed = DateTime.now().difference(_startedAt));
  }

  void _togglePause() {
    if (_saving) return;
    setState(() {
      _paused = !_paused;
      if (!_paused) {
        _startedAt = DateTime.now().subtract(_elapsed);
        _breathController.repeat(reverse: true);
      } else {
        _breathController.stop();
      }
    });
  }

  Future<void> _complete() async {
    if (_saving) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final durationMinutes = math.max(1, (_elapsed.inSeconds / 60).ceil());
    final note = _noteController.text.trim();

    try {
      await ref
          .read(focusSessionsRepositoryProvider)
          .create(
            date: now,
            startedAt: now.subtract(_elapsed),
            endedAt: now,
            durationMinutes: durationMinutes,
            note: note.isEmpty ? null : note,
            createdAt: now,
          );
      ref.read(dataVersionProvider.notifier).increment();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已记录专注 $durationMinutes 分钟'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('保存专注失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xFF17211E),
      body: AnimatedBuilder(
        animation: _breathController,
        builder: (context, child) {
          final breath = _paused ? 0.0 : _breathController.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.28),
                radius: 1.05 + breath * 0.12,
                colors: [
                  Color.lerp(
                    const Color(0xFF49645B),
                    const Color(0xFF6E8A7D),
                    breath,
                  )!,
                  const Color(0xFF17211E),
                  const Color(0xFF101513),
                ],
                stops: const [0.0, 0.58, 1.0],
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                    ),
                    const Spacer(),
                    Text(
                      _paused ? '已暂停' : '专注中',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '$minutes:$seconds',
                  key: const ValueKey('focus-session-timer'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 76,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('focus-session-note'),
                  controller: _noteController,
                  enabled: !_saving,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: '正在专注什么？',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(120)),
                    filled: true,
                    fillColor: Colors.white.withAlpha(18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _togglePause,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withAlpha(80)),
                        ),
                        icon: Icon(
                          _paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        label: Text(_paused ? '继续' : '暂停'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('focus-session-complete'),
                        onPressed: _saving ? null : _complete,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.tracker,
                          foregroundColor: Colors.white,
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: const Text('完成'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('放弃'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
