import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class MarkdownReader extends StatelessWidget {
  const MarkdownReader({
    required this.text,
    this.onDoubleTap,
    super.key,
  });

  final String text;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: blocks.length,
        itemBuilder: (context, index) => _renderBlock(context, blocks[index]),
      ),
    );
  }

  Widget _renderBlock(BuildContext context, _MdBlock block) {
    final theme = Theme.of(context);

    switch (block.type) {
      case _MdType.h1:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(
            block.content,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        );
      case _MdType.h2:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
          child: Text(
            block.content,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      case _MdType.h3:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xxs),
          child: Text(
            block.content,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      case _MdType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.primary.withAlpha(100), width: 3)),
          ),
          child: Text(
            block.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      case _MdType.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            block.content,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        );
      case _MdType.listItem:
        return Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 14)),
              Expanded(child: _renderInline(block.content, theme)),
            ],
          ),
        );
      case _MdType.table:
        return _renderTable(context, block);
      case _MdType.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _renderInline(block.content, theme),
        );
    }
  }

  Widget _renderInline(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`)');
    var lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
          text: match.group(3),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(
          text: match.group(4),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
        children: spans,
      ),
    );
  }

  Widget _renderTable(BuildContext context, _MdBlock block) {
    final rows = block.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Table(
        border: TableBorder.all(color: AppColors.border.withAlpha(80)),
        columnWidths: {for (var i = 0; i < rows.first.length; i++) i: const FlexColumnWidth()},
        children: rows.asMap().entries.map((entry) {
          final isHeader = entry.key == 0;
          return TableRow(
            decoration: isHeader
                ? BoxDecoration(color: AppColors.surfaceLow.withAlpha(120))
                : null,
            children: entry.value.map((cell) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Text(
                  cell,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  List<_MdBlock> _parseBlocks(String text) {
    final blocks = <_MdBlock>[];
    final lines = text.split('\n');
    var i = 0;
    var tableActive = false;
    var tableRows = <List<String>>[];

    while (i < lines.length) {
      var line = lines[i].trim();

      if (tableActive) {
        if (line.startsWith('|') && line.endsWith('|')) {
          final cells = line
              .substring(1, line.length - 1)
              .split('|')
              .map((c) => c.trim())
              .toList();
          tableRows.add(cells);
          i++;
          continue;
        } else {
          blocks.add(_MdBlock.table(tableRows));
          tableRows = [];
          tableActive = false;
        }
      }

      if (line.startsWith('|') && line.endsWith('|')) {
        final cells = line
            .substring(1, line.length - 1)
            .split('|')
            .map((c) => c.trim())
            .toList();
        // Check if next line is separator
        if (i + 1 < lines.length && _isTableSeparator(lines[i + 1].trim())) {
          tableActive = true;
          tableRows.add(cells);
          i += 2; // skip separator
          continue;
        }
      }

      if (line.isEmpty) {
        i++;
        continue;
      }

      if (line.startsWith('### ')) {
        blocks.add(_MdBlock.h3(line.substring(4)));
      } else if (line.startsWith('## ')) {
        blocks.add(_MdBlock.h2(line.substring(3)));
      } else if (line.startsWith('# ')) {
        blocks.add(_MdBlock.h1(line.substring(2)));
      } else if (line.startsWith('> ')) {
        blocks.add(_MdBlock.quote(line.substring(2)));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        blocks.add(_MdBlock.listItem(line.substring(2)));
      } else if (line.startsWith('```')) {
        final buf = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buf.writeln(lines[i]);
          i++;
        }
        blocks.add(_MdBlock.code(buf.toString().trim()));
      } else {
        blocks.add(_MdBlock.paragraph(line));
      }
      i++;
    }

    if (tableActive && tableRows.isNotEmpty) {
      blocks.add(_MdBlock.table(tableRows));
    }

    return blocks;
  }

  bool _isTableSeparator(String line) {
    return RegExp(r'^\|[\s\-:]+\|').hasMatch(line);
  }
}

enum _MdType { h1, h2, h3, paragraph, quote, code, listItem, table }

class _MdBlock {
  _MdBlock(this.type, this.content, [this.rows = const []]);

  _MdBlock.h1(this.content) : type = _MdType.h1, rows = const [];
  _MdBlock.h2(this.content) : type = _MdType.h2, rows = const [];
  _MdBlock.h3(this.content) : type = _MdType.h3, rows = const [];
  _MdBlock.quote(this.content) : type = _MdType.quote, rows = const [];
  _MdBlock.code(this.content) : type = _MdType.code, rows = const [];
  _MdBlock.listItem(this.content) : type = _MdType.listItem, rows = const [];
  _MdBlock.paragraph(this.content) : type = _MdType.paragraph, rows = const [];
  _MdBlock.table(this.rows) : type = _MdType.table, content = '';

  final _MdType type;
  final String content;
  final List<List<String>> rows;
}
