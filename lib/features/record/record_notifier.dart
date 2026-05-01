import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/parser/lui_lite_parser.dart';
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
      await _persist(parsed, asMemo: asMemo);
      ref.read(dataVersionProvider.notifier).increment();
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
      await _persist(parsed, asMemo: asMemo);
      ref.read(dataVersionProvider.notifier).increment();
      state = const RecordState();
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
    }
  }

  Future<void> _persist(ParsedInput parsed, {required bool asMemo}) async {
    final now = DateTime.now();

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
            );

      case ParsedInputType.todo:
        await ref
            .read(todosRepositoryProvider)
            .create(date: now, title: parsed.content, dueTime: parsed.time);

      case ParsedInputType.focus:
        final durationMinutes =
            (parsed.metadata['durationMinutes'] as int?) ?? 25;
        await ref
            .read(focusSessionsRepositoryProvider)
            .create(
              date: now,
              startedAt: now,
              durationMinutes: durationMinutes,
              note: parsed.content,
            );

      case ParsedInputType.expense:
        final amount = (parsed.metadata['amount'] as num?)?.toDouble() ?? 0.0;
        final category = parsed.tags.isNotEmpty ? parsed.tags.first : 'other';
        await ref
            .read(expensesRepositoryProvider)
            .create(
              date: now,
              amount: amount,
              category: category,
              note: parsed.content,
            );

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
            );

      case ParsedInputType.tracker:
        await _saveTrackerLog(parsed, now);
    }
  }

  Future<void> _saveTrackerLog(ParsedInput parsed, DateTime now) async {
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
