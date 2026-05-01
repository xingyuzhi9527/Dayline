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
          onPressed: () {},
          icon: const Icon(Icons.menu_rounded),
        ),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: _DiaryNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

class _DiaryNavigationBar extends StatelessWidget {
  const _DiaryNavigationBar({
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
                  child: _DiaryNavigationItem(
                    route: AppRoute.values[i],
                    selected: i == currentIndex,
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

class _DiaryNavigationItem extends StatelessWidget {
  const _DiaryNavigationItem({
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final AppRoute route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    final theme = Theme.of(context);

    return Semantics(
      label: route.label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: route.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            scale: selected ? 1.08 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? route.selectedIcon : route.icon,
                  color: color.withAlpha(selected ? 255 : 150),
                  size: 26,
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
    );
  }
}
