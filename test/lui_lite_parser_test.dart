import 'package:dayline_app/core/parser/lui_lite_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LuiLiteParser — tags & time', () {
    test('extracts Chinese and English hash tags', () {
      final parsed = LuiLiteParser.parse('今天写了日记 #生活 #daily');
      expect(parsed.tags, ['生活', 'daily']);
    });

    test('normalizes HH:mm colon time', () {
      expect(LuiLiteParser.parse('18:05 开会').time, '18:05');
    });

    test('normalizes H:mm time with zero-pad', () {
      expect(LuiLiteParser.parse('8:30 早餐').time, '08:30');
    });

    test('normalizes H点 Chinese time', () {
      expect(LuiLiteParser.parse('9点 晨会').time, '09:00');
    });

    test('normalizes H点半 Chinese half-hour', () {
      expect(LuiLiteParser.parse('7点半 跑步').time, '07:30');
    });

    test('strips leading # in tag normalization', () {
      final parsed = LuiLiteParser.parse('#健康 ##运动');
      expect(parsed.tags, ['健康', '运动']);
    });
  });

  group('LuiLiteParser — todo', () {
    test('recognizes English todo prefix', () {
      final p = LuiLiteParser.parse('todo 买牛奶 #家务');
      expect(p.type, ParsedInputType.todo);
      expect(p.content, '买牛奶');
      expect(p.tags, ['家务']);
    });

    test('recognizes 待办 with colon separator', () {
      final p = LuiLiteParser.parse('待办：提交报销');
      expect(p.type, ParsedInputType.todo);
      expect(p.content, '提交报销');
    });

    test('recognizes 任务 prefix', () {
      expect(LuiLiteParser.parse('任务 写周报').type, ParsedInputType.todo);
    });

    test('recognizes 记得 without trailing space', () {
      final p = LuiLiteParser.parse('记得带伞');
      expect(p.type, ParsedInputType.todo);
      expect(p.content, '带伞');
    });

    test('recognizes 要做 prefix', () {
      expect(LuiLiteParser.parse('要做 备份照片').type, ParsedInputType.todo);
    });
  });

  group('LuiLiteParser — focus', () {
    test('detects 番茄 keyword', () {
      expect(LuiLiteParser.parse('番茄 阅读').type, ParsedInputType.focus);
    });

    test('detects focus keyword + duration', () {
      final p = LuiLiteParser.parse('focus 写代码 25min');
      expect(p.type, ParsedInputType.focus);
      expect(p.metadata['durationMinutes'], 25);
    });

    test('detects 专注 keyword', () {
      final p = LuiLiteParser.parse('专注 写报告 45分钟');
      expect(p.type, ParsedInputType.focus);
      expect(p.metadata['durationMinutes'], 45);
    });

    test('detects 心流 keyword', () {
      expect(LuiLiteParser.parse('心流 编程 1小时').type, ParsedInputType.focus);
    });

    test('converts 小时 to minutes', () {
      final p = LuiLiteParser.parse('专注 设计 2小时');
      expect(p.metadata['durationMinutes'], 120);
    });
  });

  group('LuiLiteParser — expense', () {
    test('extracts 元 suffix amount', () {
      final p = LuiLiteParser.parse('午饭 35元 #支出');
      expect(p.type, ParsedInputType.expense);
      expect(p.metadata['amount'], 35.0);
    });

    test('extracts RMB prefix amount', () {
      final p = LuiLiteParser.parse('RMB 128.5 买书');
      expect(p.type, ParsedInputType.expense);
      expect(p.metadata['amount'], 128.5);
    });

    test('detects 花了 keyword', () {
      final p = LuiLiteParser.parse('买了华为耳机 花了999块');
      expect(p.type, ParsedInputType.expense);
      expect(p.metadata['amount'], 999.0);
    });

    test('detects 买了 keyword', () {
      expect(LuiLiteParser.parse('买了杯咖啡 18块').type, ParsedInputType.expense);
    });

    test('detects 消费 keyword', () {
      expect(LuiLiteParser.parse('消费 268 元 聚餐').type, ParsedInputType.expense);
    });

    test('infers 餐饮 tag for food-related expense', () {
      final p = LuiLiteParser.parse('外卖 28元');
      expect(p.tags, contains('餐饮'));
    });

    test('infers 交通 tag for transport expense', () {
      final p = LuiLiteParser.parse('打车费 45元');
      expect(p.tags, contains('交通'));
    });
  });

  group('LuiLiteParser — body', () {
    test('detects 体重 and extracts value', () {
      final p = LuiLiteParser.parse('体重 70.5kg');
      expect(p.type, ParsedInputType.body);
      expect(p.metadata['value'], 70.5);
      expect(p.metadata['metric'], 'weight');
    });

    test('detects weight keyword', () {
      final p = LuiLiteParser.parse('weight 68');
      expect(p.type, ParsedInputType.body);
      expect(p.metadata['value'], 68.0);
    });

    test('detects 血压 keyword', () {
      final p = LuiLiteParser.parse('血压 120/80');
      expect(p.type, ParsedInputType.body);
      expect(p.metadata['metric'], 'blood_pressure');
    });

    test('detects 血糖 keyword', () {
      final p = LuiLiteParser.parse('血糖 5.6');
      expect(p.type, ParsedInputType.body);
      expect(p.metadata['metric'], 'blood_sugar');
    });
  });

  group('LuiLiteParser — sleep', () {
    test('detects basic sleep keyword', () {
      final p = LuiLiteParser.parse('23点 睡觉 #睡眠');
      expect(p.type, ParsedInputType.sleep);
      expect(p.time, '23:00');
    });

    test('detects 熬夜 keyword', () {
      expect(LuiLiteParser.parse('熬夜到两点').type, ParsedInputType.sleep);
    });

    test('detects 午睡 keyword', () {
      expect(LuiLiteParser.parse('午睡25分钟').type, ParsedInputType.sleep);
    });

    test('detects 失眠 keyword', () {
      expect(LuiLiteParser.parse('失眠了 凌晨才睡着').type, ParsedInputType.sleep);
    });
  });

  group('LuiLiteParser — mood (new)', () {
    test('detects 心情不错', () {
      final p = LuiLiteParser.parse('心情不错');
      expect(p.type, ParsedInputType.mood);
      expect(p.tags, contains('正面'));
    });

    test('detects 焦虑情绪', () {
      final p = LuiLiteParser.parse('今天有点焦虑');
      expect(p.type, ParsedInputType.mood);
      expect(p.tags, contains('焦虑'));
    });

    test('detects emo了', () {
      final p = LuiLiteParser.parse('emo了');
      expect(p.type, ParsedInputType.mood);
      expect(p.tags, contains('负面'));
    });

    test('detects 心情低落 with negative tag', () {
      final p = LuiLiteParser.parse('心情低落 不想说话');
      expect(p.type, ParsedInputType.mood);
      expect(p.tags, contains('负面'));
    });

    test('detects 开心 as mood', () {
      final p = LuiLiteParser.parse('今天超开心！');
      expect(p.type, ParsedInputType.mood);
      expect(p.tags, contains('正面'));
    });
  });

  group('LuiLiteParser — tracker keyword expansion', () {
    test('recognizes 学习 as tracker', () {
      final p = LuiLiteParser.parse('学习Flutter 2小时');
      expect(p.type, ParsedInputType.tracker);
      expect(p.tags, contains('学习'));
    });

    test('recognizes 看书 as tracker', () {
      expect(LuiLiteParser.parse('看书30分钟').type, ParsedInputType.tracker);
    });

    test('recognizes 开会 as tracker', () {
      final p = LuiLiteParser.parse('开会 产品评审');
      expect(p.type, ParsedInputType.tracker);
      expect(p.tags, contains('工作'));
    });

    test('recognizes 打扫 as tracker', () {
      final p = LuiLiteParser.parse('打扫卫生');
      expect(p.type, ParsedInputType.tracker);
      expect(p.tags, contains('生活'));
    });

    test('recognizes 聚会 as tracker', () {
      final p = LuiLiteParser.parse('聚会 跟老同学吃饭');
      expect(p.type, ParsedInputType.tracker);
      expect(p.tags, contains('社交'));
    });

    test('recognizes 看病 as tracker', () {
      expect(LuiLiteParser.parse('去体检').type, ParsedInputType.tracker);
    });

    test('recognizes 画画 as tracker', () {
      final p = LuiLiteParser.parse('画画 练习素描');
      expect(p.type, ParsedInputType.tracker);
      expect(p.tags, contains('爱好'));
    });
  });

  group('LuiLiteParser — memo fallback', () {
    test('generic text falls to memo with low confidence', () {
      final p = LuiLiteParser.parse('今天有点冷');
      expect(p.type, ParsedInputType.memo);
      expect(p.confidence, 0.5);
    });
  });

  group('LuiLiteParser — complex real-world sentences', () {
    test('9:30 跑步 30分钟 #健康', () {
      final p = LuiLiteParser.parse('9:30 跑步 30分钟 #健康');
      expect(p.type, ParsedInputType.tracker);
      expect(p.time, '09:30');
      expect(p.metadata['durationMinutes'], 30);
      expect(p.tags, ['健康']);
    });

    test('花了88元 买了件卫衣 #购物', () {
      final p = LuiLiteParser.parse('花了88元 买了件卫衣 #购物');
      expect(p.type, ParsedInputType.expense);
      expect(p.metadata['amount'], 88.0);
      expect(p.tags, ['购物']);
    });

    test('今天很开心 #心情 #日记', () {
      final p = LuiLiteParser.parse('今天很开心 #心情 #日记');
      expect(p.type, ParsedInputType.mood);
      expect(p.tags, ['心情', '日记']);
    });

    test('起床 7:00', () {
      final p = LuiLiteParser.parse('起床 7:00');
      expect(p.type, ParsedInputType.tracker);
      expect(p.time, '07:00');
    });

    test('加班 写了2小时代码', () {
      final p = LuiLiteParser.parse('加班 写了2小时代码');
      expect(p.type, ParsedInputType.tracker);
      expect(p.tags, contains('工作'));
      expect(p.metadata['durationMinutes'], 120);
    });
  });
}
