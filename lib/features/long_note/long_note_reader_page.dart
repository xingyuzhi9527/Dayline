import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/markdown/markdown_storage_service.dart';
import 'long_note_editor_page.dart';
import 'widgets/markdown_reader.dart';

class LongNoteReaderPage extends ConsumerStatefulWidget {
  const LongNoteReaderPage({
    required this.title,
    required this.filePath,
    required this.body,
    this.recordId,
    this.projectId,
    super.key,
  });

  final String title;
  final String filePath;
  final String body;
  final int? recordId;
  final String? projectId;

  @override
  ConsumerState<LongNoteReaderPage> createState() => _LongNoteReaderPageState();
}

class _LongNoteReaderPageState extends ConsumerState<LongNoteReaderPage> {
  late String _title;
  late String _body;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _body = widget.body;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_title, style: theme.textTheme.titleMedium),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '缂栬緫',
            icon: const Icon(Icons.edit_rounded, size: 20),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: MarkdownReader(
        text: _body,
        onDoubleTap: () => _openEditor(context),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LongNoteEditorPage(
          initialTitle: _title,
          initialBody: _body,
          existingPath: widget.filePath,
          recordId: widget.recordId,
          initialProjectId: widget.projectId,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _reloadFromStorage();
    }
  }

  Future<void> _reloadFromStorage() async {
    final settings = ref.read(appSettingsRepositoryProvider);
    final storage = MarkdownStorageService(MarkdownDirectoryService(settings));
    final raw = await storage.readTextFileLocation(widget.filePath);
    final parsed = parseMarkdownDocument(raw, fallbackTitle: _title);
    if (!mounted) return;
    setState(() {
      _title = parsed.title.isNotEmpty ? parsed.title : _title;
      _body = parsed.body;
    });
  }
}
