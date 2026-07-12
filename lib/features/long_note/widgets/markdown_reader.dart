import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

class MarkdownReader extends StatelessWidget {
  const MarkdownReader({required this.text, this.onDoubleTap, super.key});

  final String text;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final blocks = _MarkdownBlockParser(text).parse();
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
    final colors = theme.colorScheme;

    switch (block.type) {
      case _MdType.h1:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.xs,
          ),
          child: _renderInline(
            context,
            block.content,
            baseStyle: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
        );
      case _MdType.h2:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.xxs,
          ),
          child: _renderInline(
            context,
            block.content,
            baseStyle: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case _MdType.h3:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.xxs,
          ),
          child: _renderInline(
            context,
            block.content,
            baseStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case _MdType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: colors.primary.withAlpha(100), width: 3),
            ),
          ),
          child: _renderInline(
            context,
            block.content,
            baseStyle: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
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
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.meta != null && block.meta!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    block.meta!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              SelectableText(
                block.content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      case _MdType.bullet:
        return _ListRow(
          leading: const Text('•', style: TextStyle(fontSize: 14)),
          child: _renderInline(context, block.content),
        );
      case _MdType.ordered:
        return _ListRow(
          leading: Text(
            block.meta ?? '1.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          child: _renderInline(context, block.content),
        );
      case _MdType.task:
        final checked = block.meta == 'checked';
        return _ListRow(
          leading: Icon(
            checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? colors.primary : colors.onSurfaceVariant,
          ),
          child: _renderInline(
            context,
            block.content,
            baseStyle: theme.textTheme.bodyLarge?.copyWith(
              height: 1.7,
              decoration: checked ? TextDecoration.lineThrough : null,
              color: checked ? colors.onSurfaceVariant : null,
            ),
          ),
        );
      case _MdType.table:
        return _renderTable(context, block);
      case _MdType.rule:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Divider(height: 1),
        );
      case _MdType.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _renderInline(context, block.content),
        );
    }
  }

  Widget _renderInline(
    BuildContext context,
    String text, {
    TextStyle? baseStyle,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveStyle =
        baseStyle ?? theme.textTheme.bodyLarge?.copyWith(height: 1.7);
    final spans = _MarkdownInlineParser(
      text,
      effectiveStyle ?? const TextStyle(),
      linkColor: colors.primary,
      inlineCodeBackground: colors.surfaceContainerLow,
    ).parse();

    return SelectableText.rich(
      TextSpan(style: effectiveStyle, children: spans),
    );
  }

  Widget _renderTable(BuildContext context, _MdBlock block) {
    final rows = block.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Table(
        border: TableBorder.all(color: colors.outlineVariant.withAlpha(80)),
        columnWidths: {
          for (var i = 0; i < rows.first.length; i++)
            i: const FlexColumnWidth(),
        },
        children: rows.asMap().entries.map((entry) {
          final isHeader = entry.key == 0;
          return TableRow(
            decoration: isHeader
                ? BoxDecoration(
                    color: colors.surfaceContainerLow.withAlpha(120),
                  )
                : null,
            children: entry.value.map((cell) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: SelectableText(
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
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.leading, required this.child});

  final Widget leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Center(child: leading)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MarkdownBlockParser {
  _MarkdownBlockParser(this.text);

  final String text;

  List<_MdBlock> parse() {
    final blocks = <_MdBlock>[];
    final lines = text.split('\n');
    var i = 0;
    final paragraph = StringBuffer();

    void flushParagraph() {
      final content = paragraph.toString().trim();
      if (content.isNotEmpty) {
        blocks.add(_MdBlock.paragraph(content));
      }
      paragraph.clear();
    }

    while (i < lines.length) {
      final rawLine = lines[i];
      final line = rawLine.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        i++;
        continue;
      }

      if (trimmed.startsWith('```')) {
        flushParagraph();
        final language = trimmed.substring(3).trim();
        final buffer = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buffer.writeln(lines[i]);
          i++;
        }
        blocks.add(
          _MdBlock.code(buffer.toString().trimRight(), meta: language),
        );
        i++;
        continue;
      }

      if (_isTableHeader(trimmed, i, lines)) {
        flushParagraph();
        final rows = <List<String>>[_parseTableRow(trimmed)];
        i += 2;
        while (i < lines.length) {
          final candidate = lines[i].trim();
          if (!candidate.startsWith('|') || !candidate.endsWith('|')) break;
          rows.add(_parseTableRow(candidate));
          i++;
        }
        blocks.add(_MdBlock.table(rows));
        continue;
      }

      final headingMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        flushParagraph();
        final level = headingMatch.group(1)!.length;
        final content = headingMatch.group(2)!;
        blocks.add(switch (level) {
          1 => _MdBlock.h1(content),
          2 => _MdBlock.h2(content),
          _ => _MdBlock.h3(content),
        });
        i++;
        continue;
      }

      if (trimmed.startsWith('> ')) {
        flushParagraph();
        blocks.add(_MdBlock.quote(trimmed.substring(2).trim()));
        i++;
        continue;
      }

      final taskMatch = RegExp(
        r'^[-*]\s+\[( |x|X)\]\s+(.+)$',
      ).firstMatch(trimmed);
      if (taskMatch != null) {
        flushParagraph();
        blocks.add(
          _MdBlock.task(
            taskMatch.group(2)!,
            checked: taskMatch.group(1)!.toLowerCase() == 'x',
          ),
        );
        i++;
        continue;
      }

      final orderedMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (orderedMatch != null) {
        flushParagraph();
        blocks.add(
          _MdBlock.ordered(
            orderedMatch.group(2)!,
            number: '${orderedMatch.group(1)}.',
          ),
        );
        i++;
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        flushParagraph();
        blocks.add(_MdBlock.bullet(trimmed.substring(2).trim()));
        i++;
        continue;
      }

      if (RegExp(r'^([-*_])\1{2,}$').hasMatch(trimmed)) {
        flushParagraph();
        blocks.add(const _MdBlock.rule());
        i++;
        continue;
      }

      if (paragraph.isNotEmpty) {
        paragraph.write('\n');
      }
      paragraph.write(trimmed);
      i++;
    }

    flushParagraph();
    return blocks;
  }

  bool _isTableHeader(String line, int index, List<String> lines) {
    if (!(line.startsWith('|') && line.endsWith('|'))) return false;
    if (index + 1 >= lines.length) return false;
    return RegExp(r'^\|(?:\s*:?-+:?\s*\|)+$').hasMatch(lines[index + 1].trim());
  }

  List<String> _parseTableRow(String line) {
    return line
        .substring(1, line.length - 1)
        .split('|')
        .map((cell) => cell.trim())
        .toList();
  }
}

class _MarkdownInlineParser {
  _MarkdownInlineParser(
    this.text,
    this.baseStyle, {
    required this.linkColor,
    required this.inlineCodeBackground,
  });

  final String text;
  final TextStyle baseStyle;
  final Color linkColor;
  final Color inlineCodeBackground;

  List<InlineSpan> parse() {
    final spans = <InlineSpan>[];
    var index = 0;

    while (index < text.length) {
      final remaining = text.substring(index);

      final linkMatch = RegExp(
        r'^\[([^\]]+)\]\(([^)]+)\)',
      ).firstMatch(remaining);
      if (linkMatch != null) {
        spans.add(
          TextSpan(
            text: linkMatch.group(1),
            style: baseStyle.copyWith(
              color: linkColor,
              decoration: TextDecoration.underline,
            ),
          ),
        );
        index += linkMatch.group(0)!.length;
        continue;
      }

      final boldMatch = RegExp(r'^\*\*(.+?)\*\*').firstMatch(remaining);
      if (boldMatch != null) {
        spans.add(
          TextSpan(
            text: boldMatch.group(1),
            style: baseStyle.copyWith(fontWeight: FontWeight.w700),
          ),
        );
        index += boldMatch.group(0)!.length;
        continue;
      }

      final inlineCodeMatch = RegExp(r'^`(.+?)`').firstMatch(remaining);
      if (inlineCodeMatch != null) {
        spans.add(
          TextSpan(
            text: inlineCodeMatch.group(1),
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: inlineCodeBackground,
            ),
          ),
        );
        index += inlineCodeMatch.group(0)!.length;
        continue;
      }

      final italicMatch = RegExp(r'^\*(.+?)\*').firstMatch(remaining);
      if (italicMatch != null) {
        spans.add(
          TextSpan(
            text: italicMatch.group(1),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
        index += italicMatch.group(0)!.length;
        continue;
      }

      final strikeMatch = RegExp(r'^~~(.+?)~~').firstMatch(remaining);
      if (strikeMatch != null) {
        spans.add(
          TextSpan(
            text: strikeMatch.group(1),
            style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
        index += strikeMatch.group(0)!.length;
        continue;
      }

      spans.add(TextSpan(text: text[index]));
      index++;
    }

    return spans;
  }
}

enum _MdType {
  h1,
  h2,
  h3,
  paragraph,
  quote,
  code,
  bullet,
  ordered,
  task,
  table,
  rule,
}

class _MdBlock {
  const _MdBlock(this.type, this.content, {this.meta, this.rows = const []});

  const _MdBlock.h1(String content) : this(_MdType.h1, content);
  const _MdBlock.h2(String content) : this(_MdType.h2, content);
  const _MdBlock.h3(String content) : this(_MdType.h3, content);
  const _MdBlock.quote(String content) : this(_MdType.quote, content);
  const _MdBlock.code(String content, {String? meta})
    : this(_MdType.code, content, meta: meta);
  const _MdBlock.bullet(String content) : this(_MdType.bullet, content);
  const _MdBlock.ordered(String content, {required String number})
    : this(_MdType.ordered, content, meta: number);
  const _MdBlock.task(String content, {required bool checked})
    : this(_MdType.task, content, meta: checked ? 'checked' : 'unchecked');
  const _MdBlock.paragraph(String content) : this(_MdType.paragraph, content);
  const _MdBlock.table(List<List<String>> rows)
    : this(_MdType.table, '', rows: rows);
  const _MdBlock.rule() : this(_MdType.rule, '');

  final _MdType type;
  final String content;
  final String? meta;
  final List<List<String>> rows;
}
