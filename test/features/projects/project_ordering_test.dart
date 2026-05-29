import 'package:liflow_app/features/projects/project_ordering.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

void main() {
  test(
    'reorders visible project ids while keeping hidden projects in place',
    () {
      final projects = ['active-a', 'hidden', 'active-b', 'active-c'];

      final result = reorderProjectSubset(
        projects: projects,
        orderedIds: const ['active-b', 'active-a', 'active-c'],
        idOf: (project) => project,
      );

      expect(result, ['active-b', 'hidden', 'active-a', 'active-c']);
    },
  );

  test('ignores duplicate or unknown project ids', () {
    final projects = ['a', 'b', 'c'];

    expect(
      reorderProjectSubset(
        projects: projects,
        orderedIds: const ['b', 'b'],
        idOf: (project) => project,
      ),
      same(projects),
    );
    expect(
      reorderProjectSubset(
        projects: projects,
        orderedIds: const ['b', 'missing'],
        idOf: (project) => project,
      ),
      same(projects),
    );
  });
}
