import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/parser/lui_lite_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../record_notifier.dart';

class ParserPreviewCard extends ConsumerWidget {
  const ParserPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordNotifierProvider);
    final parsed = state.parsedInput;
    if (parsed == null) return const SizedBox.shrink();

    final notifier = ref.read(recordNotifierProvider.notifier);
    final theme = Theme.of(context);
    final typeMeta = _TypeMeta.from(parsed.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.psychology_alt_outlined, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text('理解为', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PreviewHeader(typeMeta: typeMeta, parsed: parsed),
                const SizedBox(height: AppSpacing.md),
                Text(parsed.content, style: theme.textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _InfoPill(
                      icon: typeMeta.icon,
                      label: '类型',
                      value: typeMeta.label,
                      color: typeMeta.color,
                    ),
                    _InfoPill(
                      icon: Icons.schedule_rounded,
                      label: '时间',
                      value: parsed.time ?? '现在',
                      color: AppColors.primary,
                    ),
                    if (parsed.metadata['durationMinutes'] != null)
                      _InfoPill(
                        icon: Icons.timer_rounded,
                        label: '时长',
                        value: '${parsed.metadata['durationMinutes']} 分钟',
                        color: const Color(0xFFE67E22),
                      ),
                    if (parsed.metadata['amount'] != null)
                      _InfoPill(
                        icon: Icons.payments_rounded,
                        label: '金额',
                        value: '¥${parsed.metadata['amount']}',
                        color: const Color(0xFFE74C3C),
                      ),
                    if (parsed.metadata['value'] != null)
                      _InfoPill(
                        icon: Icons.monitor_weight_rounded,
                        label: '数值',
                        value: '${parsed.metadata['value']}',
                        color: const Color(0xFF9B59B6),
                      ),
                  ],
                ),
                if (parsed.tags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: parsed.tags
                        .map(
                          (tag) => Chip(
                            avatar: const Icon(Icons.tag, size: 14),
                            label: Text('#$tag'),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: state.isSaving ? null : () => notifier.confirm(),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('确认保存'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: state.isSaving
                            ? null
                            : () => notifier.changeToMemo(),
                        child: const Text('保存为备忘'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextButton(
                        onPressed: state.isSaving
                            ? null
                            : () => notifier.cancel(),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.typeMeta, required this.parsed});

  final _TypeMeta typeMeta;
  final ParsedInput parsed;

  @override
  Widget build(BuildContext context) {
    final confidence = (parsed.confidence * 100).round();

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: typeMeta.color.withAlpha(22),
            shape: BoxShape.circle,
          ),
          child: Icon(typeMeta.icon, color: typeMeta.color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeMeta.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '识别可信度 $confidence%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 136),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withAlpha(16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeMeta {
  const _TypeMeta(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static _TypeMeta from(ParsedInputType type) => switch (type) {
    ParsedInputType.memo => const _TypeMeta(
      '备忘',
      Icons.edit_note_rounded,
      AppColors.primary,
    ),
    ParsedInputType.todo => const _TypeMeta(
      '待办',
      Icons.check_circle_outline,
      Color(0xFF4A90D9),
    ),
    ParsedInputType.tracker => const _TypeMeta(
      '打卡',
      Icons.directions_run_rounded,
      Color(0xFF7CB342),
    ),
    ParsedInputType.focus => const _TypeMeta(
      '专注',
      Icons.timer_rounded,
      Color(0xFFE67E22),
    ),
    ParsedInputType.expense => const _TypeMeta(
      '消费',
      Icons.payments_rounded,
      Color(0xFFE74C3C),
    ),
    ParsedInputType.body => const _TypeMeta(
      '身体',
      Icons.monitor_weight_rounded,
      Color(0xFF9B59B6),
    ),
    ParsedInputType.sleep => const _TypeMeta(
      '睡眠',
      Icons.bedtime_rounded,
      Color(0xFF5C6BC0),
    ),
  };
}
