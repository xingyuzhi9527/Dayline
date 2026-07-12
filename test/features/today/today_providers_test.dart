import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/today/today_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LocalDatabase _memoryDatabase() {
  return LocalDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('Today queries share a canonical date-only key', () async {
    final db = _memoryDatabase();
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        todayDateKeyProvider.overrideWithValue('2024-01-02'),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(recordsRepositoryProvider)
        .create(
          date: DateTime(2024, 1, 2, 23, 59),
          type: 'memo',
          content: '固定日期',
        );

    final count = await container.read(todayRecordCountProvider.future);

    expect(count, 1);
  });
}
