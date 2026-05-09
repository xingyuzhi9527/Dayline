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

/// Shared Regex patterns — compiled once.
abstract final class _Re {
  static final tag = RegExp(r'[#＃]([A-Za-z0-9_一-鿿\p{Emoji}]+)', unicode: true);
  static final colonTime = RegExp(r'([01]?\d|2[0-3])[:：]([0-5]\d)');
  static final chineseTime = RegExp(r'([01]?\d|2[0-3])点(半)?');
  static final todoPrefix = RegExp(
    r'^(todo|待办|任务|记得|要做|别忘了|需要|必须|准备|提醒|提醒我|请|要)\s*[:：-]?\s*',
    caseSensitive: false,
  );
  static final duration = RegExp(
    r'(\d+(?:\.\d+)?)\s*(min|mins|minute|minutes|分钟|小时|hour|hours|h)',
    caseSensitive: false,
  );
  static final amountPrefix = RegExp(r'(?:¥|￥|RMB)\s*(\d+(?:\.\d+)?)', caseSensitive: false);
  static final amountSuffix = RegExp(r'(\d+(?:\.\d+)?)\s*(?:元|块|块钱)');
  static final number = RegExp(r'\d+(?:\.\d+)?');
}

/// Keyword tables — each compiled once.
abstract final class _KW {
  // ---------- expense ----------
  static final expense = RegExp(r'(元|块|¥|￥|RMB|花了|买了|消费|花费|用了|块钱|支出)');

  // ---------- focus ----------
  static final focus = RegExp(r'(番茄|专注|focus|pomodoro|心流|沉浸)');

  // ---------- body ----------
  static final body = RegExp(r'(体重|weight|身高|血压|血糖|心率|体温|体脂)');
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

  // ---------- sleep ----------
  static final sleep = RegExp(r'(睡觉|入睡|醒来|睡了|熬夜|午睡|小憩|nap|失眠|没睡好)');

  // ---------- mood ----------
  static final mood = RegExp(r'^(今天|今日|现在)?(心情|情绪|感觉|状态)(不错|很好|一般|不好|很差|还行|超好|超棒|糟糕|低落|烦躁|焦虑|平静|放松|开心|快乐|难过|伤心|生气|emo|累了|疲惫|紧张|兴奋)');
  static final moodCompact = RegExp(r'(心情不错|心情很好|心情一般|心情不好|心情很差|心情还行|心情超好|心情糟糕|心情低落|心情烦躁|心情焦虑|心情平静|心情放松|心情开心|心情快乐|心情难过|心情伤心|心情生气|emo了|累了|好累|疲惫|紧张|兴奋|开心|难过|焦虑|烦躁|平静|高兴|悲伤|沮丧|愤怒|满足|幸福|压抑)');

  // ---------- tracker by category ----------
  // Exercise / sport
  static final exercise = RegExp(r'(跑步|慢跑|运动|健身|训练|瑜伽|游泳|骑行|骑车|散步|步行|拉伸|深蹲|俯卧撑|跳绳|打球|篮球|足球|羽毛球|乒乓球|跳舞|拳击|普拉提|攀岩|冲浪|滑雪|溜冰)');
  // Daily habit
  static final dailyHabit = RegExp(r'(起床|喝[水了够]+\d*杯?水|喝[了够]?\d*杯?水|喝水|喝[水茶]|吃药|冥想|今日计划|写日记|日记|复盘|称体重|涂防晒|护肤|泡脚|早睡|早起|吃早餐|吃早饭|不吃晚餐|断食|戒糖|不喝奶茶|不喝酒|不抽烟)');
  // Learning / productivity
  static final learning = RegExp(r'(学习|看书|读书|阅读|上课|听课|写作业|做题|背单词|练口语|写代码|编程|刷题|考证|备考|复习|预习|做笔记|写文章|写作)');
  // Work
  static final work = RegExp(r'(开会|上班|下班|加班|出差|汇报|报告|周报|日报|项目|方案|提案|客户|合同|面试|入职|离职|调休|请假)');
  // House / life
  static final housework = RegExp(r'(打扫|整理|收拾|洗衣服|做饭|洗碗|买菜|倒垃圾|拖地|擦窗|换床单|浇花|遛狗|铲屎|喂猫|理)');
  // Social
  static final social = RegExp(r'(聚会|约会|见面|聊天|打电话|视频|约饭|约火锅|约咖啡|逛街|看电影|看剧|追剧|KTV|唱歌|去玩)');
  // Health
  static final health = RegExp(r'(体检|看医生|挂号|吃药|打针|输液|理疗|按摩|拔罐|针灸|看牙|配眼镜)');
  // Hobby
  static final hobby = RegExp(r'(练琴|画画|摄影|拍照|书法|手工|烘焙|养花|钓鱼|下棋|桌游|剧本杀|打游戏|弹吉他|弹钢琴|拉小提琴)');

  // Combined tracker (all non-memo types pooled for inference)
  static final tracker = RegExp([
    exercise, dailyHabit, learning, work, housework, social, health, hobby,
  ].map((r) => r.pattern).join('|'));
}

class LuiLiteParser {
  const LuiLiteParser._();

  // ---------------------------------------------------------------
  // Public entry point
  // ---------------------------------------------------------------

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

  // ---------------------------------------------------------------
  // Tag extraction
  // ---------------------------------------------------------------

  static List<String> _extractTags(String input) {
    return _Re.tag
        .allMatches(input)
        .map((m) => m.group(1)!.replaceFirst(RegExp(r'^[#＃]+'), ''))
        .where((t) => t.isNotEmpty && t.length <= 20)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------
  // Time extraction
  // ---------------------------------------------------------------

  static String? _extractTime(String input) {
    final colon = _Re.colonTime.firstMatch(input);
    if (colon != null) {
      return _fmt(int.parse(colon.group(1)!), int.parse(colon.group(2)!));
    }
    final ch = _Re.chineseTime.firstMatch(input);
    if (ch != null) {
      return _fmt(int.parse(ch.group(1)!), ch.group(2) == null ? 0 : 30);
    }
    return null;
  }

  static String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------
  // Type inference (ordered by priority)
  // ---------------------------------------------------------------

  static ParsedInputType _inferType(String input, Map<String, Object?> meta) {
    // 1. Explicit todo prefix
    if (_Re.todoPrefix.hasMatch(input)) return ParsedInputType.todo;

    // 2. Focus keyword
    if (_KW.focus.hasMatch(input)) {
      final d = _extractDuration(input);
      if (d != null) meta['durationMinutes'] = d;
      return ParsedInputType.focus;
    }

    // 3. Expense keyword + amount
    if (_KW.expense.hasMatch(input)) {
      final a = _extractAmount(input);
      if (a != null) meta['amount'] = a;
      return ParsedInputType.expense;
    }

    // 4. Body metric
    if (_KW.body.hasMatch(input)) {
      final v = _extractNumber(input);
      if (v != null) meta['value'] = v;
      meta['metric'] = _resolveBodyMetric(input);
      return ParsedInputType.body;
    }

    // 5. Sleep keyword
    if (_KW.sleep.hasMatch(input)) return ParsedInputType.sleep;

    // 6. Mood keyword
    if (_KW.moodCompact.hasMatch(input) || _KW.mood.hasMatch(input)) {
      return ParsedInputType.mood;
    }

    // 7. Tracker keyword
    if (_KW.tracker.hasMatch(input)) {
      final d = _extractDuration(input);
      if (d != null) meta['durationMinutes'] = d;
      return ParsedInputType.tracker;
    }

    return ParsedInputType.memo;
  }

  static String? _resolveBodyMetric(String input) {
    for (final entry in _KW.bodyMetric.entries) {
      if (input.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Content extraction
  // ---------------------------------------------------------------

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
      final name = _extractTrackerName(content);
      if (name != null) return name;
    }
    if (type == ParsedInputType.body) {
      content = content.replaceAll(_Re.number, '');
    }

    return _trimLoosePunctuation(_compactWhitespace(content));
  }

  // ---------------------------------------------------------------
  // Amount / number / duration extraction
  // ---------------------------------------------------------------

  static double? _extractAmount(String input) {
    final pre = _Re.amountPrefix.firstMatch(input);
    if (pre != null) return double.parse(pre.group(1)!);
    final suf = _Re.amountSuffix.firstMatch(input);
    if (suf != null) return double.parse(suf.group(1)!);
    return null;
  }

  static double? _extractNumber(String input) {
    final m = _Re.number.firstMatch(input);
    return m == null ? null : double.parse(m.group(0)!);
  }

  static int? _extractDuration(String input) {
    final m = _Re.duration.firstMatch(input);
    if (m == null) return null;
    final value = int.parse(m.group(1)!);
    final unit = m.group(2)!.toLowerCase();
    if (unit == '小时' || unit == 'h' || unit.startsWith('hour')) return value * 60;
    return value;
  }

  // ---------------------------------------------------------------
  // Tracker name
  // ---------------------------------------------------------------

  static String? _extractTrackerName(String input) {
    final patterns = [
      _KW.exercise, _KW.dailyHabit, _KW.learning,
      _KW.work, _KW.housework, _KW.social, _KW.health, _KW.hobby,
    ];
    for (final re in patterns) {
      final m = re.firstMatch(input);
      if (m != null) return m.group(0);
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Smart tag inference
  // ---------------------------------------------------------------

  static List<String> _inferTags(String input, ParsedInputType type) {
    final tags = <String>[];

    void add(String tag) {
      if (!tags.contains(tag)) tags.add(tag);
    }

    // --- type-based defaults ---
    switch (type) {
      case ParsedInputType.todo:       add('待办'); break;
      case ParsedInputType.focus:      add('专注'); break;
      case ParsedInputType.expense:    add('消费'); break;
      case ParsedInputType.body:       add('身体'); break;
      case ParsedInputType.sleep:      add('睡眠'); break;
      case ParsedInputType.mood:       add('情绪'); break;
      case ParsedInputType.tracker:
      case ParsedInputType.memo:
        break; // inferred below
    }

    // --- content-based inference ---
    if (_KW.exercise.hasMatch(input)) add('运动');
    if (_KW.dailyHabit.hasMatch(input)) add('习惯');
    if (_KW.learning.hasMatch(input)) add('学习');
    if (_KW.work.hasMatch(input)) add('工作');
    if (_KW.housework.hasMatch(input)) add('生活');
    if (_KW.social.hasMatch(input)) add('社交');
    if (_KW.health.hasMatch(input)) add('健康');
    if (_KW.hobby.hasMatch(input)) add('爱好');

    // --- mood refinement ---
    if (type == ParsedInputType.mood) {
      final neg = RegExp(r'(不好|差|糟糕|低落|烦躁|焦虑|难过|伤心|生气|emo|沮丧|愤怒|悲伤|压抑|紧张|累了|好累|疲惫|疲惫)');
      final pos = RegExp(r'(开心|快乐|高兴|满足|幸福|兴奋|放松|平静|不错|很好|超好|超棒|还行)');
      final isNeg = neg.hasMatch(input);
      final isPos = pos.hasMatch(input);
      if (isNeg && !isPos) {
        add('负面');
      } else if (isPos && !isNeg) {
        add('正面');
      } else if (isNeg && isPos) {
        add('中性');
      }
      // Also add specific mood keywords
      if (input.contains('紧张')) add('紧张');
      if (input.contains('开心') || input.contains('快乐')) add('开心');
      if (input.contains('焦虑')) add('焦虑');
      if (input.contains('难过') || input.contains('伤心')) add('难过');
      if (input.contains('生气') || input.contains('愤怒')) add('生气');
      if (input.contains('平静') || input.contains('放松')) add('放松');
      if (input.contains('累') || input.contains('疲惫')) add('疲惫');
      if (input.contains('兴奋')) add('兴奋');
    }

    // --- expense refinement ---
    if (type == ParsedInputType.expense) {
      if (RegExp(r'(房[租费]|水电[费]?|物业[费]?|网费|话费|燃气[费]?)').hasMatch(input)) {
        add('账单');
      } else if (RegExp(r'(午饭|晚餐|早饭|早餐|中饭|晚饭|外卖|食堂|火锅|烧烤|奶茶|咖啡|饮料|零食|水果|餐厅|聚餐|饭店|买水|买菜|买菜|饭钱|餐费)').hasMatch(input)) {
        add('餐饮');
      } else if (RegExp(r'(车费|地铁|公交|打车|加油|停车费|机票|火车票)').hasMatch(input)) {
        add('交通');
      } else if (RegExp(r'(衣服|裤子|鞋|包|化妆品|护肤品|面膜|代购|淘宝|京东)').hasMatch(input)) {
        add('购物');
      } else {
        add('支出');
      }
    }

    return tags;
  }

  // ---------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------

  static double _confidenceFor(ParsedInputType type) => switch (type) {
    ParsedInputType.todo    => 0.95,
    ParsedInputType.focus   => 0.90,
    ParsedInputType.expense => 0.88,
    ParsedInputType.body    => 0.86,
    ParsedInputType.sleep   => 0.82,
    ParsedInputType.mood    => 0.80,
    ParsedInputType.tracker => 0.78,
    ParsedInputType.memo    => 0.50,
  };

  static String _compactWhitespace(String input) =>
      input.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _trimLoosePunctuation(String input) =>
      input.replaceAll(RegExp(r'^[,，。:：;；\s]+|[,，。:：;；\s]+$'), '');
}
