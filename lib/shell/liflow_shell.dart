import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';
import '../core/database/repository_providers.dart';
import '../core/markdown/markdown_directory_service.dart';
import '../core/markdown/markdown_storage_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/flash_record/flash_record_page.dart';
import '../features/markdown_setup/markdown_directory_dialog.dart';
import '../features/timeline/timeline_page.dart';
import '../features/timeline/timeline_providers.dart';

class LiflowShell extends ConsumerStatefulWidget {
  const LiflowShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<LiflowShell> createState() => _LiflowShellState();
}

class _LiflowShellState extends ConsumerState<LiflowShell> {
  late final PageController _pageController;
  var _currentIndex = 1;

  var _onboardingChecked = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell.currentIndex;
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboarding());
  }

  Future<void> _checkOnboarding() async {
    if (_onboardingChecked) return;
    _onboardingChecked = true;
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final dirService = MarkdownDirectoryService(settings);
      final treeUri = await dirService.getTreeRootUri();
      final lostTreeAccess =
          treeUri != null &&
          treeUri.isNotEmpty &&
          !await MarkdownStorageService(dirService).hasTreeAccess(treeUri);
      final needsAndroidVisibleFolder =
          Platform.isAndroid && (treeUri == null || treeUri.isEmpty);
      if (!await dirService.isConfigured() ||
          needsAndroidVisibleFolder ||
          lostTreeAccess) {
        if (!mounted) return;
        await showMarkdownDirectoryDialog(context, dirService);
      }
    } catch (_) {
      // Keep startup resilient when storage/config providers are unavailable,
      // such as during lightweight widget tests or transient init failures.
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  var _fromNavTap = false;

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    if (_fromNavTap) {
      _fromNavTap = false;
      return;
    }
    setState(() => _currentIndex = index);
    _releaseInputFocus();
    widget.navigationShell.goBranch(index);
    if (index == 0) {
      ref.read(timelineScrollToLatestSignalProvider.notifier).request();
    }
  }

  void _onNavTapped(int index) {
    if (index == _currentIndex) {
      widget.navigationShell.goBranch(index, initialLocation: true);
      if (index == 0) {
        ref.read(timelineScrollToLatestSignalProvider.notifier).request();
      }
      return;
    }
    setState(() => _currentIndex = index);
    _releaseInputFocus();
    widget.navigationShell.goBranch(index);
    if (index == 0) {
      ref.read(timelineScrollToLatestSignalProvider.notifier).request();
    }
    _fromNavTap = true;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  static void _releaseInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: false,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const PageScrollPhysics(),
        children: [
          for (var i = 0; i < 3; i++)
            TickerMode(enabled: i == _currentIndex, child: _pageWidget(i)),
        ],
      ),
      bottomNavigationBar: _TripleNavBar(
        currentIndex: _currentIndex,
        onSelected: _onNavTapped,
      ),
    );
  }

  Widget _pageWidget(int index) => switch (index) {
    0 => const TimelinePage(),
    1 => const FlashRecordPage(),
    _ => const DashboardPage(),
  };
}

class _TripleNavBar extends StatelessWidget {
  const _TripleNavBar({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withAlpha(242),
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.softShadow,
            offset: Offset(0, -4),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < AppRoute.values.length; i++)
                Expanded(
                  child: _NavItem(
                    route: AppRoute.values[i],
                    selected: i == currentIndex,
                    isCenter: i == 1,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.route,
    required this.selected,
    required this.isCenter,
    required this.onTap,
  });

  final AppRoute route;
  final bool selected;
  final bool isCenter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    final theme = Theme.of(context);
    final iconSize = isCenter && selected ? 28.0 : 24.0;
    final scale = isCenter && selected ? 1.12 : 1.0;

    return Semantics(
      label: route.label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: route.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 160),
              scale: scale,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isCenter)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withAlpha(20)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected ? route.selectedIcon : route.icon,
                        color: selected
                            ? AppColors.primary
                            : AppColors.muted.withAlpha(160),
                        size: iconSize,
                      ),
                    )
                  else
                    Icon(
                      selected ? route.selectedIcon : route.icon,
                      color: color.withAlpha(selected ? 255 : 150),
                      size: iconSize,
                    ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    route.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color.withAlpha(selected ? 255 : 150),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
