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

  ParsedInput copyWith({
    ParsedInputType? type,
    String? content,
    String? time,
    DateTime? date,
    List<String>? tags,
    Map<String, Object?>? metadata,
    double? confidence,
  }) {
    return ParsedInput(
      type: type ?? this.type,
      content: content ?? this.content,
      time: time ?? this.time,
      date: date ?? this.date,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
      confidence: confidence ?? this.confidence,
    );
  }
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
    r'(番茄|专注|focus|pomodoro)',
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
  static final RegExp _exerciseTrackerPattern = RegExp(
    r'(跑步|慢跑|运动|健身|训练|瑜伽|游泳|骑行|骑车|散步|步行|拉伸)',
  );
  static final RegExp _trackerPattern = RegExp(
    r'(起床|喝水|吃药|冥想|今日计划|跑步|慢跑|运动|健身|训练|瑜伽|游泳|骑行|骑车|散步|步行|拉伸)',
  );
  static final RegExp _durationPattern = RegExp(
    r'(\d+)\s*(min|mins|minute|minutes|分钟|小时|hour|hours|h)',
    caseSensitive: false,
  );

  static ParsedInput parse(String rawInput) {
    final normalizedInput = _compactWhitespace(rawInput.trim());
    final explicitTags = _extractTags(normalizedInput);
    final time = _extractTime(normalizedInput);
    final metadata = <String, Object?>{};
    final type = _inferType(normalizedInput, metadata);
    final tags = explicitTags.isEmpty
        ? _inferTags(normalizedInput, type)
        : explicitTags;
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
      final duration = _extractDuration(input);
      if (duration != null) {
        metadata['durationMinutes'] = duration;
      }
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

    if (type == ParsedInputType.focus || type == ParsedInputType.tracker) {
      content = content.replaceAll(_durationPattern, '');
    }

    if (type == ParsedInputType.tracker) {
      final trackerName = _extractTrackerName(content);
      if (trackerName != null) {
        return trackerName;
      }
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

    final value = int.parse(match.group(1)!);
    final unit = match.group(2)!.toLowerCase();

    if (unit == '小时' || unit == 'h' || unit.startsWith('hour')) {
      return value * 60;
    }

    return value;
  }

  static String? _extractTrackerName(String input) {
    final match = _trackerPattern.firstMatch(input);
    return match?.group(0);
  }

  static List<String> _inferTags(String input, ParsedInputType type) {
    if (type == ParsedInputType.tracker &&
        _exerciseTrackerPattern.hasMatch(input)) {
      return const ['运动'];
    }

    return const [];
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
