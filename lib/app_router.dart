import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/flash_record/flash_record_page.dart';
import 'features/projects/projects_page.dart';
import 'features/search/presentation/search_page.dart';
import 'features/timeline/timeline_page.dart';
import 'shell/liflow_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoute.record.path,
    redirect: (context, state) {
      if (state.uri.path == '/') {
        return AppRoute.record.path;
      }

      return null;
    },
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: (context, navigationShell, children) {
          return LiflowBranchNavigatorContainer(
            navigationShell: navigationShell,
            children: children,
          );
        },
        builder: (context, state, navigationShell) {
          return LiflowShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.line.path,
                name: AppRoute.line.name,
                builder: (context, state) => const TimelinePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.record.path,
                name: AppRoute.record.name,
                builder: (context, state) => const FlashRecordPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.projects.path,
                name: AppRoute.projects.name,
                builder: (context, state) => const ProjectsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.dashboard.path,
                name: AppRoute.dashboard.name,
                builder: (context, state) => const DashboardPage(),
                routes: [
                  GoRoute(
                    path: 'search',
                    name: 'search',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SearchPage(),
                    routes: [
                      GoRoute(
                        path: 'record/:recordId',
                        name: 'search-record',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) {
                          final recordId = int.tryParse(
                            state.pathParameters['recordId'] ?? '',
                          );
                          final date = _parseDate(
                            state.uri.queryParameters['date'],
                          );
                          return TimelinePage(
                            initialDate: date,
                            targetRecordId: recordId,
                            standalone: true,
                          );
                        },
                      ),
                      GoRoute(
                        path: 'project/:projectId',
                        name: 'search-project',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => ProjectsPage(
                          initialProjectId: state.pathParameters['projectId'],
                          standalone: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);

  return router;
});

DateTime? _parseDate(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}
