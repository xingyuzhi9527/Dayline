import 'package:flutter/material.dart';

enum AppRoute {
  today(
    path: '/today',
    label: '今日',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
  ),
  timeline(
    path: '/timeline',
    label: '时间线',
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline,
  ),
  record(
    path: '/record',
    label: '记录',
    icon: Icons.add_circle_outline,
    selectedIcon: Icons.add_circle,
  ),
  review(
    path: '/review',
    label: '复盘',
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
