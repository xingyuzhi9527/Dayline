const _sentenceEndings = {'。', '！', '？', '.', '!', '?'};

String postProcessTranscript(String input) {
  var text = input.trim();
  if (text.isEmpty) return '';

  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final fillerPattern = RegExp(r'^(嗯|啊|呃|额|那个|就是|这个)[，,\s]*');
  while (fillerPattern.hasMatch(text)) {
    text = text.replaceFirst(fillerPattern, '').trim();
  }

  if (text.isEmpty) return '';
  if (_sentenceEndings.contains(text.characters.last)) return text;
  return '$text。';
}

extension on String {
  Iterable<String> get characters sync* {
    for (final rune in runes) {
      yield String.fromCharCode(rune);
    }
  }
}
