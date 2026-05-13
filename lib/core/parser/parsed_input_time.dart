DateTime? parsedInputTimeToDateTime(DateTime anchorDate, String? time) {
  if (time == null || time.trim().isEmpty) return null;

  final parts = time.split(':');
  if (parts.length != 2) return null;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;

  return DateTime(
    anchorDate.year,
    anchorDate.month,
    anchorDate.day,
    hour,
    minute,
  );
}
