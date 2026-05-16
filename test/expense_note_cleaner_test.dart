import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/parser/expense_note_cleaner.dart';

void main() {
  group('cleanExpenseNote', () {
    test('removes stale arabic amount from expense note', () {
      expect(cleanExpenseNote('午饭 35元'), '午饭');
      expect(cleanExpenseNote('买了杯咖啡 18块'), '买了杯咖啡');
      expect(cleanExpenseNote('RMB 128.5 买书'), '买书');
    });

    test('removes Chinese spoken amount from expense note', () {
      expect(cleanExpenseNote('十元的小吃'), '的小吃');
      expect(cleanExpenseNote('十八元买咖啡'), '买咖啡');
    });
  });
}
