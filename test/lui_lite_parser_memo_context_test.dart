import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/parser/lui_lite_parser.dart';

void main() {
  group('LuiLiteParser memo context guards', () {
    test('keeps feature planning text as memo even with tracker keywords', () {
      final parsed = LuiLiteParser.parse('添加学习功能，别当成打卡');

      expect(parsed.type, ParsedInputType.memo);
      expect(parsed.content, '添加学习功能，别当成打卡');
    });

    test('keeps forgetfulness text as memo and preserves full content', () {
      final parsed = LuiLiteParser.parse('忘记记录昨天跑步这件事');

      expect(parsed.type, ParsedInputType.memo);
      expect(parsed.content, '忘记记录昨天跑步这件事');
    });

    test('keeps technical debugging note as memo', () {
      final parsed = LuiLiteParser.parse('电脑风扇狂转，检测发现文件大量测试文件，没加入规则，git一直刷新状态');

      expect(parsed.type, ParsedInputType.memo);
      expect(parsed.content, '电脑风扇狂转，检测发现文件大量测试文件，没加入规则，git一直刷新状态');
    });

    test('keeps salary reimbursement policy with amounts as memo', () {
      final parsed = LuiLiteParser.parse('10000元以上工资可申报1000的房贷报销');

      expect(parsed.type, ParsedInputType.memo);
      expect(parsed.metadata['amount'], isNull);
      expect(parsed.metadata['expenseItems'], isNull);
    });
  });
}
