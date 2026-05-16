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
  });
}
