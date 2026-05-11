# Dayline 开发日志：SenseVoice 替换 STT 与真机性能调优

日期：2026-05-12  
设备：vivo V2154A / Android 14 / 真机序列号 `3432033034001K3`  
范围：离线 STT 引擎、SenseVoice 模型部署、录音链路、真机安装验证、连续录音与滑动卡顿排查

## 1. 开始前状态

根据 `E:/Claude code/SenseVoice集成计划书.md` 实施 SenseVoice-Small 手机端集成，用 SenseVoice 替代原 STT。

开始前先检查 git：

```text
origin/main...HEAD = 0 0
```

结论：没有本地 commit 未推送到云端。工作区已有一些未提交改动和未跟踪截图/日志文件，本轮只处理 STT、Android 配置、入口初始化、对应测试和开发日志。

## 2. 初始替换方案

原实现基于 sherpa-onnx 在线流式 transducer：

- `OnlineRecognizer`
- PCM16 stream
- Silero VAD
- 常驻 worker 流式解码

本轮改为 SenseVoice 离线批量识别：

- `OfflineRecognizer`
- `OfflineSenseVoiceModelConfig`
- `model.int8.onnx + tokens.txt`
- 16kHz mono WAV
- `readWave()` 读取文件
- 输出文本、语种、情绪、音频事件

最终录音链路：

```text
按住开始 -> record 录制 16kHz mono WAV
松手结束 -> SenseVoice OfflineRecognizer 推理 -> SttTranscript
```

主要改动文件：

- `lib/core/stt/local_stt_service.dart`
- `lib/core/stt/stt_asset_manager.dart`
- `lib/core/stt/stt_engine.dart`
- `lib/main.dart`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `test/core/stt/stt_asset_manager_test.dart`

## 3. 模型部署

模型地址：

```text
https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2
```

App 私有模型目录：

```text
/data/data/com.example.dayline_app/app_flutter/stt_models/sense_voice_small_zh/
```

目标文件：

```text
model.int8.onnx
tokens.txt
```

`SttAssetManager` 从原来的 asset zip + manifest 校验，改为：

1. 检查 app 私有目录是否已有 `model.int8.onnx` 和 `tokens.txt`。
2. 缺失时下载 tar.bz2。
3. 解压 tar.bz2。
4. 只提取 `model.int8.onnx` 和 `tokens.txt`。
5. 写入 `source.json` 记录来源信息。

## 4. 真机问题：手机访问 GitHub 失败

首轮写入 APK 后真机显示“语音不可用”。排查：

```text
adb shell ping -c 1 github.com
ping: unknown host github.com
```

手机端无法解析或访问 GitHub，首次启动无法下载模型。临时处理：

1. 在电脑端下载模型包。
2. 本地解压出 `model.int8.onnx` 和 `tokens.txt`。
3. `adb push` 到 `/data/local/tmp/`。
4. 用 `run-as com.example.dayline_app` 复制进 app 私有目录。

真机确认：

```text
model.int8.onnx  239233841 bytes
tokens.txt          315894 bytes
```

同时显式写入：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

## 5. 第一轮速度优化：常驻 Recognizer

初始 SenseVoice 版本每次松手后都会：

```text
新开 compute isolate
-> initBindings()
-> 创建 OfflineRecognizer
-> readWave()
-> decode()
-> free recognizer
```

239MB 模型重复加载会让短语音识别很慢。第一轮优化为常驻 worker：

- `LocalSttService.initialize()` 阶段启动 `DaylineSenseVoiceWorker`。
- worker 内创建一次 `OfflineRecognizer`。
- 每次松手只发送 `wavPath`。
- worker 复用 recognizer 识别。
- `dispose()` 时释放 recognizer。

体验结果：

- 松手后出结果速度明显变快。
- 但页面进入时模型加载前移，用户感到“进入页面加载模型慢了”。

## 6. 第二轮速度优化：可录音优先，后台预热

目标调整为：

```text
页面先可录音
模型后台预热
松手时如果 worker 已热好，直接识别
如果 worker 还没热好，松手时等待同一个 warmup future
```

实现：

- `initialize()` 只同步确认模型文件存在。
- 文件存在就立刻返回 `SttAvailability.ready()`。
- 后台 `unawaited(_startWorker(paths))` 预热 SenseVoice worker。
- `startListening()` 不再等待 worker 创建完成，只负责开始 WAV 录音。
- `stop()` 时通过 `_transcribeFile()` 等待或复用 worker。

真机安装后 UI 树确认 ready：

```text
时刻准备记录你的灵感
也可以长按话筒说话
```

## 7. 话筒动效优化

用户反馈“话筒下的动效有点卡”。处理：

- 录音音量刷新间隔从 `120ms` 放缓到 `180ms`。
- 给 `VoiceButton` 外层加 `RepaintBoundary`。
- 给 `AudioWaveform` 外层加 `RepaintBoundary`。

目标是减少音量状态更新造成的大范围重绘，让波形和话筒动画互相隔离。

## 8. 连续录音与滑动卡顿排查

用户连续多次录音并滑动页面后反馈：

- 上滑胶囊区域开始明显卡顿。
- 页面使用一段时间后有“越来越卡”的趋势。

采集目录：

```text
.codex_tmp/perf/20260512-011955-sensevoice-jank/
```

采集内容包括 Perfetto trace、`dumpsys gfxinfo`、前后两次 `dumpsys meminfo`、logcat。

关键观察：

- `gfxinfo` 现代口径 janky frames 为 `5 / 259 = 1.93%`。
- GPU 50/90/95/99 分位为 `1ms / 2ms / 2ms / 2ms`，主要不是 GPU 绘制瓶颈。
- legacy janky frames 为 `50 / 259 = 19.31%`，`High input latency = 26`，与滑动和胶囊输入迟滞相符。
- TOTAL PSS：`714915 KB -> 839463 KB`，增长约 `124.5 MB`。
- Native Heap PSS：`354987 KB -> 455632 KB`，增长约 `100.6 MB`。
- Native Heap Alloc：`344017 KB -> 457415 KB`，增长约 `113.4 MB`。
- Views/Activities 稳定为 `7 / 1`，不像 Flutter 页面或 Activity 泄漏。
- 静置后 Dalvik/Binder 部分回落，但 Native Heap 仍保持高位。

判断：更像 SenseVoice/ONNX/XNNPACK 常驻识别器在连续 decode 后累积 native workspace/cache，导致系统内存压力和输入迟滞，而不是单纯 UI 绘制太重。

## 9. 第三轮优化：短周期 Worker 回收

处理策略：

- 保留“后台预热 + 常驻 worker”的速度优势。
- 每完成 2 次识别后，释放旧 `OfflineRecognizer`/worker。
- 释放后立刻后台预热新的 worker。
- 回收时先摘掉当前 worker 引用，再异步释放旧 isolate，避免新识别任务误发到正在关闭的 worker。

取舍：

- 连续快速录音时，每第 3 次附近可能遇到一次后台预热窗口。
- 大部分交互仍保持热识别速度。
- 目标是压住 native heap 的持续上涨，减少内存压力导致的“越用越卡”。

## 10. 验证记录

已执行：

```text
flutter analyze
flutter test
flutter build apk --debug
adb -s 3432033034001K3 install -r build\app\outputs\flutter-apk\app-debug.apk
adb -s 3432033034001K3 shell am start -n com.example.dayline_app/.MainActivity
```

结果：

- `flutter analyze` 通过。
- `flutter test` 通过。
- Debug APK 构建成功。
- 真机安装成功。
- 启动后 UI 树显示语音入口 ready。

## 11. 当前注意事项

- `adb install -r` 会保留 app 数据，因此 sideload 到私有目录的模型仍在。
- 如果清除 app 数据或卸载重装，模型私有目录会被删除；手机无法访问 GitHub 时需要再次 sideload。
- 后续可以继续加识别耗时日志：录音时长、WAV 写入耗时、worker 等待耗时、推理耗时、总耗时。
