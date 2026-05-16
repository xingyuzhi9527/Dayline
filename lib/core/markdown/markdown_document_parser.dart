class MarkdownDocumentContent {
  const MarkdownDocumentContent({required this.title, required this.body});

  final String title;
  final String body;
}

MarkdownDocumentContent parseMarkdownDocument(
  String raw, {
  String fallbackTitle = '',
}) {
  var body = raw.trim();

  if (body.startsWith('---\n')) {
    final end = body.indexOf('\n---\n', 4);
    if (end != -1) {
      body = body.substring(end + 5).trim();
    }
  }

  var title = fallbackTitle;
  final firstNewline = body.indexOf('\n');
  if (body.startsWith('# ')) {
    if (firstNewline == -1) {
      title = body.substring(2).trim();
      body = '';
    } else {
      title = body.substring(2, firstNewline).trim();
      body = body.substring(firstNewline + 1).trim();
    }
  }

  return MarkdownDocumentContent(title: title, body: body);
}
