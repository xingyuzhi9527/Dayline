import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import 'widgets/review_cards.dart';

class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dataVersionProvider);

    return SafeArea(
      child: Column(
        key: const ValueKey('review-page'),
        children: const [
          ReviewDateBar(),
          Expanded(child: ReviewBody()),
        ],
      ),
    );
  }
}
