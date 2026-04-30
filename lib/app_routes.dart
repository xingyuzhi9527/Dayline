import 'package:flutter/material.dart';

enum AppRoute {
  today(
    path: '/today',
    label: 'Today',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
  ),
  record(
    path: '/record',
    label: 'Record',
    icon: Icons.add_circle_outline,
    selectedIcon: Icons.add_circle,
  ),
  timeline(
    path: '/timeline',
    label: 'Timeline',
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline,
  ),
  review(
    path: '/review',
    label: 'Review',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
  );

  const AppRoute({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
