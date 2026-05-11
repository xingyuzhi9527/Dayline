# Dayline 开发日志：语音长按退出、初始化重试与速度测试现场

日期：2026-05-11
设备：vivo V2154A / Android 14 / 真机序列号 `3432033034001K3`
范围：`记` 页面底部胶囊、离线 STT 状态机、真机语音识别体验、后续测速方案

## 1. 背景

用户在真机上反馈：`记` 页面点击下方胶囊后，长按可以进入语音识别，但松开后无法退出，会一直处于识别状态。

随后修复后，用户继续反馈：

- 语音功能一度不能用。
- 识别速度仍然偏慢。
- 识别率不够高。
- 希望通过人工点击/口播，由 Codex 收集日志来判断慢在哪里。

本轮目标从单纯修复交互问题，扩大为：

- 保证“按住说话，松手结束”这条链路稳定。
- 避免 STT 初始化慢或超时后把语音入口判死。
- 建立可继续测量语音速度的日志方法。

## 2. 问题一：长按后松手无法退出识别

### 2.1 现象

用户长按底部胶囊后，页面进入 `listening`，但松手后没有触发停止，表现为一直在识别。

### 2.2 根因

底部胶囊的显示受 `FlashRecordState.isInputActive` 控制。原逻辑只在 `idle` 时渲染底部输入胶囊：

```dart
bool get isInputActive => phase == FlashPhase.idle;
```

长按触发 `startListening()` 后，状态立刻切到 `FlashPhase.listening`，导致底部胶囊从 widget tree 中移除。手指还没有松开，承接 `PointerUp` / `onLongPressEnd` 的 widget 已经消失，所以停止事件丢失。

### 2.3 修复

将底部胶囊保留到 `listening` 状态：

```dart
bool get isInputActive =>
    phase == FlashPhase.idle || phase == FlashPhase.listening;
```

文件：

- `lib/features/flash_record/flash_record_state.dart`

新增回归测试：

- `collapsed intent long press stops after pointer release`

验证点：

- 长按底部胶囊后 STT 会话启动。
- 状态切到 `listening` 后，胶囊仍在树上。
- 松手后会调用 `SttListenSession.stop()`。

## 3. 问题二：修复后语音一度不可用

### 3.1 现象

真机 UI 树显示：

```text
离线语音暂不可用：TimeoutException after 0:00:45.000000: Future not completed
```

这说明当时不是“松手 stop 失败”，而是离线语音初始化进入了错误态。

### 3.2 根因

`startListening()` 原逻辑在 `sttStatus != ready` 时会立即放弃：

- 如果 STT 还在 loading，直接显示“离线大脑还在唤醒，稍等一下”。
- 如果前一次初始化超时，状态进入 error，再次长按也不会主动等初始化恢复。

这会把“初始化慢”误处理成“语音不可用”，用户会感觉语音功能坏了。

### 3.3 修复

`startListening()` 改为：

- 如果状态已经 ready，直接开始录音。
- 如果还没有 ready，用户长按时主动调用 `_initializeStt()` 等一次。
- 初始化完成后再启动真实 STT session。
- 如果本次请求已经过期，则丢弃旧结果。

核心逻辑：

```dart
final availability = state.sttStatus == SttAvailabilityStatus.ready
    ? const SttAvailability.ready()
    : await _initializeStt();

if (_disposed || requestId != _listenRequestId) return;

if (!availability.isReady) {
  state = state.copyWith(
    phase: FlashPhase.idle,
    errorMessage: kDebugMode
        ? availability.message
        : '离线语音暂不可用，请使用文字记录',
  );
  return;
}
```

文件：

- `lib/features/flash_record/flash_record_notifier.dart`

新增回归测试：

- `voice long press waits for STT init and starts once ready`

验证点：

- 用户长按时，如果 STT 初始化还未完成，不会立刻报“离线语音暂不可用”。
- 初始化完成后会继续启动 STT session。

## 4. 真机验证

### 4.1 环境

- 设备：`3432033034001K3`
- 包名：`com.example.dayline_app`
- Activity：`com.example.dayline_app/.MainActivity`
- 麦克风权限：已授权 `android.permission.RECORD_AUDIO`

### 4.2 安装与启动

执行：

```bash
flutter install -d 3432033034001K3 --debug
adb -s 3432033034001K3 shell am force-stop com.example.dayline_app
adb -s 3432033034001K3 shell am start -n com.example.dayline_app/.MainActivity
```

启动后，真机从：

```text
正在唤醒离线大脑...
首次加载稍慢，之后会热启动
```

等待约 10 秒后进入：

```text
时刻准备记录你的灵感
也可以长按话筒说话
```

说明新包中的初始化重试和 ready 状态恢复可用。

### 4.3 长按释放验证

使用 adb 模拟底部胶囊长按 1 秒：

```bash
adb -s 3432033034001K3 shell input swipe 540 1992 540 1992 1000
```

松开后 UI 回到空闲态，并显示：

```text
没有听清，再按住说一次。
```

结论：

- 松手后已经能退出识别。
- 不再卡在 listening 状态。
- 这次 adb 测试没有真实口播，因此没有有效识别文本属于预期。

## 5. 当前速度测试现场

用户随后人工长按并口播一次，Codex 在后台采集 `logcat`。

采集到的关键日志：

```text
05-11 21:36:39.922 D/AudioRecord(17385): start(313): sync event 0 trigger session 0
05-11 21:36:41.974 D/AudioRecord(17385): stop(313): mActive:1
05-11 21:36:42.068 D/AudioRecord(17385): stop(313): mActive:0
05-11 21:36:42.068 D/AudioRecord(17385): stop(313): mActive:0
```

从这组日志只能确认：

- 录音从 `21:36:39.922` 开始。
- 用户释放后，底层 AudioRecord 在 `21:36:41.974` 开始停止。
- 到 `21:36:42.068` 完全停止。
- 本次口播录音持续约 `2.05s`。
- AudioRecord stop 收尾约 `94ms`。

但目前日志没有记录：

- `startListening()` 被 UI 触发的时间。
- STT session 创建完成时间。
- 第一次 partial transcript 出现时间。
- final transcript 输出时间。
- `_completeTranscript()` 切 UI 的时间。

因此这一次还不能精确判断慢在：

- STT 初始化。
- 录音启动。
- VAD 判断起声。
- streaming decode。
- 松手后 final decode。
- UI 状态切换。

## 6. 识别率观察

用户反馈：“识别率不高还有点慢。”

已知相关线索：

- 当前模型是本地 `sherpa_onnx` streaming Zipformer v2 包。
- 真机日志中仍出现过热词编码警告：

```text
sherpa-onnx: Cannot find ID for token ? at line: ? ?.
sherpa-onnx: Failed to encode some hotwords, skip them already
```

当前 `assets/stt/life_keywords.txt` 在 PowerShell 输出中呈现乱码，说明需要进一步确认：

- 文件本身是否 UTF-8 正常。
- zip 内的 `life_keywords.txt` 是否和当前源码一致。
- 热词是否被 sherpa tokenization 正确接受。
- 错误热词是否反而拖慢初始化或影响识别倾向。

这部分暂未改动，下一轮需要专项处理。

## 7. 已运行验证

本轮代码侧验证：

```bash
flutter test test\widget_test.dart --plain-name "collapsed intent long press stops after pointer release"
flutter test test\widget_test.dart --plain-name "voice long press waits for STT init and starts once ready"
flutter test test\widget_test.dart
flutter analyze
```

结果：

- 相关回归测试通过。
- 完整 `widget_test.dart` 通过。
- `flutter analyze` 无问题。
- 最新 debug 包已安装到真机。

## 8. 下一步建议

### 8.1 增加开发态 STT 性能打点

需要在 debug 模式下输出结构化日志，例如统一前缀：

```text
DAYLINE_STT start_request requestId=...
DAYLINE_STT init_done elapsedMs=...
DAYLINE_STT session_started elapsedMs=...
DAYLINE_STT partial elapsedMs=... text=...
DAYLINE_STT final elapsedMs=... text=...
DAYLINE_STT stop_done elapsedMs=...
```

这样下一次人工口播时，可以直接拆出：

- 按下到开始录音。
- 开始录音到首字。
- 首字到 final。
- 松手到 UI 完成。

### 8.2 热词文件专项检查

需要确认 `life_keywords.txt` 的真实编码和 zip 内内容：

- 用二进制/UTF-8 工具检查源码文件。
- 解包 `assets/stt/dayline-stt-v2.zip` 检查包内热词。
- 去掉无法编码的热词做 A/B 测试。
- 对比有热词和无热词时的初始化时间、识别率。

### 8.3 识别速度调参方向

候选方向：

- 缩短 final endpoint 的尾部等待。
- 调整 VAD threshold / min speech duration / silence endpoint。
- 降低或调整 hotwordsScore。
- 记录 partial 输出频率，看是否 UI 已拿到文本但没有及时展示。
- 建一组固定短句 baseline，避免每次人工口播差异太大。

### 8.4 识别率优化方向

候选方向：

- 清理热词乱码和不在 tokens 中的热词。
- 增加生活记录高频词 baseline，例如跑步、买菜、花了、待办、开会、体重、喝水。
- 对常见误识别做后处理，但只做高置信、低风险替换。
- 保留 recognized 阶段的可编辑文本框，降低误识别带来的记录成本。

## 9. 当前结论

本轮已经解决两个阻断问题：

1. 底部胶囊长按后松手无法退出。
2. STT 初始化慢或超时后，用户长按无法重新拉起语音。

但“速度慢、识别率不高”仍是开放问题。当前日志只能证明录音层启动和停止是正常的，还不能精确定位识别链路耗时。下一轮应先补开发态 STT 性能打点，再做参数和热词优化，否则调参会有点像蒙着眼睛拧旋钮。
