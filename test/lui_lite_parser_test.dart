import 'package:dayline_app/core/parser/lui_lite_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LuiLiteParser', () {
    test('extracts hash tags from input', () {
      final parsed = LuiLiteParser.parse('今天写了日记 #生活 #daily');

      expect(parsed.tags, ['生活', 'daily']);
      expect(parsed.type, ParsedInputType.memo);
    });

    test('normalizes HH:mm time', () {
      final parsed = LuiLiteParser.parse('18:05 开会');

      expect(parsed.time, '18:05');
    });

    test('normalizes H:mm time', () {
      final parsed = LuiLiteParser.parse('8:30 早餐');

      expect(parsed.time, '08:30');
    });

    test('normalizes H点 time', () {
      final parsed = LuiLiteParser.parse('9点 晨会');

      expect(parsed.time, '09:00');
    });

    test('normalizes H点半 time', () {
      final parsed = LuiLiteParser.parse('7点半 跑步');

      expect(parsed.time, '07:30');
    });

    test('recognizes todo prefix in English', () {
      final parsed = LuiLiteParser.parse('todo 买牛奶 #家务');

      expect(parsed.type, ParsedInputType.todo);
      expect(parsed.content, '买牛奶');
      expect(parsed.tags, ['家务']);
    });

    test('recognizes 待办 prefix', () {
      final parsed = LuiLiteParser.parse('待办：提交报销');

      expect(parsed.type, ParsedInputType.todo);
      expect(parsed.content, '提交报销');
    });

    test('recognizes 任务 prefix', () {
      final parsed = LuiLiteParser.parse('任务 写周报');

      expect(parsed.type, ParsedInputType.todo);
    });

    test('recognizes 记得 prefix without space', () {
      final parsed = LuiLiteParser.parse('记得带伞');

      expect(parsed.type, ParsedInputType.todo);
      expect(parsed.content, '带伞');
    });

    test('recognizes 要做 prefix', () {
      final parsed = LuiLiteParser.parse('要做 备份照片');

      expect(parsed.type, ParsedInputType.todo);
    });

    test('todo has priority over focus', () {
      final parsed = LuiLiteParser.parse('todo 25分钟整理桌面');

      expect(parsed.type, ParsedInputType.todo);
    });

    test('recognizes focus from 番茄', () {
      final parsed = LuiLiteParser.parse('番茄 阅读');

      expect(parsed.type, ParsedInputType.focus);
    });

    test('recognizes focus from focus keyword', () {
      final parsed = LuiLiteParser.parse('focus 写代码 25min');

      expect(parsed.type, ParsedInputType.focus);
      expect(parsed.metadata['durationMinutes'], 25);
    });

    test('recognizes expense and extracts amount with 元', () {
      final parsed = LuiLiteParser.parse('午饭 35元 #支出');

      expect(parsed.type, ParsedInputType.expense);
      expect(parsed.metadata['amount'], 35.0);
      expect(parsed.tags, ['支出']);
    });

    test('recognizes expense and extracts amount with RMB prefix', () {
      final parsed = LuiLiteParser.parse('RMB 128.5 买书');

      expect(parsed.type, ParsedInputType.expense);
      expect(parsed.metadata['amount'], 128.5);
    });

    test('expense has priority over body', () {
      final parsed = LuiLiteParser.parse('体重秤电池 12元');

      expect(parsed.type, ParsedInputType.expense);
      expect(parsed.metadata['amount'], 12.0);
    });

    test('recognizes body and extracts weight number', () {
      final parsed = LuiLiteParser.parse('体重 70.5kg');

      expect(parsed.type, ParsedInputType.body);
      expect(parsed.metadata['value'], 70.5);
    });

    test('recognizes body from weight keyword', () {
      final parsed = LuiLiteParser.parse('weight 68');

      expect(parsed.type, ParsedInputType.body);
      expect(parsed.metadata['value'], 68.0);
    });

    test('recognizes sleep from sleep keywords', () {
      final parsed = LuiLiteParser.parse('23点 睡觉 #睡眠');

      expect(parsed.type, ParsedInputType.sleep);
      expect(parsed.time, '23:00');
      expect(parsed.tags, ['睡眠']);
    });

    test('recognizes tracker keywords and defaults unknown input to memo', () {
      final tracker = LuiLiteParser.parse('喝水 250ml');
      final memo = LuiLiteParser.parse('今天心情不错');

      expect(tracker.type, ParsedInputType.tracker);
      expect(memo.type, ParsedInputType.memo);
      expect(memo.confidence, lessThan(tracker.confidence));
    });

    test('recognizes running duration as a tracker instead of memo', () {
      final parsed = LuiLiteParser.parse('跑步3分钟');

      expect(parsed.type, ParsedInputType.tracker);
      expect(parsed.content, '跑步');
      expect(parsed.metadata['durationMinutes'], 3);
      expect(parsed.tags, ['运动']);
    });

    test('does not treat exercise duration as focus without focus keyword', () {
      final parsed = LuiLiteParser.parse('跑步25分钟');

      expect(parsed.type, ParsedInputType.tracker);
      expect(parsed.content, '跑步');
      expect(parsed.metadata['durationMinutes'], 25);
    });
  });
}
