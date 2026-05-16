import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/focus/focus_session_page.dart';

void main() {
  testWidgets('focus session saves duration and note when completed', (
    tester,
  ) async {
    final fakeRepo = _FakeFocusSessionsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusSessionsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: FocusSessionPage(
            initialStartedAt: DateTime.now().subtract(
              const Duration(minutes: 5, seconds: 2),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('focus-session-note')),
      '修改 app 专注功能',
    );
    await tester.tap(find.byKey(const ValueKey('focus-session-complete')));
    await tester.pumpAndSettle();

    expect(fakeRepo.createdCount, 1);
    expect(fakeRepo.lastDurationMinutes, greaterThanOrEqualTo(5));
    expect(fakeRepo.lastNote, '修改 app 专注功能');
  });
}

class _FakeFocusSessionsRepository implements FocusSessionsRepository {
  int createdCount = 0;
  int? lastDurationMinutes;
  String? lastNote;

  @override
  Future<int> create({
    required DateTime date,
    required DateTime startedAt,
    required int durationMinutes,
    DateTime? endedAt,
    String? note,
    DateTime? createdAt,
  }) async {
    createdCount += 1;
    lastDurationMinutes = durationMinutes;
    lastNote = note;
    return createdCount;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
