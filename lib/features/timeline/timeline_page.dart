import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import 'timeline_providers.dart';
import 'widgets/timeline_list.dart';

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({
    this.initialDate,
    this.targetRecordId,
    this.standalone = false,
    super.key,
  });

  final DateTime? initialDate;
  final int? targetRecordId;
  final bool standalone;

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(timelineDateProvider.notifier).setDate(initialDate);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataVersionProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          key: const ValueKey('timeline-page'),
          children: [
            TimelineDateBar(
              onBack: widget.standalone
                  ? () => Navigator.of(context).maybePop()
                  : null,
            ),
            Expanded(
              child: TimelineBody(targetRecordId: widget.targetRecordId),
            ),
          ],
        ),
      ),
    );
  }
}
