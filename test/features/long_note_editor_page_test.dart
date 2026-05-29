import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/features/long_note/long_note_editor_page.dart';

void main() {
  testWidgets('long note body uses multiline keyboard and keeps newlines', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LongNoteEditorPage())),
    );

    final bodyFinder = find.byKey(const ValueKey('long-note-body-field'));
    final bodyField = tester.widget<TextField>(bodyFinder);

    expect(bodyField.keyboardType, TextInputType.multiline);
    expect(bodyField.textInputAction, TextInputAction.newline);

    await tester.enterText(bodyFinder, '# 一级标题\n正文第一行');

    expect(find.text('# 一级标题\n正文第一行'), findsOneWidget);
  });
}
