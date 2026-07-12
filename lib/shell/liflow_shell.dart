import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';
import '../core/database/local_database.dart';
import '../core/database/repository_providers.dart';
import '../core/markdown/markdown_directory_service.dart';
import '../core/markdown/markdown_storage_service.dart';
import '../core/media/photo_moment_service.dart';
import '../core/theme/app_spacing.dart';
import '../features/markdown_setup/markdown_directory_dialog.dart';
import '../features/monthly_expenses/monthly_expense_markdown_service.dart';
import '../features/projects/project_store.dart';
import '../features/restore/markdown_restore_dialog.dart';
import '../features/restore/markdown_restore_service.dart';
import '../features/timeline/timeline_providers.dart';

class LiflowShell extends ConsumerStatefulWidget {
  const LiflowShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<LiflowShell> createState() => _LiflowShellState();
}

class _LiflowShellState extends ConsumerState<LiflowShell> {
  var _onboardingChecked = false;
  Timer? _backupSnapshotTimer;

  @override
  void initState() {
    super.initState();
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
        final configured = await showMarkdownDirectoryDialog(
          context,
          dirService,
        );
        if (configured && mounted) {
          await _maybeOfferMarkdownRestore(dirService);
          _scheduleBackupSnapshot();
          unawaited(_ensurePreviousMonthExpenseReport(dirService));
        }
        unawaited(
          ref
              .read(photoMomentServiceProvider)
              .syncPrivatePhotoCopiesToVisibleDocuments(),
        );
      } else {
        await MarkdownStorageService(dirService).ensureCoreDirectories();
        _scheduleBackupSnapshot();
        unawaited(_ensurePreviousMonthExpenseReport(dirService));
        unawaited(
          ref
              .read(photoMomentServiceProvider)
              .syncPrivatePhotoCopiesToVisibleDocuments(),
        );
      }
    } catch (_) {
      // Keep startup resilient when storage/config providers are unavailable,
      // such as during lightweight widget tests or transient init failures.
    }
  }

  Future<void> _ensurePreviousMonthExpenseReport(
    MarkdownDirectoryService dirService,
  ) async {
    try {
      await MonthlyExpenseAutoExporter(
        expensesRepository: ref.read(expensesRepositoryProvider),
        settingsRepository: ref.read(appSettingsRepositoryProvider),
        directoryService: dirService,
      ).ensurePreviousMonthReport();
    } catch (_) {
      // Monthly reports are a convenience export; startup should stay resilient.
    }
  }

  Future<void> _maybeOfferMarkdownRestore(
    MarkdownDirectoryService dirService,
  ) async {
    if (!await _isLocalDataEmpty()) return;
    if (!mounted) return;

    final settings = ref.read(appSettingsRepositoryProvider);
    final restoreService = MarkdownRestoreService(
      source: StorageMarkdownRestoreSource(directoryService: dirService),
      database: ref.read(localDatabaseProvider),
      recordsRepository: ref.read(recordsRepositoryProvider),
      settingsRepository: settings,
    );
    final restored = await showMarkdownRestoreDialog(
      context: context,
      restoreService: restoreService,
    );
    if (restored) {
      ref
          .read(dataVersionProvider.notifier)
          .increment(domains: DataDomain.values.toSet());
      await _checkOnboardingAfterRestore();
    }
  }

  Future<bool> _isLocalDataEmpty() async {
    final database = await ref.read(localDatabaseProvider).database;
    for (final table in const [
      'records',
      'todos',
      'trackers',
      'tracker_logs',
      'focus_sessions',
      'expenses',
      'body_logs',
      'daily_reviews',
      'media_attachments',
    ]) {
      final rows = await database.rawQuery('SELECT 1 FROM $table LIMIT 1');
      if (rows.isNotEmpty) return false;
    }

    final row = await ref
        .read(appSettingsRepositoryProvider)
        .findByKey(projectsSettingsKey);
    final value = row?['value'] as String?;
    return value == null || value.trim().isEmpty || value.trim() == '[]';
  }

  Future<void> _checkOnboardingAfterRestore() async {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _backupSnapshotTimer?.cancel();
    super.dispose();
  }

  void _onNavTapped(int index) {
    final currentIndex = widget.navigationShell.currentIndex;
    if (index == currentIndex) {
      widget.navigationShell.goBranch(index, initialLocation: true);
      if (index == 0) {
        ref.read(timelineScrollToLatestSignalProvider.notifier).request();
      }
      return;
    }
    _releaseInputFocus();
    widget.navigationShell.goBranch(index);
    if (index == 0) {
      ref.read(timelineScrollToLatestSignalProvider.notifier).request();
    }
  }

  static void _releaseInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataVersionProvider, (previous, next) {
      if (previous == null || previous == next) return;
      _scheduleBackupSnapshot();
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: false,
      body: widget.navigationShell,
      bottomNavigationBar: _TripleNavBar(
        currentIndex: widget.navigationShell.currentIndex,
        onSelected: _onNavTapped,
      ),
    );
  }

  void _scheduleBackupSnapshot() {
    _backupSnapshotTimer?.cancel();
    _backupSnapshotTimer = Timer(const Duration(milliseconds: 900), () {
      unawaited(_writeBackupSnapshot());
    });
  }

  Future<void> _writeBackupSnapshot() async {
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final dirService = MarkdownDirectoryService(settings);
      if (!await dirService.isConfigured()) return;
      await BackupSnapshotService(
        directoryService: dirService,
        database: ref.read(localDatabaseProvider),
      ).writeSnapshot();
    } catch (_) {
      // Backup snapshots should never interrupt normal app usage.
    }
  }
}

/// Hosts go_router's branch Navigators in a swipeable container.
///
/// The router owns the active branch. The [PageController] is only a visual
/// affordance: a swipe requests a branch change, while URL-driven changes
/// snap the page to the router's current index.
class LiflowBranchNavigatorContainer extends StatefulWidget {
  const LiflowBranchNavigatorContainer({
    required this.navigationShell,
    required this.children,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  State<LiflowBranchNavigatorContainer> createState() =>
      _LiflowBranchNavigatorContainerState();
}

class _LiflowBranchNavigatorContainerState
    extends State<LiflowBranchNavigatorContainer> {
  late final PageController _pageController;
  var _lastRouterIndex = 0;

  @override
  void initState() {
    super.initState();
    _lastRouterIndex = widget.navigationShell.currentIndex;
    _pageController = PageController(initialPage: _lastRouterIndex);
  }

  @override
  void didUpdateWidget(covariant LiflowBranchNavigatorContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = widget.navigationShell.currentIndex;
    if (nextIndex != _lastRouterIndex) {
      _lastRouterIndex = nextIndex;
      _syncToBranch(nextIndex);
    }
  }

  void _syncToBranch(int index) {
    if (!mounted) return;
    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncToBranch(index);
      });
      return;
    }
    final currentPage = _pageController.page;
    if (currentPage == null || (currentPage - index).abs() < 0.001) return;
    // The router is authoritative. A route change may arrive while a user
    // swipe is still settling, so snap the visual container to the new branch
    // instead of starting a competing animation.
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    if (index != widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(index);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.navigationShell.currentIndex;
    return PageView(
      key: const ValueKey('liflow-branch-page-view'),
      controller: _pageController,
      onPageChanged: _onPageChanged,
      physics: const PageScrollPhysics(),
      children: [
        for (var i = 0; i < widget.children.length; i++)
          TickerMode(enabled: i == activeIndex, child: widget.children[i]),
      ],
    );
  }
}

class _TripleNavBar extends StatelessWidget {
  const _TripleNavBar({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('liflow-bottom-navigation'),
      decoration: BoxDecoration(
        color: colorScheme.surface.withAlpha(242),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withAlpha(20),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
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
                            ? colorScheme.primary.withAlpha(20)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected ? route.selectedIcon : route.icon,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        size: iconSize,
                      ),
                    )
                  else
                    Icon(
                      selected ? route.selectedIcon : route.icon,
                      color: color,
                      size: iconSize,
                    ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    route.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
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
