import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/record/record_notifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'quick input rolls back all expense rows when one insert fails',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final expenses = _FailSecondExpenseOnceRepository(database);
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          expensesRepositoryProvider.overrideWithValue(expenses),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      const input = '午饭35元 咖啡18元';
      final notifier = container.read(recordNotifierProvider.notifier);

      expect(await notifier.saveInput(input), isFalse);
      expect(await expenses.findByDate(DateTime.now()), isEmpty);

      expect(await notifier.saveInput(input), isTrue);
      final saved = await expenses.findByDate(DateTime.now());
      expect(saved, hasLength(2));
      expect(saved.map((row) => row['amount']), [35.0, 18.0]);
    },
  );
}

class _FailSecondExpenseOnceRepository extends ExpensesRepository {
  _FailSecondExpenseOnceRepository(super.localDatabase);

  var createCount = 0;
  var _shouldFail = true;

  @override
  Future<int> create({
    required DateTime date,
    required double amount,
    required String category,
    String? note,
    String currency = 'CNY',
    DateTime? createdAt,
  }) async {
    createCount += 1;
    final id = await super.create(
      date: date,
      amount: amount,
      category: category,
      note: note,
      currency: currency,
      createdAt: createdAt,
    );
    if (_shouldFail && createCount == 2) {
      _shouldFail = false;
      throw StateError('injected second expense failure');
    }
    return id;
  }
}
