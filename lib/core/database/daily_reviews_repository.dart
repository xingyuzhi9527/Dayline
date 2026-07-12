import '../database/local_database.dart';
import '../database/repositories.dart';

class DailyReviewsRepository extends Repository {
  DailyReviewsRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'daily_reviews');

  Future<int> create({
    required String date,
    String kept = '',
    String adjust = '',
    String nextAction = '',
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'date': date,
        'kept': kept,
        'adjust': adjust,
        'next_action': nextAction,
      }, createdAt: createdAt),
    );
  }

  Future<DatabaseRow?> findByDate(String date) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      tableName,
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<int> updateReview(
    String date, {
    required String kept,
    required String adjust,
    required String nextAction,
    DateTime? updatedAt,
  }) {
    final now = updatedAt ?? DateTime.now();
    return localDatabase.executor.then(
      (db) => db.update(
        tableName,
        {
          'kept': kept,
          'adjust': adjust,
          'next_action': nextAction,
          'updated_at': timestamp(now),
        },
        where: 'date = ?',
        whereArgs: [date],
      ),
    );
  }

  Future<int> upsert({
    required String date,
    required String kept,
    required String adjust,
    required String nextAction,
  }) async {
    final existing = await findByDate(date);
    if (existing != null) {
      return updateReview(
        date,
        kept: kept,
        adjust: adjust,
        nextAction: nextAction,
      );
    }
    return create(
      date: date,
      kept: kept,
      adjust: adjust,
      nextAction: nextAction,
    );
  }
}
