# Dayline 开发日志：真机语音、输入与记录体验修复

时间范围：2026-05-09 晚间至 2026-05-10 00:55  
设备：vivo V2154A / Android 14 / 真机序列号 `3432033034001K3`  
范围：`记` 页面、`线` 页面、本地 STT、文字输入、消费金额解析、压力测试与 QA 证据

## 1. 背景

本轮工作从“真机语音能否接入系统”开始，随后决定将系统 `speech_to_text` 方案替换为本地离线 STT。用户提供了 V2.1 计划，目标是：

- 使用 `record` 采集 PCM16 音频。
- 使用 `sherpa_onnx` Zipformer 做本地实时识别。
- 使用 VAD 降低无声环境误识别。
- 内置模型与热词，优先 Android 真机离线可用。
- 修正“模拟器语音不可用”的错误文案。
- 保留 debug mock engine。

在本地 STT 接入后，进入真机测试阶段，陆续暴露出 UI overflow、键盘挤压、待办卡片过大、文字输入保存慢、中文输入法被安全键盘替代、语音消费金额缺失等问题。

## 2. 今日主要改动

### 2.1 本地 STT 与语音入口

已完成的方向：

- App 已从系统语音黑盒调用转向本地离线语音入口。
- 语音状态文案已调整为离线引擎语义：
  - `正在唤醒离线大脑...`
  - `时刻准备记录你的灵感`
  - `正在本地识别...`
  - `离线语音暂不可用，请使用文字记录`
- debug fallback 保留，可用于无模型或开发场景生成测试记录。
- 模型包已放入工程并能在真机运行。

当前体验观察：

- 能识别中文短句，但模型准确率和速度仍不理想。
- 用户实测“吃饭二十分钟”时，“分钟”出现较慢，多次尝试才稳定识别。
- 曾出现误识别为“枝花”等情况。
- 本轮没有继续深调模型参数，优先修复录入链路和 UI 可用性。

### 2.2 `记` 页面布局修复

问题：

- 待办卡片过大，视觉上抢占主操作区。
- 点击文字输入框时页面被键盘顶动，布局不稳定。
- 麦克风按钮位置偏下，主操作焦点不够明确。
- 盘页面曾出现 `bottom overflowed` 类黄黑斜纹。

原因：

- 页面主体使用普通 `Column` 布局，键盘弹出后可用高度减少，导致底部输入区挤压主体内容。
- 待办入口尺寸接近普通卡片，不适合放在主录音界面上。
- App shell 默认允许键盘调整 Scaffold 高度。

解决：

- `lib/shell/dayline_shell.dart`
  - 设置 `resizeToAvoidBottomInset: false`，避免键盘直接顶动主界面。
- `lib/features/flash_record/flash_record_page.dart`
  - 主操作区改为 `Positioned.fill` + `Align` 的稳定舞台布局。
  - 文字输入区改为底部 dock，键盘弹出时用 `AnimatedPositioned` 调整位置。
  - 键盘弹出时主舞台轻微降透明，保持视觉层次。
  - 待办入口缩小为右下角轻量入口。
- `lib/features/flash_record/widgets/voice_button.dart`
  - 麦克风按钮增大并更居中。
- `lib/features/today/widgets/today_cards.dart`
  - 今日卡片比例微调，缓解盘页面布局压力。

状态：

- 已真机构建安装。
- UI overflow 问题已按截图和 UI 树复测。
- 仍建议后续做更多不同屏幕尺寸覆盖，尤其是小屏、字体放大、系统导航栏高度变化。

### 2.3 文字输入大量写入卡顿

问题：

- 用户要求压力测试“大量写入或者划屏”。
- 初始自动化写入中发现输入后没有真正点击发送。
- 后续要求“长文本、加快”，暴露出连续输入/发送时明显卡顿风险。
- 用户反馈“现在感觉输多了会卡顿”。

原因：

- 原 `saveAsText` 会把页面 phase 切到 `saving`，保存完成后才恢复，连续输入时 UI 被保存流程牵制。
- 每次写入都会立即触发 `dataVersionProvider` 增量，导致时间线、今日统计等依赖数据频繁刷新。
- STT 初始化原先在启动 microtask 中尽快触发，可能与首帧渲染争抢资源。

解决：

- `lib/features/flash_record/flash_record_page.dart`
  - 点击发送后立即清空输入框。
  - 使用 `unawaited(saveAsText(text))` 后台保存，让用户可以继续输入。
  - 发送按钮显示轻量 loading，但不阻断输入区。
- `lib/features/flash_record/flash_record_notifier.dart`
  - `saveAsText` 不再切到全局 `saving` phase。
  - 新增 `textSaving` 状态用于按钮反馈。
  - 保存成功后清理 raw/parsed 状态，并递增 `savedSequence`。
  - STT 初始化延迟约 900ms，优先让首屏渲染完成。
- `lib/core/database/repository_providers.dart`
  - `DataVersionNotifier` 新增 `incrementSoon`，将连续写入后的刷新做 250ms 防抖。
- `lib/features/flash_record/flash_record_state.dart`
  - 新增 `textSaving`、`savedSequence`。

验证：

- `flutter analyze` 通过。
- `flutter test` 全量通过。
- `flutter build apk --debug` 通过。
- 真机已重新安装。

注意：

- 有一次真机安装曾失败，原因是手机端拒绝安装权限：`INSTALL_FAILED_ABORTED: User rejected permissions`。后续重新连接并确认后安装成功。
- 因为安装失败那轮跑到的是旧包，所以那一次“新版压力复测”不计为有效验证。
- 最新修复包已安装成功，但仍建议补一轮“新版连续长文本写入 + 滑动”正式压力报告。

### 2.4 中文输入法被安全键盘替代

问题：

- 用户反馈：“怎么只能打开安全键盘了，无法输中文了。”

原因：

- 为减少输入法乱转换，之前对文字输入框加入了：
  - `autocorrect: false`
  - `enableSuggestions: false`
  - `keyboardType: TextInputType.text`
  - `textCapitalization: TextCapitalization.none`
- vivo/百度输入法可能把这种组合识别成受限输入场景，从而切到安全键盘，中文输入不可用。

解决：

- `lib/features/flash_record/flash_record_page.dart`
  - 移除上述受限输入配置。
  - 恢复 Flutter 默认普通文本输入能力。
  - 保留快速发送、发送后立即清空、后台保存、防卡顿优化。

验证：

- 真机默认输入法：`com.baidu.input_vivo/.ImeVivoService`。
- UI 树确认输入框为普通 `EditText`，`password="false"`。
- 已重新安装到真机。

状态：

- 已解决。
- 后续如果还出现厂商输入法异常，应优先通过 `TextInputConfiguration` 和真机输入法日志定位，而不是强关联想/纠错。

### 2.5 语音输入消费金额不显示

问题：

- 用户反馈：语音输入的价格不会显示，文字输入的价格消费能识别。
- 线页面证据：
  - `20元手机壳` 显示为 `消费 ¥20.00`。
  - `十元的小吃` 显示为 `消费 ¥0.00`。

原因：

- 解析器原本只支持阿拉伯数字金额：
  - `20元`
  - `18块`
  - `RMB 128.5`
- 语音识别常输出中文数字：
  - `十元`
  - `十八元`
  - `二十块`
- 类型推断因为包含 `元/块/消费` 等关键词，能识别为 `expense`，但金额提取失败，保存时 fallback 为 `0.0`。

解决：

- `lib/core/parser/lui_lite_parser.dart`
  - 新增中文金额后缀识别。
  - 支持 `十元`、`十八元`、`二十块`、`一百二十三元`、`两百零五元`。
  - 支持简单中文小数结构，例如 `十点五元` 的解析基础。
- `test/chinese_amount_parser_test.dart`
  - 新增语音中文金额回归测试。

验证：

- `flutter test test/chinese_amount_parser_test.dart` 通过。
- `flutter analyze` 通过。
- `flutter test` 全量 154 个测试通过。
- 已重新 build 并安装真机。

注意：

- 已存在旧记录 `十元的小吃 -> ¥0.00` 已经写入数据库为 0，本次代码修复只影响新录入。
- 如需修复旧数据，需要额外做历史数据回填或手动编辑保存。

## 3. QA 与测试证据

新增或使用的 QA 目录：

- `docs/qa/2026-05-09-ui-overflow/`
  - 记录盘页面 overflow、输入框黄黑斜纹、修复后截图与日志。
- `docs/qa/2026-05-09-flash-layout/`
  - 记录 `记` 页面布局、输入框、待办入口、麦克风视觉调整过程。
- `docs/qa/2026-05-09-stress-test/`
  - 记录早期压力测试、写入步骤、滑动、日志、数据库快照、framestats。
- `docs/qa/2026-05-09-stress-test-enter-slow/`
  - 记录 Enter/发送慢探针与长文本快速写入实验。
- `docs/qa/2026-05-09-text-input-fix/`
  - 记录一次安装失败后的无效复测证据，需注意该轮不代表新版结果。
- `docs/qa/2026-05-10-device-install/`
  - 记录真机安装与启动截图、logcat tail。
- `docs/qa/2026-05-10-chinese-ime-fix/`
  - 记录中文输入法修复后的输入框 UI 树与截图。
- `docs/qa/2026-05-10-voice-price-issue.png`
  - 语音金额问题截图。
- `docs/qa/2026-05-10-voice-price-ui.xml`
  - 线页面 UI 树，包含 `十元的小吃 -> ¥0.00` 证据。

执行过的验证命令：

- `flutter analyze`
- `flutter test test/widget_test.dart`
- `flutter test test/chinese_amount_parser_test.dart`
- `flutter test`
- `flutter build apk --debug`
- `adb install -r -g build\app\outputs\flutter-apk\app-debug.apk`
- `adb shell am start -n com.example.dayline_app/.MainActivity`
- `adb exec-out screencap -p`
- `adb exec-out uiautomator dump /dev/tty`
- `adb logcat -d`

最近一次关键结果：

- `flutter analyze`：通过。
- `flutter test`：154 个测试全部通过。
- debug APK：构建成功。
- 真机安装：`Success`。
- 真机启动：成功。

## 4. 已解决问题清单

1. `记` 页面键盘弹出导致布局跳动。
2. 盘页面/输入框出现黄黑斜纹 overflow。
3. 待办卡片过大，已缩小并放到右下角。
4. 麦克风按钮视觉中心不佳，已放大并居中。
5. 文字输入连续写入时保存流程阻断 UI，已改为后台保存。
6. 高频写入触发大量 provider 刷新，已增加防抖。
7. STT 初始化抢首帧，已延迟初始化。
8. 中文输入法变安全键盘，已恢复普通文本输入配置。
9. 语音输出中文数字金额导致消费金额为 0，已支持中文金额解析。
10. 自动化测试中“没点击发送”的问题已定位为测试动作问题，不是保存逻辑本身。

## 5. 未解决 / 风险

1. 本地 STT 准确率仍不足。
   - 表现：短句需要多次尝试才准确，部分词会误识别。
   - 影响：生活记录的可靠性和用户信任。
   - 方向：模型选择、热词、beam、VAD 阈值、endpoint 参数继续调优。

2. 本地 STT 速度仍偏慢。
   - 表现：“分钟”等词可能延迟较久才出现。
   - 影响：用户会觉得长按后反馈慢。
   - 方向：模型换小、int8 确认、线程数、chunk/periodFrames、endpoint 策略。

3. 旧数据没有自动回填。
   - 表现：已经保存为 `¥0.00` 的旧语音消费记录不会自动修正。
   - 方向：提供一次性 migration/backfill，扫描今天或全量 expense note 中的中文金额。

4. 最新“连续长文本写入 + 滑动”压力测试需要重新跑。
   - 原因：有一轮安装失败导致测试跑在旧包上。
   - 当前代码已优化，但需要新包下的正式证据。

5. 不同设备/输入法兼容性未覆盖。
   - 当前只验证 vivo + 百度输入法。
   - 方向：至少补小米、OPPO、华为或系统 Gboard。

6. 长时间语音连续识别的发热和耗电还未专项测试。
   - V2.1 中低电量、省电模式、音乐抢占已列为第二轮。

## 6. 待办建议

### P0

- 重新跑新版压力测试：
  - 20 到 50 条长文本快速写入。
  - 连续切换 `线/记/盘`。
  - 滑动时间线。
  - 抓取 logcat、数据库 count、framestats、meminfo。
- 针对新语音金额逻辑做真机验收：
  - 说“十元的小吃”。
  - 说“十八元买咖啡”。
  - 说“二十块手机壳”。
  - 到线页面确认金额不是 `¥0.00`。

### P1

- 做旧记录金额回填工具：
  - 只处理 `expenses.amount == 0` 且 note/content 中包含中文金额的记录。
  - 回填前写 QA 日志和可回滚备份。
- 增加更多中文数字解析：
  - `十二块五`
  - `三块五毛`
  - `一百零八块八`
  - `两千三百五十元`

### P2

- STT 专项优化：
  - 对比不同 sherpa-onnx 模型。
  - 调整 beam、chunk、endpoint silence。
  - 优化热词文件。
  - 增加语音转写 baseline 音频集。
- UI 细节继续打磨：
  - 输入框 focus 动画。
  - 发送成功反馈。
  - 录音 partial/final 文案层级。

## 7. 文件变更摘要

核心代码：

- `lib/core/database/repository_providers.dart`
  - 数据刷新防抖。
- `lib/core/parser/lui_lite_parser.dart`
  - 中文金额解析。
- `lib/features/flash_record/flash_record_notifier.dart`
  - 文字保存后台化、STT 延迟初始化。
- `lib/features/flash_record/flash_record_page.dart`
  - 稳定舞台布局、输入 dock、发送按钮状态、中文输入法修复。
- `lib/features/flash_record/flash_record_state.dart`
  - `textSaving`、`savedSequence` 状态。
- `lib/features/flash_record/widgets/voice_button.dart`
  - 麦克风尺寸与视觉调整。
- `lib/features/today/widgets/today_cards.dart`
  - 卡片比例调整。
- `lib/shell/dayline_shell.dart`
  - 禁止键盘顶动 Scaffold。

测试：

- `test/chinese_amount_parser_test.dart`
  - 新增中文金额解析回归。
- `test/widget_test.dart`
  - 适配 STT 延迟初始化。
- `test/ui_redesign_test.dart`
  - 适配 STT 延迟初始化。

文档与证据：

- `docs/qa/**`
  - 真机截图、UI 树、logcat、压力测试、数据库快照。
- `docs/devlogs/2026-05-10-flash-record-stt-ui-devlog.md`
  - 本开发日志。
