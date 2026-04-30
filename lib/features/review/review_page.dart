import 'package:flutter/material.dart';

import '../widgets/empty_tab_page.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyTabPage(
      key: ValueKey('review-page'),
      icon: Icons.insights_outlined,
      title: 'Review',
    );
  }
}
