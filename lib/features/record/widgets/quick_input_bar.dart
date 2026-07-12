import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../record_notifier.dart';

enum QuickInputMode { preview, saveImmediately }

class QuickInputBar extends ConsumerStatefulWidget {
  const QuickInputBar({
    this.placeholder = '写下一句话... 或输入“午餐花了38元”',
    this.minLines = 2,
    this.showTools = true,
    this.mode = QuickInputMode.preview,
    super.key,
  });

  final String placeholder;
  final int minLines;
  final bool showTools;
  final QuickInputMode mode;

  @override
  ConsumerState<QuickInputBar> createState() => _QuickInputBarState();
}

class _QuickInputBarState extends ConsumerState<QuickInputBar> {
  final _controller = TextEditingController();
  bool _awaitingSaveClear = false;

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    setState(() {});
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _awaitingSaveClear = true;
    final notifier = ref.read(recordNotifierProvider.notifier);

    if (widget.mode == QuickInputMode.saveImmediately) {
      final saved = await notifier.saveInput(text);
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? '已保存到今日'
                : ref.read(recordNotifierProvider).errorMessage ?? '保存失败',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    notifier.submit(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordNotifierProvider);

    if (_awaitingSaveClear &&
        state.inputText.isEmpty &&
        state.parsedInput == null &&
        !state.isSaving &&
        _controller.text.isNotEmpty) {
      _awaitingSaveClear = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.clear();
      });
    }

    final canSubmit = _controller.text.trim().isNotEmpty && !state.isSaving;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final buttonLabel = widget.mode == QuickInputMode.saveImmediately
        ? '保存'
        : '整理';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: widget.placeholder,
                prefixIcon: Container(
                  width: 42,
                  height: 42,
                  margin: const EdgeInsets.only(right: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: colors.primary.withAlpha(14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit_rounded, color: colors.primary),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 52,
                  minHeight: 44,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              minLines: widget.minLines,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              enabled: !state.isSaving,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (widget.showTools) ...[
                  _ToolIcon(icon: Icons.image_outlined, tooltip: '图片'),
                  const SizedBox(width: AppSpacing.xs),
                  _ToolIcon(icon: Icons.mic_none_rounded, tooltip: '语音'),
                  const SizedBox(width: AppSpacing.xs),
                  _ToolIcon(icon: Icons.location_on_outlined, tooltip: '位置'),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: canSubmit ? _submit : null,
                  icon: state.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(buttonLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Icon(icon, size: 18, color: colors.onSurfaceVariant),
      ),
    );
  }
}
