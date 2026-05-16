String cleanExpenseNote(String? raw) {
  var text = raw?.trim() ?? '';
  if (text.isEmpty) return '';

  text = text
      .replaceAll(
        RegExp(
          r'(?:[¥￥]|RMB)\s*\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*(?:元|块钱|块)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[零〇一二两三四五六七八九十百千万点半]+\s*(?:元|块钱|块)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[,，。！？!?:：；;\s]+|[,，。！？!?:：；;\s]+$'), '')
      .trim();

  if (text == '花了' || text == '消费' || text == '买了' || text == '支出') {
    return '';
  }
  return text;
}
