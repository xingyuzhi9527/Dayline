import 'package:flutter/material.dart';

enum AppRoute {
  line(
    path: '/line',
    label: '线',
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline,
  ),
  record(
    path: '/record',
    label: '记',
    icon: Icons.mic_none_outlined,
    selectedIcon: Icons.mic,
  ),
  dashboard(
    path: '/dashboard',
    label: '盘',
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
