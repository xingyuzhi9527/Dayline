import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/local_database.dart';
import '../../core/database/repository_providers.dart';
import '../../core/parser/expense_line_item.dart';
import '../../core/parser/lui_lite_parser.dart';
import '../../core/parser/parsed_input_time.dart';
import '../dashboard/daily_note_draft.dart';
import '../monthly_expenses/monthly_expense_report_sync.dart';
import 'record_state.dart';

final recordNotifierProvider = NotifierProvider<RecordNotifier, RecordState>(
  RecordNotifier.new,
);

class RecordNotifier extends Notifier<RecordState> {
  @override
  RecordState build() => const RecordState();

  void updateInput(String text) {
    state = state.copyWith(inputText: text, errorMessage: null);
  }

  void submit([String? rawText]) {
    final text = (rawText ?? state.inputText).trim();
    if (text.isEmpty) return;

    final parsed = LuiLiteParser.parse(text);
    state = state.copyWith(
      inputText: text,
      parsedInput: parsed,
      errorMessage: null,
    );
  }

  Future<bool> saveInput(String text, {bool asMemo = false}) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return false;

    final parsed = LuiLiteParser.parse(trimmedText);
    state = state.copyWith(
      inputText: trimmedText,
      parsedInput: parsed,
      isSaving: true,
      errorMessage: null,
    );

    try {
      await ref
          .read(localDatabaseProvider)
          .transaction(() => _persist(parsed, asMemo: asMemo));
      await ensureDailyDraftAfterActivity(ref, DateTime.now());
      await _refreshMonthlyReportIfNeeded(parsed, asMemo: asMemo);
      ref
          .read(dataVersionProvider.notifier)
          .increment(domains: _domainsForParsedInput(parsed, asMemo: asMemo));
      state = const RecordState();
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
      return false;
    }
  }

  void updateParsedType(ParsedInputType type) {
    final parsed = state.parsedInput;
    if (parsed == null || parsed.type == type) return;

    state = state.copyWith(
      parsedInput: parsed.copyWith(type: type, confidence: 1),
      errorMessage: null,
    );
  }

  void updateParsedText(String text) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      state = state.copyWith(inputText: text, errorMessage: null);
      return;
    }

    final parsed = LuiLiteParser.parse(trimmedText);
    state = state.copyWith(
      inputText: text,
      parsedInput: parsed,
      errorMessage: null,
    );
  }

  void updateParsedTags(List<String> tags) {
    final parsed = state.parsedInput;
    if (parsed == null) return;

    state = state.copyWith(
      parsedInput: parsed.copyWith(tags: _normalizeTags(tags)),
      errorMessage: null,
    );
  }

  Future<void> confirm() => _save(asMemo: false);

  Future<void> changeToMemo() => _save(asMemo: true);

  void cancel() {
    state = state.copyWith(parsedInput: null, errorMessage: null);
  }

  Future<void> _save({required bool asMemo}) async {
    final parsed = state.parsedInput;
    if (parsed == null) return;

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      await ref
          .read(localDatabaseProvider)
          .transaction(() => _persist(parsed, asMemo: asMemo));
      await ensureDailyDraftAfterActivity(ref, DateTime.now());
      await _refreshMonthlyReportIfNeeded(parsed, asMemo: asMemo);
      ref
          .read(dataVersionProvider.notifier)
          .increment(domains: _domainsForParsedInput(parsed, asMemo: asMemo));
      state = const RecordState();
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
    }
  }

  Future<void> _persist(ParsedInput parsed, {required bool asMemo}) async {
    final now = DateTime.now();
    final createdAt = parsedInputTimeToDateTime(now, parsed.time) ?? now;

    if (asMemo) {
      await ref
          .read(recordsRepositoryProvider)
          .create(
            date: now,
            type: 'memo',
            content: parsed.content,
            time: parsed.time,
            tags: parsed.tags,
            metadata: parsed.metadata,
            createdAt: createdAt,
          );
      return;
    }

    switch (parsed.type) {
      case ParsedInputType.memo:
        await ref
            .read(recordsRepositoryProvider)
            .create(
              date: now,
              type: 'memo',
              content: parsed.content,
              time: parsed.time,
              tags: parsed.tags,
              metadata: parsed.metadata,
              createdAt: createdAt,
            );

      case ParsedInputType.todo:
        await ref
            .read(todosRepositoryProvider)
            .create(
              date: now,
              title: parsed.content,
              dueTime: parsed.time,
              createdAt: createdAt,
            );

      case ParsedInputType.focus:
        final durationMinutes =
            (parsed.metadata['durationMinutes'] as int?) ?? 0;
        await ref
            .read(focusSessionsRepositoryProvider)
            .create(
              date: now,
              startedAt: createdAt,
              durationMinutes: durationMinutes,
              note: parsed.content,
              createdAt: createdAt,
            );

      case ParsedInputType.expense:
        final items = validExpenseLineItemsFromMetadata(parsed.metadata);
        if (items.isEmpty) {
          throw StateError('消费金额需要至少一笔有效数字。');
        }
        final fallbackCategory = parsed.tags.isNotEmpty
            ? parsed.tags.first
            : 'other';
        final note = parsed.content.trim();
        for (final item in items) {
          await ref
              .read(expensesRepositoryProvider)
              .create(
                date: now,
                amount: item.amount,
                category: item.name.isNotEmpty ? item.name : fallbackCategory,
                note: items.length == 1 ? note : null,
                createdAt: createdAt,
              );
        }
      case ParsedInputType.body:
        final value = (parsed.metadata['value'] as num?)?.toDouble() ?? 0.0;
        final metric = (parsed.metadata['metric'] as String?) ?? 'weight';
        await ref
            .read(bodyLogsRepositoryProvider)
            .create(
              date: now,
              metric: metric,
              value: value,
              note: parsed.content,
              createdAt: createdAt,
            );

      case ParsedInputType.sleep:
        await ref
            .read(recordsRepositoryProvider)
            .create(
              date: now,
              type: 'sleep',
              content: parsed.content,
              time: parsed.time,
              tags: parsed.tags,
              metadata: parsed.metadata,
              createdAt: createdAt,
            );

      case ParsedInputType.mood:
        await ref
            .read(recordsRepositoryProvider)
            .create(
              date: now,
              type: 'mood',
              content: parsed.content,
              time: parsed.time,
              tags: parsed.tags,
              metadata: parsed.metadata,
              createdAt: createdAt,
            );

      case ParsedInputType.tracker:
        await _saveTrackerLog(parsed, now, createdAt);
    }
  }

  Future<void> _refreshMonthlyReportIfNeeded(
    ParsedInput parsed, {
    required bool asMemo,
  }) async {
    if (asMemo || parsed.type != ParsedInputType.expense) return;
    try {
      await syncMonthlyExpenseReportForDate(
        settingsRepository: ref.read(appSettingsRepositoryProvider),
        expensesRepository: ref.read(expensesRepositoryProvider),
        date: DateTime.now(),
        generatedAt: DateTime.now(),
      );
    } catch (_) {
      // The expense rows are authoritative; Markdown is a derived view.
    }
  }

  Set<DataDomain> _domainsForParsedInput(
    ParsedInput parsed, {
    required bool asMemo,
  }) {
    if (asMemo) return const {DataDomain.records};

    return switch (parsed.type) {
      ParsedInputType.memo ||
      ParsedInputType.sleep ||
      ParsedInputType.mood => const {DataDomain.records},
      ParsedInputType.todo => const {DataDomain.todos},
      ParsedInputType.focus => const {DataDomain.focus},
      ParsedInputType.expense => const {DataDomain.expenses},
      ParsedInputType.body => const {DataDomain.bodyLogs},
      ParsedInputType.tracker => const {
        DataDomain.trackerLogs,
        DataDomain.trackers,
      },
    };
  }

  Future<void> _saveTrackerLog(
    ParsedInput parsed,
    DateTime now,
    DateTime createdAt,
  ) async {
    final trackerName = parsed.content.isNotEmpty
        ? parsed.content
        : (parsed.tags.isNotEmpty ? parsed.tags.first : 'tracker');
    final durationMinutes = parsed.metadata['durationMinutes'] as int?;
    final value = durationMinutes?.toDouble() ?? 1;

    final allTrackers = await ref.read(trackersRepositoryProvider).findAll();
    final existing = allTrackers.cast<Map<String, Object?>>().firstWhere(
      (t) => t['name'] == trackerName,
      orElse: () => <String, Object?>{},
    );

    final trackerId = existing.isNotEmpty
        ? existing['id'] as int
        : await ref
              .read(trackersRepositoryProvider)
              .create(
                name: trackerName,
                unit: durationMinutes == null ? null : '分钟',
              );

    await ref
        .read(trackerLogsRepositoryProvider)
        .create(
          trackerId: trackerId,
          date: now,
          value: value,
          note: parsed.content,
          createdAt: createdAt,
        );
  }

  static List<String> _normalizeTags(Iterable<String> tags) {
    final seen = <String>{};
    final normalized = <String>[];

    for (final tag in tags) {
      final value = tag
          .replaceFirst(RegExp(r'^[#＃]+'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .trim();
      if (value.isEmpty || seen.contains(value)) continue;

      seen.add(value);
      normalized.add(value);
    }

    return normalized;
  }
}
