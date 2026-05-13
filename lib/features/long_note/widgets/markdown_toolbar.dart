import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _ToolButton(label: 'H1', onTap: () => _wrapLine('# ')),
          _ToolButton(label: 'H2', onTap: () => _wrapLine('## ')),
          _ToolButton(label: 'B', onTap: () => _wrapSelection('**', '**')),
          _ToolButton(label: 'I', onTap: () => _wrapSelection('*', '*')),
          _ToolButton(label: '[]', onTap: () => _insertAtCursor('- [ ] ')),
          _ToolButton(label: '-', onTap: () => _insertAtCursor('- ')),
          _ToolButton(label: '>', onTap: () => _insertAtCursor('> ')),
          _ToolButton(label: '```', onTap: () => _insertBlock('```', '```')),
          _ToolButton(
            label: 'T',
            onTap: () => _insertAtCursor(
              '| 项目 | 内容 |\n| --- | --- |\n|  |  |\n',
            ),
          ),
        ],
      ),
    );
  }

  void _wrapSelection(String open, String close) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;

    if (sel.isCollapsed) {
      final placeholder = '文字';
      final newText = '$text$open$placeholder$close';
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: newText.length - close.length - placeholder.length,
        ),
      );
    } else {
      final selected = text.substring(sel.start, sel.end);
      final newText = text.replaceRange(sel.start, sel.end, '$open$selected$close');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + open.length + selected.length + close.length),
      );
    }
  }

  void _wrapLine(String prefix) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;

    // Find start of current line
    var lineStart = sel.isCollapsed ? sel.baseOffset : sel.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    // Find end of current line
    var lineEnd = sel.isCollapsed ? sel.baseOffset : sel.end;
    while (lineEnd < text.length && text[lineEnd] != '\n') {
      lineEnd++;
    }

    final line = text.substring(lineStart, lineEnd);
    final newLine = '$prefix$line';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: lineStart + newLine.length,
      ),
    );
  }

  void _insertAtCursor(String text) {
    final current = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;

    final start = sel.isCollapsed ? sel.baseOffset : sel.start;
    final end = sel.isCollapsed ? sel.baseOffset : sel.end;
    final newText = current.replaceRange(start, end, text);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  void _insertBlock(String open, String close) {
    final current = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;

    final start = sel.isCollapsed ? sel.baseOffset : sel.start;
    final end = sel.isCollapsed ? sel.baseOffset : sel.end;
    final selected = current.substring(start, end);
    final block = '$open\n${selected.isNotEmpty ? selected : '  '}\n$close\n';
    final newText = current.replaceRange(start, end, block);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: start + open.length + 1,
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Material(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: label.length > 2 ? 44 : 36,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: label.length > 2 ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
