// Bulk test: 50+ realistic Chinese life-logging inputs.
// Validates that the parser correctly types, tags, and extracts
// metadata from everyday sentences a real user would speak or type.
//
// Run: flutter test test/bulk_life_data_test.dart

import 'package:dayline_app/core/parser/lui_lite_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Each entry: (input, expected_type, expected_tags_contains, metadata_checks)
typedef _Case = (String, ParsedInputType, List<String>, Map<String, dynamic>);
final _cases = <_Case>[

  // ── Mood ──
  ('心情不错', ParsedInputType.mood, ['正面'], {}),
  ('今天有点焦虑', ParsedInputType.mood, ['焦虑', '负面'], {}),
  ('emo了 不想说话', ParsedInputType.mood, ['负面'], {}),
  ('心情低落', ParsedInputType.mood, ['负面'], {}),
  ('今天超开心！', ParsedInputType.mood, ['正面', '开心'], {}),
  ('感觉紧张 要上台演讲了', ParsedInputType.mood, ['负面', '紧张'], {}),
  ('心情很平静 今天过得安稳', ParsedInputType.mood, ['正面', '放松'], {}),
  ('好累 今天跑了三个地方', ParsedInputType.mood, ['负面', '疲惫'], {}),
  ('心情烦躁 #情绪', ParsedInputType.mood, ['情绪'], {}),

  // ── Expense ──
  ('午饭 35元 #支出', ParsedInputType.expense, ['支出'], {'amount': 35.0}),
  ('RMB 128.5 买书', ParsedInputType.expense, ['消费'], {'amount': 128.5}),
  ('花了88元 买了件卫衣 #购物', ParsedInputType.expense, ['购物'], {'amount': 88.0}),
  ('外卖 28元 #午餐', ParsedInputType.expense, ['午餐'], {}),
  ('打车费 45元', ParsedInputType.expense, ['交通'], {}),
  ('买了杯咖啡 18块', ParsedInputType.expense, ['餐饮'], {}),
  ('消费 268 元 聚餐', ParsedInputType.expense, ['餐饮'], {'amount': 268.0}),
  ('水电费 150元', ParsedInputType.expense, ['账单'], {}),

  // ── Todo ──
  ('todo 买牛奶 #家务', ParsedInputType.todo, ['家务'], {}),
  ('待办：提交报销', ParsedInputType.todo, ['待办'], {}),
  ('任务 写周报', ParsedInputType.todo, ['待办'], {}),
  ('记得带伞', ParsedInputType.todo, ['待办'], {}),
  ('要做 备份照片', ParsedInputType.todo, ['待办'], {}),

  // ── Focus ──
  ('番茄 阅读', ParsedInputType.focus, ['专注'], {}),
  ('专注 写代码 25min', ParsedInputType.focus, ['专注'], {'durationMinutes': 25}),
  ('心流 编程 1小时', ParsedInputType.focus, ['专注'], {'durationMinutes': 60}),
  ('番茄工作25分钟', ParsedInputType.focus, ['专注'], {'durationMinutes': 25}),

  // ── Body ──
  ('体重 70.5kg', ParsedInputType.body, ['身体'], {'value': 70.5}),
  ('血压 120/80', ParsedInputType.body, ['身体'], {}),
  ('血糖 5.6 早上空腹', ParsedInputType.body, ['身体'], {'metric': 'blood_sugar'}),

  // ── Sleep ──
  ('23点 睡觉 #睡眠', ParsedInputType.sleep, ['睡眠'], {}),
  ('熬夜到两点', ParsedInputType.sleep, ['睡眠'], {}),
  ('午睡25分钟', ParsedInputType.sleep, ['睡眠'], {}),
  ('失眠了 凌晨才睡着', ParsedInputType.sleep, ['睡眠'], {}),
  ('没睡好 醒了三次', ParsedInputType.sleep, ['睡眠'], {}),

  // ── Tracker — exercise ──
  ('9:30 跑步 30分钟 #健康', ParsedInputType.tracker, ['健康'], {'durationMinutes': 30}),
  ('跑步3分钟', ParsedInputType.tracker, ['运动'], {'durationMinutes': 3}),
  ('健身 1小时 练胸', ParsedInputType.tracker, ['运动'], {'durationMinutes': 60}),
  ('瑜伽 45min', ParsedInputType.tracker, ['运动'], {'durationMinutes': 45}),
  ('游泳 2000米', ParsedInputType.tracker, ['运动'], {}),

  // ── Tracker — learning ──
  ('学习Flutter 2小时', ParsedInputType.tracker, ['学习'], {'durationMinutes': 120}),
  ('看书30分钟', ParsedInputType.tracker, ['学习'], {'durationMinutes': 30}),
  ('背单词 20分钟 #英语', ParsedInputType.tracker, ['英语'], {}),
  ('做笔记 机器学习笔记整理', ParsedInputType.tracker, ['学习'], {}),

  // ── Tracker — work ──
  ('开会 产品评审', ParsedInputType.tracker, ['工作'], {}),
  ('加班 写了2小时代码', ParsedInputType.tracker, ['工作'], {'durationMinutes': 120}),
  ('写周报 本周总结', ParsedInputType.tracker, ['工作'], {}),
  ('汇报 季度数据', ParsedInputType.tracker, ['工作'], {}),

  // ── Tracker — daily habit ──
  ('起床 7:00', ParsedInputType.tracker, ['习惯'], {}),
  ('喝够了8杯水', ParsedInputType.tracker, ['习惯'], {}),
  ('吃药 维生素', ParsedInputType.tracker, ['习惯'], {}),
  ('冥想 早上冥想10分钟', ParsedInputType.tracker, ['习惯'], {'durationMinutes': 10}),
  ('写日记 今天发生了很多事', ParsedInputType.tracker, ['习惯'], {}),

  // ── Tracker — housework ──
  ('打扫卫生 拖地擦窗', ParsedInputType.tracker, ['生活'], {}),
  ('洗衣服 换床单', ParsedInputType.tracker, ['生活'], {}),
  ('买菜 超市 ', ParsedInputType.tracker, ['生活'], {}),

  // ── Tracker — social ──
  ('聚会 跟老同学吃饭', ParsedInputType.tracker, ['社交'], {}),
  ('约会 看电影', ParsedInputType.tracker, ['社交'], {}),

  // ── Tracker — health ──
  ('体检 年度体检', ParsedInputType.tracker, ['健康'], {}),

  // ── Tracker — hobby ──
  ('画画 练习素描', ParsedInputType.tracker, ['爱好'], {}),
  ('练琴 车尔尼599 #音乐', ParsedInputType.tracker, ['音乐'], {}),

  // ── Memo fallback ──
  ('今天有点冷', ParsedInputType.memo, [], {}),
  ('晚上想去看星星', ParsedInputType.memo, [], {}),
  ('收到了一封邮件', ParsedInputType.memo, [], {}),
];

void main() {
  group('Bulk life data — parser validation', () {
    for (final (i, (input, expectedType, expectedTags, checks)) in _cases.indexed) {
      test('[${(i + 1).toString().padLeft(2, '0')}] "$input"', () {
        final parsed = LuiLiteParser.parse(input);

        expect(
          parsed.type,
          expectedType,
          reason: 'type mismatch for "$input"',
        );

        for (final tag in expectedTags) {
          expect(
            parsed.tags,
            contains(tag),
            reason: '"$input" should have tag "$tag", got ${parsed.tags}',
          );
        }

        // Dynamic metadata checks
        for (final entry in checks.entries) {
          if (entry.key == 'amount') {
            expect(
              parsed.metadata['amount'],
              closeTo(entry.value as double, 1e-4),
              reason: 'amount mismatch for "$input"',
            );
          } else if (entry.key == 'durationMinutes') {
            expect(
              parsed.metadata['durationMinutes'],
              entry.value,
              reason: 'durationMinutes mismatch for "$input"',
            );
          } else if (entry.key == 'metric') {
            expect(
              parsed.metadata['metric'],
              entry.value,
              reason: 'metric mismatch for "$input"',
            );
          }
        }
      });
    }
  });

  test('all test cases are valid and non-empty', () {
    expect(_cases.length, greaterThanOrEqualTo(55));
    for (final (input, _, _, _) in _cases) {
      expect(input.trim(), isNotEmpty);
    }
  });
}
