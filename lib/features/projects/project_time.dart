/// Shared time rules for project summaries and update rows.
String formatProjectDateTime(DateTime value) {
  final date =
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

DateTime? parseProjectDateTime(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (parsed == null || formatProjectDateTime(parsed) != value) return null;
  return parsed;
}

DateTime? parseProjectEpoch(Object? raw) {
  if (raw is! num || raw <= 0) return null;
  final value = raw.toInt();
  if (value < 1000000000 || value > 4102444800000) return null;
  return DateTime.fromMillisecondsSinceEpoch(value);
}

DateTime? parseProjectUpdateId(String id) {
  final raw = int.tryParse(id.split('-').first);
  if (raw == null || raw <= 0) return null;
  final date = DateTime.fromMicrosecondsSinceEpoch(raw);
  if (date.year < 2000 || date.year > 2100) return null;
  return date;
}

String formatStoredProjectTime({
  Object? timestamp,
  Object? legacyText,
  String? id,
}) {
  final epoch = parseProjectEpoch(timestamp);
  if (epoch != null) return formatProjectDateTime(epoch);
  final parsedText = parseProjectDateTime(legacyText);
  if (parsedText != null) return formatProjectDateTime(parsedText);
  final parsedId = id == null ? null : parseProjectUpdateId(id);
  if (parsedId != null) return formatProjectDateTime(parsedId);
  return '时间未记录';
}
