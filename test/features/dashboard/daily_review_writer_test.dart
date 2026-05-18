import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/daily_reviews_repository.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/dashboard/daily_review_writer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('saving review for yesterday writes yesterday review only', () async {
    final database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final today = DateTime.now();
    final yesterday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));

    await saveDailyReviewForDate(
      container,
      date: yesterday,
      kept: '保留昨天的节奏',
      adjust: '少拖延',
      nextAction: '先写一段',
    );

    final reviews = DailyReviewsRepository(database);
    expect(await reviews.findByDate(dateKey(yesterday)), isNotNull);
    expect(await reviews.findByDate(dateKey(today)), isNull);
  });
}
