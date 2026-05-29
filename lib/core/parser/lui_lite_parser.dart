import 'expense_note_cleaner.dart';
import 'expense_line_item.dart';

enum ParsedInputType { memo, todo, tracker, focus, expense, body, sleep, mood }

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

abstract final class _Re {
  static final tag = RegExp(r'[#＃]([^\s#＃,，。！？!?:：；;]+)');
  static final colonTime = RegExp(r'([01]?\d|2[0-3])[:：]([0-5]\d)');
  static final chineseTime = RegExp(r'([01]?\d|2[0-3])点(半)?');
  static final todoPrefix = RegExp(
    r'^(todo|待办|任务|记得|要做|别忘了|别忘|需要|必须|准备|提醒|请|要)\s*[:：]?\s*',
    caseSensitive: false,
  );
  static final duration = RegExp(
    r'(\d+(?:\.\d+)?)\s*(min|mins|minute|minutes|分钟|小时|hour|hours|h)',
    caseSensitive: false,
  );
  static final amountPrefix = RegExp(
    r'(?:¥|￥|RMB)\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final amountSuffix = RegExp(r'(\d+(?:\.\d+)?)\s*(?:元|块钱|块)');
  static final chineseAmountSuffix = RegExp(
    '([\\u96f6\\u3007\\u4e00\\u4e8c\\u4e24\\u4e09\\u56db\\u4e94'
    '\\u516d\\u4e03\\u516b\\u4e5d\\u5341\\u767e\\u5343\\u4e07'
    '\\u70b9\\u534a]+)\\s*(?:\\u5143|\\u5757|\\u5757\\u94b1)',
  );
  static final number = RegExp(r'\d+(?:\.\d+)?');
}

abstract final class _KW {
  static final expense = RegExp(
    r'(元|块|￥|¥|RMB|花了|买了|消费|花费|用了|块钱|支出|午饭|午餐|晚饭|晚餐|早饭|早餐|外卖|打车费|水电费|房租|聚餐|咖啡|奶茶)',
    caseSensitive: false,
  );
  static final focus = RegExp(
    r'(番茄|专注|focus|pomodoro|心流|沉浸)',
    caseSensitive: false,
  );
  static final body = RegExp(
    r'(体重|weight|身高|血压|血糖|心率|体温|体脂)',
    caseSensitive: false,
  );
  static final bodyMetric = {
    '体重': 'weight',
    'weight': 'weight',
    '身高': 'height',
    '血压': 'blood_pressure',
    '血糖': 'blood_sugar',
    '心率': 'heart_rate',
    '体温': 'body_temp',
    '体脂': 'body_fat',
  };
  static final sleep = RegExp(
    r'(睡觉|入睡|醒来|睡了|熬夜|午睡|小憩|nap|失眠|没睡好|睡眠)',
    caseSensitive: false,
  );
  static final mood = RegExp(
    r'(心情|情绪|感觉|状态|不错|很好|一般|不好|很差|还行|超好|糟糕|低落|烦躁|焦虑|平静|放松|开心|快乐|难过|伤心|生气|emo|累了|好累|疲惫|紧张|兴奋|高兴|满足|幸福|压力)',
    caseSensitive: false,
  );

  static final exercise = RegExp(
    r'(跑步|慢跑|运动|健身|训练|瑜伽|游泳|骑行|骑车|散步|步行|拉伸|深蹲|俯卧撑|跳绳|打球|篮球|足球|羽毛球|乒乓球|跳舞|拳击|普拉提|冲浪|滑雪|溜冰)',
  );
  static final dailyHabit = RegExp(
    r'(起床|喝水|喝够|吃药|冥想|今日计划|写日记|日记|复盘|称体重|防晒|护肤|泡脚|早睡|早起|吃早饭|吃早餐|不吃晚饭|断食|戒糖|不喝奶茶|不喝酒|不抽烟)',
  );
  static final learning = RegExp(
    r'(学习|看书|读书|阅读|上课|听课|写作|做题|背单词|练口语|写代码|编程|刷题|考证|备考|复习|预习|做笔记|写文章)',
  );
  static final work = RegExp(
    r'(开会|上班|下班|加班|出差|汇报|报告|周报|日报|项目|方案|提案|客户|合同|面试|入职|离职|调休|请假|产品评审)',
  );
  static final housework = RegExp(r'(打扫|整理|收纳|洗衣服|做饭|洗碗|买菜|倒垃圾|拖地|擦窗|换床单|浇花)');
  static final social = RegExp(
    r'(聚会|约会|见面|聊天|打电话|视频|约饭|逛街|看电影|看剧|追剧|KTV|唱歌|出去玩)',
  );
  static final health = RegExp(r'(体检|看病|看医生|挂号|打针|输液|理疗|按摩|拔罐|针灸|看牙|配眼镜)');
  static final hobby = RegExp(
    r'(练琴|画画|绘画|摄影|拍照|书法|手工|烘焙|养花|钓鱼|下棋|桌游|剧本杀|打游戏|弹吉他|弹钢琴|拉小提琴)',
  );

  static final tracker = RegExp(
    [
      exercise,
      dailyHabit,
      learning,
      work,
      housework,
      social,
      health,
      hobby,
    ].map((r) => r.pattern).join('|'),
  );

  static final memoContext = RegExp(
    r'(备忘|忘记|忘了|忘掉|计划|方案|想法|灵感|思路|考虑|打算|想要|需要做|设计|开发|实现|功能|优化|修复|改进|增加|添加|修改|调整|需求|问题|bug)',
  );
}

class LuiLiteParser {
  const LuiLiteParser._();

  static ParsedInput parse(String rawInput) {
    final input = _compactWhitespace(rawInput.trim());
    final tags = _extractTags(input);
    final time = _extractTime(input);
    final metadata = <String, Object?>{};
    final type = _inferType(input, metadata);
    final inferredTags = tags.isEmpty ? _inferTags(input, type) : tags;
    final content = _extractContent(input, type);

    return ParsedInput(
      type: type,
      content: content,
      time: time,
      date: null,
      tags: inferredTags,
      metadata: metadata,
      confidence: _confidenceFor(type),
    );
  }

  static List<String> _extractTags(String input) {
    return _Re.tag
        .allMatches(input)
        .map((m) => m.group(1)!.trim())
        .where((tag) => tag.isNotEmpty && tag.length <= 20)
        .toList(growable: false);
  }

  static String? _extractTime(String input) {
    final colon = _Re.colonTime.firstMatch(input);
    if (colon != null) {
      return _fmt(int.parse(colon.group(1)!), int.parse(colon.group(2)!));
    }
    final chinese = _Re.chineseTime.firstMatch(input);
    if (chinese != null) {
      return _fmt(
        int.parse(chinese.group(1)!),
        chinese.group(2) == null ? 0 : 30,
      );
    }
    return null;
  }

  static String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  static ParsedInputType _inferType(String input, Map<String, Object?> meta) {
    if (_Re.todoPrefix.hasMatch(input)) return ParsedInputType.todo;

    if (_KW.focus.hasMatch(input)) {
      final duration = _extractDuration(input);
      if (duration != null) {
        meta['durationMinutes'] = duration;
        return ParsedInputType.focus;
      }
      if (_isLikelyMemo(input)) return ParsedInputType.memo;
    }

    final expenseItems = _extractExpenseItems(input);
    if (_KW.expense.hasMatch(input) && expenseItems.isNotEmpty) {
      meta.addAll(expenseMetadataForItems(expenseItems));
      return ParsedInputType.expense;
    }
    if (expenseItems.isNotEmpty && _looksLikeExpense(input)) {
      meta.addAll(expenseMetadataForItems(expenseItems));
      return ParsedInputType.expense;
    }

    if (_KW.body.hasMatch(input)) {
      final value = _extractNumber(input);
      if (value != null) meta['value'] = value;
      meta['metric'] = _resolveBodyMetric(input);
      return ParsedInputType.body;
    }

    if (_KW.sleep.hasMatch(input)) return ParsedInputType.sleep;
    if (_looksLikeMood(input)) return ParsedInputType.mood;

    if (_KW.tracker.hasMatch(input)) {
      if (_isLikelyMemo(input)) return ParsedInputType.memo;
      final duration = _extractDuration(input);
      if (duration != null) meta['durationMinutes'] = duration;
      return ParsedInputType.tracker;
    }

    return ParsedInputType.memo;
  }

  static bool _looksLikeExpense(String input) {
    return _Re.amountPrefix.hasMatch(input) ||
        _Re.amountSuffix.hasMatch(input) ||
        _Re.chineseAmountSuffix.hasMatch(input);
  }

  static bool _looksLikeMood(String input) {
    if (!_KW.mood.hasMatch(input)) return false;
    if (_KW.tracker.hasMatch(input) && !_KW.memoContext.hasMatch(input)) {
      return RegExp(r'^(心情|情绪|感觉|状态|今天|现在)').hasMatch(input);
    }
    return true;
  }

  static bool _isLikelyMemo(String input) {
    if (_KW.memoContext.hasMatch(input)) return true;
    return false;
  }

  static String? _resolveBodyMetric(String input) {
    for (final entry in _KW.bodyMetric.entries) {
      if (input.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return null;
  }

  static String _extractContent(String input, ParsedInputType type) {
    var content = input
        .replaceAll(_Re.tag, '')
        .replaceAll(_Re.colonTime, '')
        .replaceAll(_Re.chineseTime, '');

    if (type == ParsedInputType.todo) {
      content = content.replaceFirst(_Re.todoPrefix, '');
    }
    if (type == ParsedInputType.focus || type == ParsedInputType.tracker) {
      content = content.replaceAll(_Re.duration, '');
    }
    if (type == ParsedInputType.tracker) {
      final stripped = _stripTrackerKeywords(content);
      if (stripped.isNotEmpty) content = stripped;
    }
    if (type == ParsedInputType.body) {
      content = content.replaceAll(_Re.number, '');
    }
    if (type == ParsedInputType.expense) {
      content = cleanExpenseNote(content);
    }

    return _trimLoosePunctuation(_compactWhitespace(content));
  }

  static List<ExpenseLineItem> _extractExpenseItems(String input) {
    final matches = _amountMatches(input);
    if (matches.isEmpty) return const [];

    final items = <ExpenseLineItem>[];
    for (var i = 0; i < matches.length; i += 1) {
      final match = matches[i];
      final previousEnd = i == 0 ? 0 : matches[i - 1].end;
      final nextStart = i + 1 >= matches.length
          ? input.length
          : matches[i + 1].start;
      final name = match.isPrefix
          ? _expenseItemNameAfter(input, match, nextStart)
          : _expenseItemNameBefore(input, match, previousEnd, nextStart);
      items.add(ExpenseLineItem(name: name, amount: match.amount));
    }

    return items;
  }

  static List<_AmountMatch> _amountMatches(String input) {
    final rawMatches = <_AmountMatch>[];

    for (final match in _Re.amountPrefix.allMatches(input)) {
      rawMatches.add(
        _AmountMatch(
          amount: double.parse(match.group(1)!),
          start: match.start,
          end: match.end,
          isPrefix: true,
        ),
      );
    }

    for (final match in _Re.amountSuffix.allMatches(input)) {
      rawMatches.add(
        _AmountMatch(
          amount: double.parse(match.group(1)!),
          start: match.start,
          end: match.end,
          isPrefix: false,
        ),
      );
    }

    for (final match in _Re.chineseAmountSuffix.allMatches(input)) {
      final amount = _parseChineseNumber(match.group(1)!);
      if (amount == null) continue;
      rawMatches.add(
        _AmountMatch(
          amount: amount,
          start: match.start,
          end: match.end,
          isPrefix: false,
        ),
      );
    }

    rawMatches.sort((a, b) => a.start.compareTo(b.start));

    final matches = <_AmountMatch>[];
    var lastEnd = -1;
    for (final match in rawMatches) {
      if (match.start < lastEnd) continue;
      matches.add(match);
      lastEnd = match.end;
    }
    return matches;
  }

  static String _expenseItemNameBefore(
    String input,
    _AmountMatch match,
    int previousEnd,
    int nextStart,
  ) {
    final separatorEnd = _lastItemSeparatorEndBefore(input, match.start);
    final start = [previousEnd, separatorEnd].reduce((a, b) => a > b ? a : b);
    final before = _cleanExpenseItemName(input.substring(start, match.start));
    if (before.isNotEmpty) return before;
    return _expenseItemNameAfter(input, match, nextStart);
  }

  static String _expenseItemNameAfter(
    String input,
    _AmountMatch match,
    int nextStart,
  ) {
    final separatorStart = _firstItemSeparatorStartAfter(input, match.end);
    final end = [nextStart, separatorStart].reduce((a, b) => a < b ? a : b);
    return _cleanExpenseItemName(input.substring(match.end, end));
  }

  static String _cleanExpenseItemName(String raw) {
    final withoutTags = raw.replaceAll(_Re.tag, '');
    var text = cleanExpenseNote(withoutTags);
    text = text
        .replaceFirst(RegExp(r'^(其中|一共|总共|合计|买了|花了|消费|支出|用了|花费)\s*'), '')
        .replaceFirst(RegExp(r'\s*(花了|消费|支出|用了|花费)$'), '');
    return _trimLoosePunctuation(_compactWhitespace(text));
  }

  static int _lastItemSeparatorEndBefore(String input, int offset) {
    var end = 0;
    for (final match in RegExp(r'[,，、;；。.!！?？\n]+').allMatches(input)) {
      if (match.end > offset) break;
      end = match.end;
    }
    return end;
  }

  static int _firstItemSeparatorStartAfter(String input, int offset) {
    for (final match in RegExp(r'[,，、;；。.!！?？\n]+').allMatches(input)) {
      if (match.start >= offset) return match.start;
    }
    return input.length;
  }

  static double? _parseChineseNumber(String input) {
    if (input.isEmpty) return null;
    if (input == '半') return 0.5;

    final parts = input.split('点');
    if (parts.length > 2) return null;

    final whole = _parseChineseInteger(parts.first);
    if (whole == null) return null;
    if (parts.length == 1) return whole.toDouble();

    final decimalDigits = parts.last.runes.map(_chineseDigit).toList();
    if (decimalDigits.any((digit) => digit == null)) return whole.toDouble();
    return whole + double.parse('0.${decimalDigits.join()}');
  }

  static int? _parseChineseInteger(String input) {
    if (input.isEmpty) return 0;

    final hasUnit = input.runes.any(
      (rune) =>
          rune == 0x5341 || rune == 0x767e || rune == 0x5343 || rune == 0x4e07,
    );
    if (!hasUnit) {
      final digits = input.runes.map(_chineseDigit).toList();
      if (digits.any((digit) => digit == null)) return null;
      return int.parse(digits.join());
    }

    var result = 0;
    var section = 0;
    var number = 0;

    for (final rune in input.runes) {
      final digit = _chineseDigit(rune);
      if (digit != null) {
        number = digit;
        continue;
      }

      final unit = switch (rune) {
        0x5341 => 10,
        0x767e => 100,
        0x5343 => 1000,
        0x4e07 => 10000,
        _ => null,
      };
      if (unit == null) return null;

      if (unit == 10000) {
        section += number;
        result += section * unit;
        section = 0;
      } else {
        section += (number == 0 ? 1 : number) * unit;
      }
      number = 0;
    }

    return result + section + number;
  }

  static int? _chineseDigit(int rune) => switch (rune) {
    0x96f6 || 0x3007 => 0,
    0x4e00 => 1,
    0x4e8c || 0x4e24 => 2,
    0x4e09 => 3,
    0x56db => 4,
    0x4e94 => 5,
    0x516d => 6,
    0x4e03 => 7,
    0x516b => 8,
    0x4e5d => 9,
    _ => null,
  };

  static double? _extractNumber(String input) {
    final match = _Re.number.firstMatch(input);
    return match == null ? null : double.parse(match.group(0)!);
  }

  static int? _extractDuration(String input) {
    final match = _Re.duration.firstMatch(input);
    if (match == null) return null;
    final value = double.parse(match.group(1)!);
    final unit = match.group(2)!.toLowerCase();
    final minutes = unit == '小时' || unit == 'h' || unit.startsWith('hour')
        ? value * 60
        : value;
    return minutes.round();
  }

  static String? _extractTrackerName(String input) {
    for (final pattern in _trackerPatterns) {
      final match = pattern.firstMatch(input);
      if (match != null) return match.group(0);
    }
    return null;
  }

  static String _stripTrackerKeywords(String input) {
    var result = input;
    final trackerName = _extractTrackerName(input);
    if (trackerName != null) {
      result = result.replaceFirst(trackerName, '');
    }
    return _trimLoosePunctuation(_compactWhitespace(result));
  }

  static List<String> _inferTags(String input, ParsedInputType type) {
    final tags = <String>[];

    void add(String tag) {
      if (!tags.contains(tag)) tags.add(tag);
    }

    switch (type) {
      case ParsedInputType.todo:
        add('待办');
      case ParsedInputType.focus:
        add('专注');
      case ParsedInputType.expense:
        add('消费');
      case ParsedInputType.body:
        add('身体');
      case ParsedInputType.sleep:
        add('睡眠');
      case ParsedInputType.mood:
        add('情绪');
      case ParsedInputType.tracker:
      case ParsedInputType.memo:
        break;
    }

    if (type != ParsedInputType.memo) {
      if (_KW.exercise.hasMatch(input)) add('运动');
      if (_KW.dailyHabit.hasMatch(input)) add('习惯');
      if (_KW.learning.hasMatch(input)) add('学习');
      if (_KW.work.hasMatch(input)) add('工作');
      if (_KW.housework.hasMatch(input)) add('生活');
      if (_KW.social.hasMatch(input)) add('社交');
      if (_KW.health.hasMatch(input)) add('健康');
      if (_KW.hobby.hasMatch(input)) add('爱好');
    }

    if (type == ParsedInputType.mood) {
      final neg = RegExp(r'(不好|差|糟糕|低落|烦躁|焦虑|难过|伤心|生气|emo|累|疲惫|紧张|压力)');
      final pos = RegExp(r'(开心|快乐|高兴|满足|幸福|放松|平静|不错|很好|超好|还行|兴奋)');
      final isNeg = neg.hasMatch(input);
      final isPos = pos.hasMatch(input);
      if (isNeg && !isPos) add('负面');
      if (isPos && !isNeg) add('正面');
      if (isNeg && isPos) add('中性');
      if (input.contains('紧张')) add('紧张');
      if (input.contains('开心') || input.contains('快乐')) add('开心');
      if (input.contains('焦虑')) add('焦虑');
      if (input.contains('难过') || input.contains('伤心')) add('难过');
      if (input.contains('生气')) add('生气');
      if (input.contains('平静') || input.contains('放松')) add('放松');
      if (input.contains('累') || input.contains('疲惫')) add('疲惫');
      if (input.contains('兴奋')) add('兴奋');
    }

    if (type == ParsedInputType.expense) {
      if (RegExp(r'(房租|租费|水电|物业|网费|话费|燃气)').hasMatch(input)) {
        add('账单');
      } else if (RegExp(
        r'(午饭|午餐|晚饭|晚餐|早饭|早餐|外卖|食堂|火锅|烧烤|奶茶|咖啡|饮料|零食|水果|餐厅|聚餐|饭店|买水|买菜|饭钱|餐费)',
      ).hasMatch(input)) {
        add('餐饮');
      } else if (RegExp(r'(车费|地铁|公交|打车|加油|停车费|机票|火车票)').hasMatch(input)) {
        add('交通');
      } else if (RegExp(
        r'(衣服|卫衣|裤子|鞋|包|化妆品|护肤品|面膜|代购|淘宝|京东)',
      ).hasMatch(input)) {
        add('购物');
      } else {
        add('支出');
      }
    }

    return tags;
  }

  static final _trackerPatterns = [
    _KW.exercise,
    _KW.dailyHabit,
    _KW.learning,
    _KW.work,
    _KW.housework,
    _KW.social,
    _KW.health,
    _KW.hobby,
  ];

  static double _confidenceFor(ParsedInputType type) => switch (type) {
    ParsedInputType.todo => 0.95,
    ParsedInputType.focus => 0.90,
    ParsedInputType.expense => 0.88,
    ParsedInputType.body => 0.86,
    ParsedInputType.sleep => 0.82,
    ParsedInputType.mood => 0.80,
    ParsedInputType.tracker => 0.78,
    ParsedInputType.memo => 0.50,
  };

  static String _compactWhitespace(String input) =>
      input.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _trimLoosePunctuation(String input) =>
      input.replaceAll(RegExp(r'^[,，。！？!?:：；;\s]+|[,，。！？!?:：；;\s]+$'), '');
}

class _AmountMatch {
  const _AmountMatch({
    required this.amount,
    required this.start,
    required this.end,
    required this.isPrefix,
  });

  final double amount;
  final int start;
  final int end;
  final bool isPrefix;
}
