enum ParsedInputType { memo, todo, tracker, focus, expense, body, sleep }

class ParsedInput {
  const ParsedInput({
    required this.type,
    required this.content,
    required this.time,
    required this.date,
    required this.tags,
    required this.metadata,
    required this.confidence,
  });

  final ParsedInputType type;
  final String content;
  final String? time;
  final DateTime? date;
  final List<String> tags;
  final Map<String, Object?> metadata;
  final double confidence;
}

class LuiLiteParser {
  const LuiLiteParser._();

  static final RegExp _tagPattern = RegExp('[#＃]([A-Za-z0-9_\u4e00-\u9fff-]+)');
  static final RegExp _colonTimePattern = RegExp(
    r'([01]?\d|2[0-3])[:：]([0-5]\d)',
  );
  static final RegExp _chineseTimePattern = RegExp(r'([01]?\d|2[0-3])点(半)?');
  static final RegExp _todoPrefixPattern = RegExp(
    r'^(todo|待办|任务|记得|要做)\s*[:：-]?\s*',
    caseSensitive: false,
  );
  static final RegExp _focusPattern = RegExp(
    r'(番茄|专注|focus|pomodoro|25\s*min|25\s*分钟)',
    caseSensitive: false,
  );
  static final RegExp _expensePattern = RegExp(
    r'(元|块|¥|￥|RMB)',
    caseSensitive: false,
  );
  static final RegExp _amountPrefixPattern = RegExp(
    r'(?:¥|￥|RMB)\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final RegExp _amountSuffixPattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:元|块)',
  );
  static final RegExp _bodyPattern = RegExp(
    r'(体重|weight)',
    caseSensitive: false,
  );
  static final RegExp _numberPattern = RegExp(r'\d+(?:\.\d+)?');
  static final RegExp _sleepPattern = RegExp(r'(睡觉|入睡|醒来|起床)');
  static final RegExp _trackerPattern = RegExp(r'(起床|喝水|吃药|运动|冥想|今日计划)');
  static final RegExp _durationPattern = RegExp(
    r'(\d+)\s*(?:min|分钟)',
    caseSensitive: false,
  );

  static ParsedInput parse(String rawInput) {
    final normalizedInput = _compactWhitespace(rawInput.trim());
    final tags = _extractTags(normalizedInput);
    final time = _extractTime(normalizedInput);
    final metadata = <String, Object?>{};
    final type = _inferType(normalizedInput, metadata);
    final content = _extractContent(normalizedInput, type);

    return ParsedInput(
      type: type,
      content: content,
      time: time,
      date: null,
      tags: tags,
      metadata: metadata,
      confidence: _confidenceFor(type),
    );
  }

  static List<String> _extractTags(String input) {
    return _tagPattern
        .allMatches(input)
        .map((match) => match.group(1)!)
        .toList(growable: false);
  }

  static String? _extractTime(String input) {
    final colonMatch = _colonTimePattern.firstMatch(input);
    if (colonMatch != null) {
      return _formatTime(
        int.parse(colonMatch.group(1)!),
        int.parse(colonMatch.group(2)!),
      );
    }

    final chineseMatch = _chineseTimePattern.firstMatch(input);
    if (chineseMatch != null) {
      return _formatTime(
        int.parse(chineseMatch.group(1)!),
        chineseMatch.group(2) == null ? 0 : 30,
      );
    }

    return null;
  }

  static ParsedInputType _inferType(
    String input,
    Map<String, Object?> metadata,
  ) {
    if (_todoPrefixPattern.hasMatch(input)) {
      return ParsedInputType.todo;
    }

    if (_focusPattern.hasMatch(input)) {
      final duration = _extractDuration(input);
      if (duration != null) {
        metadata['durationMinutes'] = duration;
      }
      return ParsedInputType.focus;
    }

    if (_expensePattern.hasMatch(input)) {
      final amount = _extractAmount(input);
      if (amount != null) {
        metadata['amount'] = amount;
      }
      return ParsedInputType.expense;
    }

    if (_bodyPattern.hasMatch(input)) {
      final value = _extractNumber(input);
      if (value != null) {
        metadata['value'] = value;
      }
      metadata['metric'] = 'weight';
      return ParsedInputType.body;
    }

    if (_sleepPattern.hasMatch(input)) {
      return ParsedInputType.sleep;
    }

    if (_trackerPattern.hasMatch(input)) {
      return ParsedInputType.tracker;
    }

    return ParsedInputType.memo;
  }

  static String _extractContent(String input, ParsedInputType type) {
    var content = input
        .replaceAll(_tagPattern, '')
        .replaceAll(_colonTimePattern, '')
        .replaceAll(_chineseTimePattern, '');

    if (type == ParsedInputType.todo) {
      content = content.replaceFirst(_todoPrefixPattern, '');
    }

    return _trimLoosePunctuation(_compactWhitespace(content));
  }

  static double? _extractAmount(String input) {
    final prefixMatch = _amountPrefixPattern.firstMatch(input);
    if (prefixMatch != null) {
      return double.parse(prefixMatch.group(1)!);
    }

    final suffixMatch = _amountSuffixPattern.firstMatch(input);
    if (suffixMatch != null) {
      return double.parse(suffixMatch.group(1)!);
    }

    return null;
  }

  static double? _extractNumber(String input) {
    final match = _numberPattern.firstMatch(input);
    if (match == null) {
      return null;
    }

    return double.parse(match.group(0)!);
  }

  static int? _extractDuration(String input) {
    final match = _durationPattern.firstMatch(input);
    if (match == null) {
      return null;
    }

    return int.parse(match.group(1)!);
  }

  static String _formatTime(int hour, int minute) {
    final formattedHour = hour.toString().padLeft(2, '0');
    final formattedMinute = minute.toString().padLeft(2, '0');
    return '$formattedHour:$formattedMinute';
  }

  static double _confidenceFor(ParsedInputType type) {
    return switch (type) {
      ParsedInputType.todo => 0.95,
      ParsedInputType.focus => 0.9,
      ParsedInputType.expense => 0.88,
      ParsedInputType.body => 0.86,
      ParsedInputType.sleep => 0.82,
      ParsedInputType.tracker => 0.78,
      ParsedInputType.memo => 0.5,
    };
  }

  static String _compactWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _trimLoosePunctuation(String input) {
    return input.replaceAll(RegExp(r'^[,，。:：;；\s]+|[,，。:：;；\s]+$'), '');
  }
}
