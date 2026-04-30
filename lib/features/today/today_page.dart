import 'package:flutter/material.dart';

import '../widgets/empty_tab_page.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyTabPage(
      key: ValueKey('today-page'),
      icon: Icons.today_outlined,
      title: 'Today',
    );
  }
}
