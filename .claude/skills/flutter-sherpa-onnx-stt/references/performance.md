# sherpa-onnx STT 性能优化参考

## 架构层面优化

### Worker Isolate（必做）

将解码放到独立 Isolate 是最重要的性能优化。不解耦的话 UI 会出现明显卡顿。

```
UI Isolate                     Worker Isolate
  │                                │
  ├─ record 录音 ──► SendPort ──►  ├─ sherpa.initBindings()
  ├─ RMS 电平计算                  ├─ OfflineRecognizer
  ├─ UI 渲染                       ├─ 解码 decode()
  │                                └─ 结果回传 → ReceivePort → UI
```

- Worker 每 N 次识别后重建（建议 N=2），防止 native heap 持续增长
- `TransferableTypedData` 传音频数据（零拷贝）
- `Isolate.immediate` 优先 kill 避免等待

### 初始化优化

- 模型初始化在后台执行（`unawaited(_startWorker(...))`），不阻塞 UI
- 支持 lazy init：首次录音时才启动 Worker
- 初始化超时保护（60s）

## 音频层面优化

### 录音配置

```dart
RecordConfig(
  encoder: AudioEncoder.wav,
  sampleRate: 16000,      // 16kHz 是 SenseVoice 的要求
  numChannels: 1,         // 单声道（降低数据量）
  autoGain: true,         // 自动增益提升远场识别
  noiseSuppress: true,    // 降噪
  echoCancel: false,      // 录音场景无需回声消除
)
```

### 波形刷新率

- 音频电平采样间隔：**180ms**（120ms 可能不够平滑，低端设备更明显）
- RMS 归一化：`(dbfs + 60) / 60`，clamp 到 [0, 1]
- dbfs 典型范围：-60（静音） 到 0（满幅）

## Widget 性能

### RepaintBoundary

动画组件必须包裹 `RepaintBoundary`，避免触发全局重绘：

```dart
RepaintBoundary(
  child: VoiceButton(...),   // 录音按钮动画
)
RepaintBoundary(
  child: AudioWaveform(...), // 波形动画
)
```

### Ticker 平滑插值

波形用 `StatefulWidget` + `Ticker` 做平滑过渡，不要每帧重建 Widget：

```dart
// 每帧向目标值移动 ~18%，产生平滑的视觉过渡
_currentLevel += (targetLevel - _currentLevel) * 0.18;
```

### TickerMode

非活动标签页关闭动画 ticker，减少无用渲染：

```dart
TickerMode(
  enabled: isCurrentTab,
  child: page,
)
```

## Worker 生命周期管理

### 回收策略

```dart
const _workerRecycleAfterTranscriptions = 2;

void _noteWorkerTranscriptionFinished() {
  _workerTranscriptionCount++;
  if (_workerTranscriptionCount >= _workerRecycleAfterTranscriptions) {
    // 异步重建 worker，不阻塞当前操作
    unawaited(Future.delayed(Duration.zero, () async {
      await _disposeWorker(completePending: false);
      await _startWorker(paths);
    }));
  }
}
```

**为什么需要回收**：
- Native heap 在连续使用后会持续增长（debug build 可见 >100MB PSS）
- Isolate 的 GC 不及时
- 重建 worker 是成本最低的"手动 GC"

### 超时保护

- Worker 初始化：60s 超时
- 单次识别：90s 超时
- 超时后返回空文本 + 保留录音 draft（用户不会丢失录音）

## 监控指标

### 需要关注的数值

| 指标 | 正常范围 | 异常迹象 |
|------|---------|---------|
| 识别耗时 | < 3s（短句） | > 10s 可能卡住 |
| Native Heap PSS | 100-150 MB (debug) | > 200 MB 需排查泄漏 |
| 帧率 | 60fps（非录音）/ 流畅（录音中） | 明显掉帧需检查 UI 线程 |
| Worker 启动 | < 5s | > 30s 检查模型文件 |

### 日志标签约定

统一使用可过滤的日志标签，方便性能分析：

```
STT_INIT  - 初始化耗时
STT_SESSION - 录音会话生命周期
STT_DECODE - 解码耗时
STT_WORKER - Worker 生命周期
```

## 未覆盖的性能场景

以下场景尚未专项测试，属于已知风险：

- 连续 >5 分钟录音的发热和稳定性
- 低电量/省电模式下的 CPU 调度影响
- 音乐播放时的音频焦点抢占
- 嘈杂环境下的 VAD 误触发率
- ABI split 对 release APK 体积的影响
