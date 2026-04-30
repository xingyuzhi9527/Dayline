import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../record_notifier.dart';

class QuickInputBar extends ConsumerStatefulWidget {
  const QuickInputBar({
    this.placeholder = '写下一句话，Dayline 会帮你整理...',
    this.minLines = 2,
    this.showTools = true,
    super.key,
  });

  final String placeholder;
  final int minLines;
  final bool showTools;

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

  void _submit() {
    if (!_controller.text.trim().isNotEmpty) return;
    _awaitingSaveClear = true;
    ref.read(recordNotifierProvider.notifier).updateInput(_controller.text);
    ref.read(recordNotifierProvider.notifier).submit();
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: widget.placeholder,
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
            const SizedBox(height: AppSpacing.sm),
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
                  label: const Text('保存'),
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
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.canvas,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Icon(icon, size: 18, color: AppColors.muted),
      ),
    );
  }
}
