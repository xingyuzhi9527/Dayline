import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import 'widgets/timeline_list.dart';

class TimelinePage extends ConsumerWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dataVersionProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          key: const ValueKey('timeline-page'),
          children: [
            const TimelineDateBar(),
            const Expanded(child: TimelineBody()),
          ],
        ),
      ),
    );
  }
}
