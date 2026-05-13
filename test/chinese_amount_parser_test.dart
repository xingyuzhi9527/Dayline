import 'package:liflow_app/core/parser/lui_lite_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _u(List<int> codePoints) => String.fromCharCodes(codePoints);

void main() {
  group('LuiLiteParser Chinese spoken amounts', () {
    test('extracts ten yuan spoken amount', () {
      final parsed = LuiLiteParser.parse(
        _u([0x5341, 0x5143, 0x7684, 0x5c0f, 0x5403]),
      );

      expect(parsed.type, ParsedInputType.expense);
      expect(parsed.metadata['amount'], 10.0);
    });

    test('extracts common Chinese amount forms from STT text', () {
      final cases = {
        _u([0x5341, 0x516b, 0x5143, 0x4e70, 0x5496, 0x5561]): 18.0,
        _u([0x4e8c, 0x5341, 0x5757, 0x624b, 0x673a, 0x58f3]): 20.0,
        _u([0x4e00, 0x767e, 0x4e8c, 0x5341, 0x4e09, 0x5143]): 123.0,
        _u([0x4e24, 0x767e, 0x96f6, 0x4e94, 0x5143]): 205.0,
      };

      for (final entry in cases.entries) {
        final parsed = LuiLiteParser.parse(entry.key);
        expect(parsed.type, ParsedInputType.expense, reason: entry.key);
        expect(parsed.metadata['amount'], entry.value, reason: entry.key);
      }
    });
  });
}
