---
name: flutter-sherpa-onnx-stt
description: Flutter sherpa-onnx 离线语音识别集成。用于在 Flutter 应用中集成 sherpa-onnx 离线 ASR。覆盖：sherpa-onnx, sherpa_onnx, SenseVoice, Zipformer, Silero VAD, Worker Isolate, 离线语音识别, 本地STT, 语音转文字, speech-to-text, record 录音, PCM16, 音频处理, VAD 语音活动检测。
---

# Flutter sherpa-onnx 离线语音识别集成

完全离线的 Flutter 语音识别方案，基于 sherpa-onnx + Silero VAD，不依赖任何云服务或系统语音能力。

## 快速上手

**核心依赖**（以 pub.dev 最新兼容版本为准）：

```yaml
dependencies:
  record: <latest>        # 麦克风录音（已验证: ^6.2.0）
  sherpa_onnx: <latest>   # 离线 ASR 引擎（已验证: ^1.13.1）
  archive: <latest>       # 模型文件解压（已验证: ^4.0.9）
  crypto: <latest>        # SHA-256 校验（已验证: ^3.0.7）
  path_provider: <latest> # 应用存储路径（已验证: ^2.1.5）
```

**最简架构**：

```
麦克风 → record 包 (PCM16, 16kHz, mono)
       → 音频数据
       → sherpa-onnx OfflineRecognizer (Worker Isolate)
       → 识别文本
       → 后处理（去填充词、加标点）
```

## 架构概览

### 双 Isolate 架构

将识别放在独立的 Worker Isolate 中是**关键设计决策**，不是可选的优化。

**UI Isolate 职责**：
- 录音权限管理与麦克风 PCM16 采集
- 音频电平 RMS 计算（驱动波形 UI）
- 将音频 chunk 通过 `SendPort` 发给 Worker

**Worker Isolate 职责**：
- `sherpa.initBindings()` 初始化 native 引擎
- 创建 `OfflineRecognizer`（SenseVoice）或 `OnlineRecognizer`（Zipformer streaming）
- 创建 Silero VAD 检测人声
- 识别解码（decode + getResult）
- 通过 `SendPort` 回传结果

**Worker 回收策略**：

```dart
const _workerRecycleAfterTranscriptions = 2;

// 每 2 次识别后自动重建 Worker，防止 native heap 持续增长
void _noteWorkerTranscriptionFinished() {
  _workerTranscriptionCount += 1;
  if (_workerTranscriptionCount < _workerRecycleAfterTranscriptions) return;
  // 重建 worker...
}
```

**通信协议**（SendPort/ReceivePort + Map 消息）：

```dart
// UI → Worker
{'type': 'transcribe', 'requestId': id, 'wavPath': path}

// Worker → UI (初始化完成)
{'type': 'ready', 'sendPort': commandPort.sendPort}

// Worker → UI (识别结果)
{'type': 'result', 'requestId': id, 'text': '...', 'language': 'zh', ...}
```

## 常见陷阱

### 陷阱 1：初始化顺序错误

**症状**：`Please initialize sherpa-onnx first`

**根因**：在调用 `sherpa.initBindings()` 之前创建了 recognizer 或 VAD 对象。

**正确做法**：在 Worker Isolate 入口函数中，`initBindings()` 必须是**第一行 sherpa 调用**：

```dart
void _workerMain(Map<String, Object?> init) {
  sherpa.initBindings();  // ← 必须最先调用

  final recognizer = sherpa.OfflineRecognizer(config);  // ← 然后才创建
}
```

### 陷阱 2：modelType 配置错误

**症状**（Zipformer 模型）：`query_head_dims does not exist in metadata` 导致崩溃

**根因**：`modelType: 'zipformer2'` 期望模型 metadata 中有 `query_head_dims`，但旧版 Zipformer 模型没有此字段。

**正确做法**：

| 模型类型 | modelType 值 |
|----------|-------------|
| SenseVoice | `'sense_voice'` |
| 旧版 Zipformer (2023) | `''`（空字符串） |
| 新版 Zipformer | `'zipformer2'`（仅当模型确实是 zipformer2 格式） |

### 陷阱 3：hotwords 与 decoding_method 冲突

**症状**：sherpa 配置报错，提示 incompatible

**根因**：热词文件只支持 `modified_beam_search`，与 `greedy_search` 不兼容。

**正确做法**：

```dart
// 使用热词时
modelConfig: OfflineModelConfig(
  hotwordsFile: 'life_keywords.txt',
  decodingMethod: 'modified_beam_search',  // 不能用 greedy_search
  maxActivePaths: 2,  // 控制性能开销（vs 默认 4）
)
```

### 陷阱 4：VAD flush 导致识别结果重复

**症状**：识别结果末尾重复，如 "20元烧烤" → "20元烧烤20元烧"，"洗衣服" → "洗衣服洗衣"

**根因**：在录音结束时调用 `VAD.flush()` 并将 flush 出的音频片段再次送入 recognizer stream。但音频在采集过程中已经同时送入了 VAD（用于人声检测）和 recognizer stream（用于识别），VAD 仅做检测不做路由。flush 再送一次 = 尾部音频被识别两次。

**正确做法**：录音结束时**不要**用 VAD flush 的结果重新喂给 recognizer，直接调用 `stream.inputFinished()`：

```dart
// 错误 ❌
void finish() {
  vad.flush();
  while (!vad.isEmpty()) {
    stream.acceptWaveform(samples: vad.front().samples);
    vad.pop();
  }
  stream.inputFinished();
}

// 正确 ✅
void finish() {
  stream.inputFinished();  // 直接结束，不经过 VAD flush
}
```

**关键认知**：当 VAD 仅用于人声检测（不用于音频路由）时，flush 没有意义且会引入重复。

### 陷阱 5：按钮不可用时仍可触发录音

**症状**：用户看到语音按钮处于 disabled 状态，但长按仍触发了录音，体验为"卡住"

**修复**：在触发录音前检查 `voiceAvailable` 状态：

```dart
void _onVoiceDown() {
  if (!voiceAvailable) return;  // ← 加这个 guard
  startListening();
}
```

### 陷阱 6：首次解压卡 UI

**症状**：App 首次启动时界面卡顿

**根因**：模型 zip 解压 + SHA-256 校验在 UI isolate 执行

**修复**：使用 `compute()` 或 Isolate 执行解压和校验

### 陷阱 7：保存/取消后 STT 状态错误回退

**症状**：用户保存或取消一条记录后，STT 状态从 `ready` 错误地回到 `loading`

**修复**：`cancelConfirm()` 和 `resetAfterSaved()` 方法中**保留 STT 状态不变**，不要重置为 loading。

### 陷阱 8：Android 设备缺少系统语音服务

**症状**：`SpeechToTextPlugin: Speech recognition not available on this device`

**根因**：国产 Android 设备（vivo、OPPO 等）通常没有 Google 服务，`android.speech.RecognitionService` 不存在。

**验证**：`adb shell cmd package query-services --brief -a android.speech.RecognitionService` 返回 `No services found`

**结论**：不要在国产 Android 设备上依赖 `speech_to_text` 包。

## 模型选型

> 详细对比和配置见 `references/models.md`

**快速决策**：
- 纯中文短句 → SenseVoice（OfflineRecognizer，体积小，精度高）
- 中英混合 / 需要 partial streaming → Zipformer（OnlineRecognizer + VAD）

**核心配置差异**：SenseVoice 用 `modelType: 'sense_voice'`。旧版 Zipformer 用 `modelType: ''`（空字符串），`'zipformer2'` 仅对新版 Zipformer 模型有效，配错会导致 `query_head_dims does not exist in metadata` 崩溃。

## 音频管线

### 录音配置

```dart
await recorder.start(
  RecordConfig(
    encoder: AudioEncoder.wav,      // WAV 格式
    sampleRate: 16000,              // 16kHz（SenseVoice 要求）
    numChannels: 1,                 // 单声道
    autoGain: true,                 // 自动增益
    echoCancel: false,              // 无需回声消除（录音场景）
    noiseSuppress: true,            // 降噪
  ),
  path: wavFile.path,
);
```

### PCM16 → Float32 转换

```dart
Float32List pcm16ToFloat32(Uint8List pcmBytes) {
  final samples = pcmBytes.buffer.asByteData();
  final floatSamples = Float32List(pcmBytes.length ~/ 2);
  for (var i = 0; i < floatSamples.length; i++) {
    floatSamples[i] = samples.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return floatSamples;
}
```

### RMS 音频电平（驱动波形 UI）

```dart
double rmsAudioLevel(Uint8List pcmBytes) {
  // 计算 RMS，映射到 [0, 1] 并做 clamp
  // dbfs 范围约 [-60, 0]，归一化: (dbfs + 60) / 60
}
```

### 刷新率建议

- 音频电平采样：**180ms** 间隔（120ms 在低端设备上可能不够平滑）
- 波形 UI：用 `StatefulWidget` + `Ticker` 做平滑插值（每帧 ~18% 趋近目标值）

## 模型部署策略

### 方案 A：APK 内置（离线优先）

```
assets/stt/
  model-package.zip         # 53 MB (zip 压缩后)
  life_keywords.txt         # 热词文件
```

- `SttAssetManager`：首次启动解压到 app support directory
- SHA-256 校验：每次启动验证文件完整性
- 防 zip-slip：解压时检查 `..` 路径穿越
- `compute()` 后台解压避免卡 UI

### 方案 B：首次下载

- APK 体积小，但需要网络
- 适用场景：模型体积很大（>100MB）或频繁更新
- 注意：国产设备可能无法访问 GitHub（DNS 不可达），需自建 CDN

### 方案 C：ABI split + sideload

- `flutter build apk --split-per-abi` 减小单包体积
- adb push 模型文件到设备做 sideload

### 选择建议

- APK < 100MB：方案 A（打包进 APK）
- APK 100-200MB：方案 A + ABI split
- APK > 200MB：方案 B 或 C

## 文本后处理

### 去填充词

识别结果中常见的口语填充词需要移除：

```dart
final _fillerRegex = RegExp(
  r'^(嗯|啊|呃|额|那个|就是|这个)[，,。.!！]?\s*|'
  r'\s*(嗯|啊|呃|额|那个|就是|这个)[，,。.!！]?\s*$'
);
```

### 自动加标点

```dart
String _ensureEndPunctuation(String text) {
  if (!text.endsWith(RegExp(r'[。！？.!?，,、]'))) {
    return '$text。';
  }
  return text;
}
```

### 识别结果可编辑

识别完成后提供 TextField 让用户修正，不要只用只读 Text：

```dart
// recognized 阶段：TextField 可编辑
// 用户修改后点"确认"进入下一阶段
// 改坏了点"重新说"从头录音
```

## 性能优化

> 详细策略见 `references/performance.md`

**核心原则**：解码放入 Worker Isolate（不阻塞 UI）、RepaintBoundary 包裹动画组件、每 2 次识别后重建 Worker 防 native heap 泄漏、180ms 音频采样间隔、90s 识别超时保护。

## 测试策略

### 抽象层设计

```dart
abstract class SttEngine {
  Future<SttAvailability> initialize();
  Future<SttListenSession> startListening({bool transcribe = true});
  Future<void> dispose();
}
```

### DebugSttEngine（mock 引擎）

```dart
class DebugSttEngine implements SttEngine {
  // 返回预定义的 mock 短语
  // 模拟识别的 800ms 延迟
  // 不需要真实麦克风和模型
}
```

### 平台选择策略

```dart
SttEngine buildSttEngine() {
  if (Platform.isAndroid) return LocalSttService.instance;
  if (kDebugMode) return DebugSttEngine();
  return UnavailableSttEngine();
}
```

### Baseline 测试句子

每次改模型、热词、VAD 参数后固定测试这组短句：

**安静环境**：
1. 今天跑步三十分钟
2. 吃饭二十分钟
3. 待办买牛奶
4. 花了十八元买咖啡
5. 心情有点焦虑

**不说话测试**：确认不产生乱码、不进入确认卡片

## 平台兼容性

| 平台 | 状态 | 说明 |
|------|------|------|
| Android 真机 | 主要支持 | 国产设备需注意系统语音服务缺失 |
| Android 模拟器 | 不可用 | 无真实麦克风 |
| iOS | 未实现 | 需额外开发 |
| Desktop (debug) | Mock 模式 | 用 DebugSttEngine 开发调试 |
| Web | 不支持 | sherpa-onnx 无 Web 构建 |

## 文件结构参考

```
lib/core/stt/
  stt_engine.dart               # SttEngine 抽象接口 + SttListenSession
  local_stt_service.dart        # sherpa-onnx Worker Isolate 实现 (~600行)
  debug_stt_engine.dart         # Mock 引擎（开发/测试用）
  stt_providers.dart            # 平台选择 Provider
  stt_audio.dart                # PCM16↔Float32、RMS 计算
  stt_text_post_processor.dart  # 去填充词、加标点
  stt_asset_manager.dart        # 模型解压、SHA-256、防 zip-slip
```
