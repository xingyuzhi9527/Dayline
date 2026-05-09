import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

class DaylineShell extends StatelessWidget {
  const DaylineShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(
          '我的日记',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        leadingWidth: 64,
        leading: IconButton(
          tooltip: '菜单',
          onPressed: _releaseInputFocus,
          icon: const Icon(Icons.menu_rounded),
        ),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: _releaseInputFocus,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: _TripleNavBar(
        currentIndex: navigationShell.currentIndex,
        onSelected: (index) {
          _releaseInputFocus();
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }

  static void _releaseInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}

class _TripleNavBar extends StatelessWidget {
  const _TripleNavBar({
    required this.currentIndex,
    required this.onSelected,
  });

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
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
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
