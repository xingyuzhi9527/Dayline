import 'package:flutter/material.dart';

import '../widgets/empty_tab_page.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyTabPage(
      key: ValueKey('timeline-page'),
      icon: Icons.timeline_outlined,
      title: 'Timeline',
    );
  }
}
