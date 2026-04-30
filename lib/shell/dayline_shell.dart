import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';

class DaylineShell extends StatelessWidget {
  const DaylineShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final currentRoute = AppRoute.values[navigationShell.currentIndex];

    return Scaffold(
      appBar: AppBar(title: Text(currentRoute.label)),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          for (final route in AppRoute.values)
            NavigationDestination(
              icon: Icon(route.icon),
              selectedIcon: Icon(route.selectedIcon),
              label: route.label,
            ),
        ],
      ),
    );
  }
}
