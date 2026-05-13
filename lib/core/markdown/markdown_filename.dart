enum MarkdownNamingMode { date, dateTitle, datetimeTitle }

class MarkdownFilename {
  const MarkdownFilename._();

  static final _illegal = RegExp(r'[\\/:*?"<>|]');

  static String sanitize(String title) {
    return title
        .replaceAll(_illegal, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String generate(
    DateTime dateTime, {
    String? title,
    MarkdownNamingMode mode = MarkdownNamingMode.datetimeTitle,
  }) {
    final dateStr = _dateStr(dateTime);
    final timeStr = '${_pad(dateTime.hour)}-${_pad(dateTime.minute)}';

    switch (mode) {
      case MarkdownNamingMode.date:
        return '$dateStr.md';
      case MarkdownNamingMode.dateTitle:
        final safe = title != null && title.isNotEmpty
            ? sanitize(title)
            : timeStr;
        return '${dateStr}_$safe.md';
      case MarkdownNamingMode.datetimeTitle:
        final safe = title != null && title.isNotEmpty
            ? sanitize(title)
            : timeStr;
        return '${dateStr}_${timeStr}_$safe.md';
    }
  }

  static String _dateStr(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String monthDir(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}';
  }
}
