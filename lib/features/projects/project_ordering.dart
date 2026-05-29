List<T> reorderProjectSubset<T>({
  required List<T> projects,
  required List<String> orderedIds,
  required String Function(T project) idOf,
}) {
  final orderedSet = orderedIds.toSet();
  if (orderedSet.length != orderedIds.length || orderedSet.length < 2) {
    return projects;
  }

  final projectsById = {for (final project in projects) idOf(project): project};
  final reordered = <T>[];
  for (final id in orderedIds) {
    final project = projectsById[id];
    if (project == null) return projects;
    reordered.add(project);
  }

  final queue = [...reordered];
  return [
    for (final project in projects)
      if (orderedSet.contains(idOf(project))) queue.removeAt(0) else project,
  ];
}
