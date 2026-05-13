import 'package:liflow_app/core/stt/stt_text_post_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes leading filler words from spoken life notes', () {
    expect(postProcessTranscript('嗯 那个 今天跑步三十分钟'), '今天跑步三十分钟。');
    expect(postProcessTranscript('啊就是待办买牛奶'), '待办买牛奶。');
  });

  test('keeps existing sentence punctuation', () {
    expect(postProcessTranscript('心情有点焦虑。'), '心情有点焦虑。');
    expect(postProcessTranscript('买咖啡了吗？'), '买咖啡了吗？');
  });

  test('returns empty text unchanged', () {
    expect(postProcessTranscript('  嗯 啊 那个  '), '');
  });
}
