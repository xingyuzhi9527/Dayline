# Dayline 开发日志：模型切换、重复修复与识别编辑

日期：2026-05-09  
工作区：`E:\codexapp\Dayline\dayline_app`  
关联分支：`feat/model-multi-zh-hans-2023-12-12` → 已合入 main

## 1. 模型切换：bilingual → 纯中文

### 问题回顾

昨日接入的 `sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16` 在真机上速度和准确率都不理想：
- "吃饭二十分钟" 需 3-4 次才准确
- "分钟" 等尾词确认慢
- 出现 "枝花" 等误识别

根因定位为三个方向：bilingual 中英共享容量稀释了中文、2023-02 模型老旧、small 参数量在 int8 量化下精度损失放大。

### 候选评估

从 sherpa-onnx asr-models release 中找到三个纯中文 streaming 替代：

| 模型 | 日期 | int8 体积 |
|------|------|-----------|
| `multi-zh-hans-2023-12-12` | 2023-12 | ~72 MB |
| `zh-14M-2023-02-23` | 2023-02 | ~25 MB |
| `zh-int8-2025-06-30` | 2025-06 | 未验证是否存在 |

选择方案 1 `multi-zh-hans-2023-12-12`：纯中文、比当前晚 10 个月、手机端 int8 体积可接受。

### 接入过程

- 下载 tar.bz2，提取 int8 三件套（encoder/decoder/joiner）+ tokens.txt + bpe.model
- 复用 silero_vad.onnx 和 life_keywords.txt
- 生成 `dayline-stt-v2.zip`（53MB），包含 manifest.json + checksum
- 更新 `SttAssetPaths`：文件名从 `epoch-99-avg-1` 改为 `epoch-20-avg-1-chunk-16-left-128`
- 更新 `SttAssetManager` 默认指向 v2 zip 和 `dayline_stt_v2` 目录

### 真机验证结果

- 速度：明显改善
- 准确率：明显改善
- 新问题：识别结果末尾出现重复

## 2. 重复修复：VAD flush 导致尾部重复

### 现象

- "20元烧烤" → "20元烧烤20元烧"
- "洗衣服" → "洗衣服洗衣"

### 根因

`_SttWorkerSession.finish()` 中调用了 `_vad.flush()` 并把 flush 出的音频片段再次送入 `_stream.acceptWaveform()`。但音频在 `acceptPcm()` 里已经同时送入了 VAD 和 stream，VAD 仅用于 `isDetected()` 语音检测判断，不做音频路由。flush 再送一次导致最后一段音频被识别两次。

### 修复

移除 `finish()` 中的 VAD flush 循环，直接调用 `_stream.inputFinished()` 收尾：

```dart
// before (有 bug)
if (sendFinal) {
  _vad.flush();
  while (!_vad.isEmpty()) {
    final segment = _vad.front();
    _stream.acceptWaveform(samples: segment.samples, ...);
    _vad.pop();
  }
  _stream.inputFinished();
  _decodeAndEmit(0, force: true);
  // ...
}

// after (修复后)
if (sendFinal) {
  _stream.inputFinished();
  _decodeAndEmit(0, force: true);
  // ...
}
```

修复后真机验证，重复问题消失。

## 3. 识别结果编辑

用户反馈识别后如果有小错误只能点"重新说"。在 `recognized` 阶段将只读 `Text` 替换为 `TextField`，用户可以：

- 直接点击文字修改识别结果
- 改完点"确认"进入闪记卡片
- 改坏了点"重新说"从头录音

实现改动：
- `FlashRecordNotifier.confirmParsed()` 新增可选参数 `editedText`
- `FlashRecordPage` 新增 `_recognizedTextController`
- `_buildRecognizedArea()` 中使用 `TextField` 替代 `Text`

## 4. 清理

- 删除旧模型 `assets/stt/dayline-stt-v1.zip`
- main 分支当前仅保留 `dayline-stt-v2.zip`

## 5. 验证结果

- `flutter analyze`：通过
- `flutter test` (145 个)：全部通过
- `flutter build apk --debug`：成功，347MB
- 真机安装测试：速度、准确率明显改善，重复问题已修复，编辑功能可用

## 6. 文件变更

- `lib/core/stt/stt_asset_manager.dart` — SttAssetPaths 适配新文件名，AssetManager 指向 v2
- `lib/core/stt/local_stt_service.dart` — 移除 VAD flush 重复
- `lib/features/flash_record/flash_record_notifier.dart` — confirmParsed 支持编辑文本
- `lib/features/flash_record/flash_record_page.dart` — recognized 阶段可编辑
- `assets/stt/dayline-stt-v2.zip` — 新模型包（新增）
- `assets/stt/dayline-stt-v1.zip` — 旧模型包（已删除）
