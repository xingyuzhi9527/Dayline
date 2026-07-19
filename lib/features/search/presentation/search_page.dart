import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/search_providers.dart';
import '../data/search_index_service.dart';
import '../domain/search_models.dart';
import 'widgets/search_filter_bar.dart';
import 'widgets/search_result_tile.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(searchFormProvider).text,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchFormProvider);
    final results = ref.watch(searchResultsProvider);
    final warmup = ref.watch(searchIndexWarmupProvider);
    ref.listen<AsyncValue<SearchIndexState>>(searchIndexWarmupProvider, (
      previous,
      next,
    ) {
      if (next is AsyncData<SearchIndexState> &&
          previous is! AsyncData<SearchIndexState>) {
        Future.microtask(() {
          if (mounted) ref.invalidate(searchResultsProvider);
        });
      }
    });

    final warmupState = switch (warmup) {
      AsyncData(value: final value) => value,
      _ => null,
    };
    final preparingIndex = warmup is AsyncLoading<SearchIndexState>;
    final fallback =
        warmupState?.backend == 'like_fallback' ||
        warmupState?.status == 'failed';

    return Scaffold(
      key: const ValueKey('search-page'),
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回复盘',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('搜索记录与项目'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                key: const ValueKey('search-input'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: ref.read(searchFormProvider.notifier).setText,
                decoration: InputDecoration(
                  hintText: '搜索',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.text.isEmpty
                      ? null
                      : SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton(
                            key: const ValueKey('search-clear'),
                            tooltip: '清除搜索词',
                            onPressed: () {
                              _controller.clear();
                              ref.read(searchFormProvider.notifier).clearText();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                ),
              ),
            ),
            SearchFilterBar(
              filters: query.filters,
              onChanged: (filters) =>
                  ref.read(searchFormProvider.notifier).setFilters(filters),
            ),
            Expanded(
              child: _SearchBody(
                query: query,
                results: results,
                preparingIndex: preparingIndex,
                fallback: fallback,
                scrollController: _scrollController,
                onRetry: () => ref.invalidate(searchResultsProvider),
                onOpen: _openResult,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openResult(SearchResultItem item) {
    if (item.kind == SearchResultKind.record) {
      final recordId = item.recordId;
      final date = item.date;
      if (recordId == null || date == null) return;
      context.go(
        '/dashboard/search/record/$recordId?date=${Uri.encodeQueryComponent(date)}',
      );
      return;
    }
    final projectId = item.projectId;
    if (projectId == null) return;
    context.go('/dashboard/search/project/${Uri.encodeComponent(projectId)}');
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.query,
    required this.results,
    required this.preparingIndex,
    required this.fallback,
    required this.scrollController,
    required this.onRetry,
    required this.onOpen,
  });

  final SearchQuery query;
  final AsyncValue<SearchResultPage> results;
  final bool preparingIndex;
  final bool fallback;
  final ScrollController scrollController;
  final VoidCallback onRetry;
  final ValueChanged<SearchResultItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _CenteredState(
        icon: Icons.manage_search_rounded,
        title: '搜索记录与项目',
      );
    }
    return switch (results) {
      AsyncLoading() => const _SearchSkeleton(),
      AsyncError(error: final error) => _SearchError(
        error: error,
        onRetry: onRetry,
      ),
      AsyncData(value: final page) when page.items.isEmpty => Column(
        children: [
          if (preparingIndex || page.indexBuilding)
            const _StatusBanner(icon: Icons.sync_rounded, text: '正在准备本地搜索'),
          const Expanded(
            child: _CenteredState(
              icon: Icons.search_off_rounded,
              title: '没有找到匹配内容',
            ),
          ),
        ],
      ),
      AsyncData(value: final page) => _ResultList(
        page: page,
        preparingIndex: preparingIndex,
        fallback: fallback,
        scrollController: scrollController,
        onOpen: onOpen,
      ),
    };
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.page,
    required this.preparingIndex,
    required this.fallback,
    required this.scrollController,
    required this.onOpen,
  });

  final SearchResultPage page;
  final bool preparingIndex;
  final bool fallback;
  final ScrollController scrollController;
  final ValueChanged<SearchResultItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('search-results-scroll'),
      controller: scrollController,
      children: [
        if (preparingIndex || page.indexBuilding)
          const _StatusBanner(icon: Icons.sync_rounded, text: '正在准备本地搜索')
        else if (fallback)
          const _StatusBanner(icon: Icons.shield_outlined, text: '当前使用兼容搜索'),
        for (var index = 0; index < page.items.length; index++) ...[
          SearchResultTile(
            item: page.items[index],
            onTap: () => onOpen(page.items[index]),
          ),
          if (index != page.items.length - 1)
            const Divider(height: 1, indent: 68),
        ],
        if (page.hasMore)
          const _StatusBanner(
            icon: Icons.filter_list_rounded,
            text: '仅显示前 100 条结果',
          ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        color: theme.colorScheme.primary.withAlpha(12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(130),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('搜索暂时不可用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.72,
                    child: Container(height: 14, color: color),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FractionallySizedBox(
                    widthFactor: 0.42,
                    child: Container(height: 10, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
