import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/features/projects/project_time.dart';

void main() {
  test('formats complete local date and time with zero padding', () {
    expect(
      formatProjectDateTime(DateTime(2026, 9, 6, 5, 4)),
      '2026-09-06 05:04',
    );
  });

  test('uses reliable timestamp before complete legacy text', () {
    final value = DateTime(2026, 9, 26, 12, 5);
    expect(
      formatStoredProjectTime(
        timestamp: value.millisecondsSinceEpoch,
        legacyText: '今天 12:05',
      ),
      '2026-09-26 12:05',
    );
    expect(formatStoredProjectTime(legacyText: '今天 12:05'), '时间未记录');
  });

  test('converts project id microseconds without using current time', () {
    final value = DateTime(2026, 9, 26, 12, 5);
    final id = '${value.microsecondsSinceEpoch}-update';
    expect(formatStoredProjectTime(id: id), '2026-09-26 12:05');
    expect(formatStoredProjectTime(id: 'not-a-date'), '时间未记录');
  });
}
