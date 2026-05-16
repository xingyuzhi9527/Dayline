String buildDailyReviewSection({
  required String kept,
  required String adjust,
  required String nextAction,
}) {
  return '## 晚间复盘\n'
      '\n'
      '### 今天值得保留的是\n'
      '\n'
      '${_reviewValue(kept)}\n'
      '\n'
      '### 今天可以调整的是\n'
      '\n'
      '${_reviewValue(adjust)}\n'
      '\n'
      '### 明天最小行动是\n'
      '\n'
      '${_reviewValue(nextAction)}';
}

String upsertDailyReviewSection(
  String markdown, {
  required String kept,
  required String adjust,
  required String nextAction,
}) {
  final section = buildDailyReviewSection(
    kept: kept,
    adjust: adjust,
    nextAction: nextAction,
  );

  const reviewHeading = '## 晚间复盘';
  final start = markdown.indexOf(reviewHeading);
  if (start != -1) {
    final nextHeading = markdown.indexOf('\n## ', start + reviewHeading.length);
    final before = markdown.substring(0, start).trimRight();
    final after = nextHeading == -1
        ? ''
        : markdown.substring(nextHeading).trimLeft();
    return _joinMarkdownParts(before, section, after);
  }

  const rawIndexHeading = '## 原始记录索引';
  final rawIndexStart = markdown.indexOf(rawIndexHeading);
  if (rawIndexStart != -1) {
    final before = markdown.substring(0, rawIndexStart).trimRight();
    final after = markdown.substring(rawIndexStart).trimLeft();
    return _joinMarkdownParts(before, section, after);
  }

  return '${markdown.trimRight()}\n\n$section\n';
}

String _reviewValue(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '...' : trimmed;
}

String _joinMarkdownParts(String before, String section, String after) {
  if (after.isEmpty) return '$before\n\n$section\n';
  if (before.isEmpty) return '$section\n\n$after';
  return '$before\n\n$section\n\n$after';
}
