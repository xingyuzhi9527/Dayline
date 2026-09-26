import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:liflow_app/core/stt/stt_providers.dart';
import 'package:liflow_app/features/flash_record/flash_record_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('keeps the typed text visible when saving fails', (tester) async {
    final database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final records = _FailingRecordsRepository(database);
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          recordsRepositoryProvider.overrideWithValue(records),
          sttEngineProvider.overrideWithValue(_UnavailableSttEngine()),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('collapsed-intent-pill')));
    await tester.pump(const Duration(milliseconds: 550));

    const input = '这条记录保存失败';
    await tester.enterText(
      find.byKey(const ValueKey('record-text-input')),
      input,
    );
    await tester.tap(find.byKey(const ValueKey('record-text-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 8));

    final inputField = tester.widget<TextField>(
      find.byKey(const ValueKey('record-text-input')),
    );
    expect(inputField.controller?.text, input);
    // Scope this regression to the field: the compact input keeps the draft
    // mounted while the notifier reports the failure.
    expect(find.byKey(const ValueKey('record-text-input')), findsOneWidget);
  });
}

class _FailingRecordsRepository extends RecordsRepository {
  _FailingRecordsRepository(super.localDatabase);

  @override
  Future<int> create({
    required DateTime date,
    required String type,
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? createdAt,
  }) async {
    throw StateError('injected save failure');
  }
}

class _UnavailableSttEngine implements SttEngine {
  @override
  Future<SttAvailability> initialize() async {
    return const SttAvailability.unavailable('offline');
  }

  @override
  Future<SttListenSession> startListening({bool transcribe = true}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}
}
