import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import 'record_notifier.dart';
import 'widgets/parser_preview_card.dart';
import 'widgets/quick_input_bar.dart';

class RecordPage extends ConsumerWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordNotifierProvider);

    return SafeArea(
      child: ListView(
        key: const ValueKey('record-page'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.lg,
          AppSpacing.containerMargin,
          AppSpacing.xl,
        ),
        children: [
          if (state.parsedInput == null) ...[
            Text('新记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            const QuickInputBar(
              placeholder: '你正在做什么？例如：9点半 跑步 30分钟 #健康',
              minLines: 4,
            ),
          ] else
            const ParserPreviewCard(),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorBanner(message: state.errorMessage!),
          ],
          if (state.isSaving) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
