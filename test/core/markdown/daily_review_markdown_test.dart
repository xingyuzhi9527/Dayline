import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/markdown/daily_review_markdown.dart';

void main() {
  group('upsertDailyReviewSection', () {
    test(
      'replaces the existing evening review without touching other sections',
      () {
        const markdown = '''
# 2026-05-16 日记

## 今日概览

今天有 3 条记录。

## 晚间复盘

### 今天值得保留的是

...

### 今天可以调整的是

...

### 明天最小行动是

...

## 原始记录索引

保留给未来检索。
''';

        final updated = upsertDailyReviewSection(
          markdown,
          kept: '散步以后状态好了',
          adjust: '少刷短视频',
          nextAction: '早上先写 10 分钟',
        );

        expect(updated, contains('## 今日概览'));
        expect(updated, contains('散步以后状态好了'));
        expect(updated, contains('少刷短视频'));
        expect(updated, contains('早上先写 10 分钟'));
        expect(updated, contains('## 原始记录索引'));
        expect(updated, isNot(contains('### 今天值得保留的是\n\n...')));
      },
    );

    test('inserts the evening review before the raw index when missing', () {
      const markdown = '''
# 2026-05-16 日记

## 今日概览

今天有 3 条记录。

## 原始记录索引

保留给未来检索。
''';

      final updated = upsertDailyReviewSection(
        markdown,
        kept: '完成了日记同步',
        adjust: '',
        nextAction: '继续真机验证',
      );

      expect(
        updated.indexOf('## 晚间复盘'),
        lessThan(updated.indexOf('## 原始记录索引')),
      );
      expect(updated, contains('完成了日记同步'));
      expect(updated, contains('继续真机验证'));
      expect(updated, contains('### 今天可以调整的是\n\n...'));
    });
  });
}
