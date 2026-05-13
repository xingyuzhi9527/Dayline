import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:liflow_app/core/stt/stt_providers.dart';
import 'package:liflow_app/features/flash_record/flash_record_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'given a parsed time, when saving text, then created_at follows that time',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final today = DateTime.now();

      await container
          .read(flashRecordProvider.notifier)
          .saveAsText('08:05 出门');

      final records = await container.read(recordsRepositoryProvider).findByDate(
        today,
      );

      expect(records, hasLength(1));
      expect(records.single['time'], '08:05');

      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        records.single['created_at'] as int,
      );
      expect(createdAt.hour, 8);
      expect(createdAt.minute, 5);
    },
  );
}

class _FakeSttEngine implements SttEngine {
  @override
  Future<SttAvailability> initialize() async =>
      const SttAvailability.unavailable('offline');

  @override
  Future<SttListenSession> startListening() {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}
}
