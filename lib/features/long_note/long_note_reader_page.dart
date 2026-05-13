import 'package:flutter/material.dart';

import 'long_note_editor_page.dart';
import 'widgets/markdown_reader.dart';

class LongNoteReaderPage extends StatelessWidget {
  const LongNoteReaderPage({
    required this.title,
    required this.filePath,
    required this.body,
    required this.recordId,
    super.key,
  });

  final String title;
  final String filePath;
  final String body;
  final int recordId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title, style: theme.textTheme.titleMedium),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_rounded, size: 20),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: MarkdownReader(
        text: body,
        onDoubleTap: () => _openEditor(context),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LongNoteEditorPage(
          initialTitle: title,
          initialBody: body,
          existingPath: filePath,
          recordId: recordId,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }
}
