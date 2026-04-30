import 'package:flutter/material.dart';

import '../widgets/empty_tab_page.dart';

class RecordPage extends StatelessWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyTabPage(
      key: ValueKey('record-page'),
      icon: Icons.add_circle_outline,
      title: 'Record',
    );
  }
}
