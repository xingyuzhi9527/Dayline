# Dayline 开发日志：本地实时 STT 接入与真机验证

日期：2026-05-09  
工作区：`E:\codexapp\Dayline\dayline_app`  
主线目标：把 Dayline 的语音入口从系统 `speech_to_text` 切到离线本地流式 STT，并在真机上验证可用性、记录问题、规划下一轮优化。

## 1. 今日结论摘要

今天完成了 Dayline 语音入口的一次核心架构迁移：从依赖 Android 系统语音服务的 `speech_to_text`，改为基于 `record` + `sherpa_onnx` + Silero VAD 的本地离线流式 STT。

这条方向是正确的，原因很明确：当前真机没有系统 `RecognitionService`，系统语音识别不可用，继续围绕 `speech_to_text` 修补只会不断撞到设备能力边界。切到本地引擎后，已经做到断网可用、App 内模型加载、实时 partial、最终文本进入原有记录确认流程，并且不再出现 `SpeechToTextPlugin: Speech recognition not available on this device`。

但当前还没有达到理想体验。真机上已经能识别，但用户反馈速度和准确率都不够稳定：例如“吃饭二十分钟”里“分钟”出现较慢，且多次尝试才准确，也出现过“枝花”等误识别。这说明当前瓶颈已经从“系统语音不可用”转移到“模型选择、热词、后处理、VAD/endpoint 参数、实时解码性能”。

最新代码状态：

- `flutter analyze` 通过。
- `flutter test` 通过，当前测试数量为 145 个。
- 早前 `flutter build apk --debug` 已通过，并成功安装到真机测试。
- 最新一次把 STT 解码迁移到 worker isolate 后，已通过 analyze/test，但尚未重新打包安装到真机做最后一轮 smoke test。

## 2. 今天的对话与需求演进

### 2.1 真机测试与模块问题报告

最开始的目标是：连接 Android 真机，把 App 写入手机，用插件或工具进行测试，记录日志，先对各个板块测试并形成问题报告，后续再讨论解决方案。

这一步确立了今天的工作方式：

- 真机优先，不只看模拟器。
- 先观察日志和 UI 状态，再改代码。
- 每个问题要沉淀成报告，不只临时口头结论。

已有 QA 报告位置：

- `docs/qa/2026-05-09-device-smoke/QA_REPORT.md`

### 2.2 关于“能不能直接操控手机”

用户问能否直接操控实机、是否需要截图、有没有插件可以做到。

结论：

- Codex 不能像人手一样“直接触摸手机屏幕”。
- 可以通过 ADB 间接操控真机：安装 APK、启动 Activity、输入文本、点击坐标、滑动、抓取 logcat、抓取 UI 层级、截图。
- 插件更擅长模拟器和浏览器自动化；真机依然主要依赖 ADB。
- 因此真机测试的可靠路径是：`adb install`、`adb shell am start`、`adb shell input`、`adb logcat`、`uiautomator dump`、截图或 UI 层级检查。

### 2.3 系统语音不可用

用户问“真机语音能接入系统的吗”。

检查后发现当前真机没有可用的 Android 系统语音识别服务：

- `adb shell cmd package query-services --brief -a android.speech.RecognitionService`
- 返回：`No services found`

日志中也出现：

- `SpeechToTextPlugin: Speech recognition not available on this device`

这说明不是 Flutter 代码简单配置问题，而是设备系统层缺少语音识别服务。继续依赖 `speech_to_text` 风险很高，尤其是国产 Android 机型、未安装 Google 服务、系统裁剪语音服务时。

因此用户提出“做个本地 stt 吧，文案也改下”，随后给出本地实时 STT 接入计划。

## 3. 本地实时 STT 方案 V2.1

用户最终确认的方案目标：

- 用本地离线 STT 替代系统 `speech_to_text`。
- Android 真机第一阶段优先。
- 完全离线可用。
- `record` 采集 PCM16 音频。
- `sherpa_onnx` Zipformer 做实时识别。
- Silero VAD 做语音活动检测。
- 热词文件增强生活记录高频词。
- 保留 debug mock engine。
- release 下本地引擎不可用时只提示文字输入，不再错误提示“模拟器语音不可用”。

核心 UI 文案：

- loading：`正在唤醒离线大脑...`
- ready：`时刻准备记录你的灵感`
- listening：`正在本地识别...`
- unavailable：`离线语音暂不可用，请使用文字记录`
- debug fallback：`离线语音暂不可用 · 点击生成测试记录`

核心体验要求：

- 录音时显示实时波形。
- partial 文本浅色显示。
- final 文本正常显示。
- 识别结束后做轻量后处理：去掉开头或独立的“嗯、啊、那个、就是”等口头填充词，并补齐中文标点。

第一版不做：

- 情绪识别。
- 复杂词级置信度显示。
- web/desktop 本地 STT。
- 低电量、省电模式、音乐抢占专项测试。

## 4. 模型下载与资产处理

### 4.1 选择模型

用户提供了 sherpa-onnx v1.13.1 release 页面，并询问应该下载哪个文件：

- `https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.1`

判断结果：

- v1.13.1 release 页面主要是 SDK/plugin/runtime 发布，不是具体 ASR 模型。
- 本次需要下载的是 ASR 模型 release 里的模型包。

建议使用的模型与 VAD：

- `sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16.tar.bz2`
- `silero_vad.onnx`

模型路线：

- 中文/英文双语。
- streaming Zipformer。
- int8 版本。
- 优先小模型，控制 APK 体积和端侧速度。

### 4.2 用户放入的文件

用户将模型文件放入 `assets/stt` 后，工作区中出现：

- `assets/stt/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16(1).tar.bz2`
- `assets/stt/silero_vad.onnx`
- `assets/stt/life_keywords.txt`

原始 tar 包大小约 458 MB。

### 4.3 重新打包 App 内模型资产

为了避免 Flutter 直接打包巨大 tar 包，也避免普通 Git 历史被大模型污染，做了以下处理：

- 解压原始 tar 包。
- 只选取 int8 推理所需文件：
  - `encoder-epoch-99-avg-1.int8.onnx`
  - `decoder-epoch-99-avg-1.int8.onnx`
  - `joiner-epoch-99-avg-1.int8.onnx`
  - `tokens.txt`
  - `bpe.model`
  - `silero_vad.onnx`
  - `life_keywords.txt`
- 生成 `assets/stt/dayline-stt-v1.zip`。
- 为 zip 内文件生成 `manifest.json`，记录 checksum。
- 将原始 tar 和 standalone `silero_vad.onnx` 移到 `.codex_tmp/stt_downloads/`，避免进入 Flutter assets。
- 添加 `.gitattributes`：
  - `assets/stt/**/* filter=lfs diff=lfs merge=lfs -text`

当前模型资产策略：

- App 内只打包一个压缩后的 `dayline-stt-v1.zip`。
- 首次使用时解压到 app support directory。
- 后续启动校验 checksum。
- 校验失败则删除并重新解压。

## 5. 代码实现概览

### 5.1 pubspec 与平台配置

`pubspec.yaml` 调整：

- 移除：
  - `speech_to_text`
- 新增：
  - `archive`
  - `crypto`
  - `path_provider`
  - `record`
  - `sherpa_onnx`
- 添加资产：
  - `assets/stt/`

`android/app/src/main/AndroidManifest.xml` 调整：

- 保留 `RECORD_AUDIO`。
- 移除不再需要的 `INTERNET`。
- 移除旧的 `android.speech.RecognitionService` query。

### 5.2 STT 抽象层

新增 `lib/core/stt/stt_engine.dart`。

主要内容：

- `SttAvailabilityStatus`
  - `loading`
  - `ready`
  - `unavailable`
  - `error`
- `SttAvailability`
- `SttMetadata`
- `SttTranscript`
- `SttEngine`
- `SttListenSession`

这样 UI 和业务层不直接依赖 sherpa-onnx，也方便 fake/mock 测试。

### 5.3 音频处理

新增 `lib/core/stt/stt_audio.dart`。

主要能力：

- `pcm16ToFloat32`
  - 将 `record` 输出的 PCM16 little-endian bytes 转成 `Float32List`。
  - 范围归一化到 `[-1, 1]`。
- `rmsAudioLevel`
  - 根据 PCM16 计算 RMS。
  - 驱动录音中波形显示。

对应测试：

- `test/core/stt/stt_audio_test.dart`

### 5.4 文本后处理

新增 `lib/core/stt/stt_text_post_processor.dart`。

第一版规则：

- 清理开头或独立出现的口头填充词：
  - `嗯`
  - `啊`
  - `呃`
  - `额`
  - `那个`
  - `就是`
  - `这个`
- 合并多余空白。
- 如果末尾没有中文或英文标点，则补 `。`。

对应测试：

- `test/core/stt/stt_text_post_processor_test.dart`

当前不足：

- 还没有针对“枝花”等生活记录误识别做领域纠错。
- 还没有将“二十分钟”“吃饭”“买牛奶”等短句建立专门的修正规则。

### 5.5 资产管理

新增 `lib/core/stt/stt_asset_manager.dart`。

主要能力：

- 将 `assets/stt/dayline-stt-v1.zip` 解压到 app support directory。
- 读取 `manifest.json`。
- 校验 sha256 checksum。
- checksum 失败时删除并重新解压。
- 防止 zip-slip 路径穿越。
- 后来将解压过程迁移到 `compute(...)` 后台 isolate，避免首次解压时卡 UI。

对应测试：

- `test/core/stt/stt_asset_manager_test.dart`

### 5.6 Debug fallback

新增 `lib/core/stt/debug_stt_engine.dart`。

用途：

- debug 或非 Android 场景下保留 mock engine。
- 不依赖真实麦克风和模型。
- 方便 widget test 和日常开发。

### 5.7 Provider 选择

新增 `lib/core/stt/stt_providers.dart`。

当前策略：

- Android 平台使用 `LocalSttService.instance`。
- debug 非 Android 使用 mock engine。
- release 非 Android 或不可用平台返回 unavailable engine。

### 5.8 本地 STT 服务

新增并多轮修改 `lib/core/stt/local_stt_service.dart`。

当前最新架构：

- UI isolate：
  - 负责 `record` 权限与麦克风 PCM16 stream。
  - 计算 RMS audio level。
  - 将 PCM chunk 用 `TransferableTypedData` 发送给 worker isolate。
- Worker isolate：
  - 初始化 `sherpa.initBindings()`。
  - 创建 `OnlineRecognizer`。
  - 创建 Silero VAD。
  - 创建 recognizer stream。
  - 维护 pre-roll buffer。
  - 根据 VAD 判断是否有人声。
  - 将有人声片段送入 ASR。
  - 节流 partial decode。
  - 根据静音时间触发 endpoint/final。

迁移 worker isolate 的原因：

- 用户反馈“卡住了，能识别，就是有点慢”。
- STT 解码如果在 UI isolate 执行，会造成 UI 响应变差。
- 将模型解码挪到 isolate 后，UI 手势和动画更有机会保持流畅。

当前注意事项：

- worker isolate 代码已通过 `flutter analyze` 和 `flutter test`。
- 还没有在真机上重新 build/install 验证实际体验。

## 6. Flash Record 页面集成

### 6.1 状态模型调整

`FlashRecordState` 从旧的系统语音状态改为本地引擎状态。

新增或调整字段包括：

- STT availability/status
- partial text
- final text
- audio level
- `SttMetadata`

状态含义：

- loading：本地引擎加载中。
- ready：本地引擎准备好。
- listening：正在本地识别。
- unavailable：不可用，引导用户文字输入。
- error：本地引擎异常，可重试。

### 6.2 Notifier 调整

`FlashRecordNotifier` 改为依赖 `SttEngine`。

主要流程：

1. 页面进入后懒加载本地 STT。
2. 用户长按语音按钮。
3. 启动 `record` 音频流。
4. 收到 partial 时更新浅色文本。
5. 收到 final 时进入原有 parser。
6. 生成确认卡片。
7. 保存后重置页面状态。

修复点：

- `cancelConfirm()` 和 `resetAfterSaved()` 保留 STT ready/loading 状态，避免保存或取消后 UI 又回到错误的 loading。
- 语音不可用时不再允许按钮继续触发录音，避免“按钮灰了但还能点导致卡住”的体验。

### 6.3 UI 文案与波形

新增 `lib/features/flash_record/widgets/audio_waveform.dart`。

UI 变化：

- 文案改为本地离线 STT 语义。
- listening 时显示实时波形。
- 波形基于 RMS/amplitude，不依赖识别结果。
- partial 文本用浅色。
- final 文本转为正常颜色。

## 7. 真机测试记录

### 7.1 设备信息

今日使用的真机信息：

- Device ID：`3432033034001K3`
- 机型：vivo V2154A
- Android：14

历史观察：

- 设备时间曾显示为 2024-05-27。
- `auto_time=0`。

该时间问题不是 STT 主线问题，但后续做日志、证书、文件时间、网络请求时可能造成干扰。

### 7.2 安装与权限

第一次安装时出现：

- `INSTALL_FAILED_ABORTED: User rejected permissions`

原因：

- 用户侧拒绝了安装权限或安装确认。

后续使用：

- `adb install -r -g build\app\outputs\flutter-apk\app-debug.apk`

安装成功。

### 7.3 第一次本地 STT 启动错误

真机启动后出现本地引擎错误：

- `Please initialize sherpa-onnx first`

原因：

- 创建 recognizer/VAD 前没有调用 `sherpa.initBindings()`。

解决：

- 在创建 sherpa 对象前显式调用 `sherpa.initBindings()`。

### 7.4 第二次本地 STT 崩溃

修复 init 后，真机出现崩溃。

日志关键线索：

- `query_head_dims does not exist in metadata`

原因：

- 2023-02-16 这个 Zipformer 模型不应配置为 `modelType: 'zipformer2'`。
- `zipformer2` 对模型 metadata 有不同预期。

解决：

- 将 `modelType` 改为 `''`。

结果：

- 真机可以进入 ready 状态。
- UI 显示：`时刻准备记录你的灵感`。
- 不再出现系统语音不可用日志。

### 7.5 解码策略冲突

为了速度尝试过 `greedy_search`，但同时保留 hotwords，导致 sherpa 配置错误。

日志含义：

- 如果提供 hotwords file，decoding method 必须使用 `modified_beam_search`。
- `greedy_search` 与 hotwords 不兼容。

解决：

- 恢复 `modified_beam_search`。
- 将 `maxActivePaths` 从 4 降到 2，减少解码开销。

### 7.6 用户最新体验反馈

用户反馈：

- “卡住了，能识别，就是有点慢。”
- “识别准确和速度都不太行。”
- 测试语句：“吃饭二十分钟。”
- 现象：
  - “分钟”很慢才识别出来。
  - 试了 3-4 次才准确。
  - 出现过误识别为“枝花”。

判断：

- 当前已经不是“不可用”问题，而是体验质量问题。
- 需要同时从模型、热词、参数、后处理四个方向优化。

## 8. 验证命令与结果

### 8.1 依赖安装

执行：

- `flutter pub get`

结果：

- 成功。

环境注意：

- Windows 用户目录包含中文和特殊字符，Gradle/Kotlin 解析 pub cache 路径时曾失败。
- 解决方式：使用项目内 ASCII 路径作为 `PUB_CACHE`。
- 示例路径：
  - `E:\codexapp\Dayline\dayline_app\.codex_tmp\pub-cache`

### 8.2 静态分析

执行：

- `flutter analyze`

最新结果：

- 通过。

### 8.3 单元测试

执行：

- `flutter test`

最新结果：

- 通过。
- 当前全量测试数量：145 个。

覆盖范围：

- STT 音频转换。
- STT 文本后处理。
- STT 资产管理。
- checksum 失败重解压。
- Flash Record 新文案和 UI 状态。
- 既有业务测试。

### 8.4 Debug APK 构建

执行过：

- `flutter build apk --debug`

结果：

- 通过。
- APK 路径：
  - `build/app/outputs/flutter-apk/app-debug.apk`
- APK 大小约 287 MB。

注意：

- 这个构建结果是在 worker isolate 最新改造之前完成并真机验证过。
- worker isolate 最新改造后尚需重新执行 debug build 和真机安装验证。

## 9. 已解决问题清单

### 9.1 系统语音服务缺失

问题：

- 真机没有 Android `RecognitionService`。
- `speech_to_text` 不可用。

解决：

- 移除系统语音方案。
- 接入本地离线 STT。

状态：

- 已解决。

### 9.2 错误文案误导

问题：

- 原先文案倾向于“模拟器语音不可用”，但真机也可能因为系统服务缺失不可用。

解决：

- 改为本地离线引擎语义：
  - `正在唤醒离线大脑...`
  - `时刻准备记录你的灵感`
  - `正在本地识别...`
  - `离线语音暂不可用，请使用文字记录`

状态：

- 已解决。

### 9.3 模型初始化错误

问题：

- `Please initialize sherpa-onnx first`

解决：

- 创建 sherpa 对象前调用 `sherpa.initBindings()`。

状态：

- 已解决。

### 9.4 Zipformer modelType 配置错误

问题：

- `query_head_dims does not exist in metadata`

解决：

- 将 2023 Zipformer 模型的 `modelType` 改为 `''`。

状态：

- 已解决。

### 9.5 hotwords 与 greedy_search 冲突

问题：

- 提供 hotwords file 时不能使用 `greedy_search`。

解决：

- 使用 `modified_beam_search`。
- 降低 `maxActivePaths` 控制性能开销。

状态：

- 已解决。

### 9.6 语音不可用时仍可触发按钮

问题：

- 按钮视觉上不可用，但点击/长按仍可能触发录音逻辑。
- 用户体感为“卡住”。

解决：

- `VoiceButton` 在 `voiceAvailable == false` 时不再触发 start。

状态：

- 已解决。

### 9.7 首次解压可能卡 UI

问题：

- 模型 zip 解压和 checksum 校验可能较重。

解决：

- 解压迁移到 `compute(...)` 后台 isolate。

状态：

- 已解决。

### 9.8 解码占用 UI isolate

问题：

- STT decode 在 UI isolate 上执行时可能造成交互卡顿。

解决：

- 新版 `LocalSttService` 将 recognizer/VAD/endpoint 逻辑迁移到 worker isolate。
- UI isolate 只负责录音、RMS、状态分发。

状态：

- 代码已完成并通过 analyze/test。
- 仍需真机 rebuild/install 验证。

## 10. 当前未解决问题

### 10.1 识别速度不够理想

用户反馈：

- “分钟”很慢才出来。

可能原因：

- streaming Zipformer partial 对尾部词确认较谨慎。
- endpoint 静音阈值偏保守。
- partial decode 节流间隔较大。
- VAD 需要等待足够语音窗口。
- 低端或中端机 CPU 上 int8 模型仍有明显计算负担。
- `modified_beam_search` 为了热词牺牲了一部分速度。

下一步建议：

- 真机安装 worker isolate 版本，确认 UI 卡顿是否改善。
- 单独调低 partial decode interval。
- 调整 endpoint trailing silence。
- 保留热词时继续用 `modified_beam_search`，但测试 `maxActivePaths=1/2/4` 的速度与准确率。
- 如果速度仍不理想，评估更适合中文短句生活记录的模型。

### 10.2 准确率不稳定

用户反馈：

- “吃饭二十分钟”需要 3-4 次才准确。
- 出现“枝花”等误识别。

可能原因：

- 当前 hotwords 偏泛，缺少“吃饭”“分钟”“二十分钟”等高频生活短句。
- 小模型对短语、量词、生活口语的稳定性不足。
- 没有领域纠错层。
- 手机麦克风环境、距离、说话速度会影响短句识别。

下一步建议：

- 扩展 `life_keywords.txt`。
- 加入轻量 domain correction：
  - 将明显误识别词映射到生活记录高频词。
  - 针对“枝花”等误识别建立可维护词表。
- 建立 10-20 条固定短句 baseline，每次改模型或参数后重复测试。
- 对比更大或更新的中文模型。

### 10.3 真机 worker isolate 版本尚未最终验收

当前状态：

- 代码已写完。
- analyze/test 已通过。
- 还没重新 build/install 到真机。

下一步：

- `flutter build apk --debug`
- `adb install -r -g build\app\outputs\flutter-apk\app-debug.apk`
- 真机测试：
  - 不说话是否不生成乱码。
  - “今天跑步三十分钟”是否能进入确认卡片。
  - “吃饭二十分钟”速度和准确率是否改善。
  - logcat 是否没有 sherpa isolate 错误。

## 11. 下一轮优化计划

### P0：先验证 worker isolate 版本

目标：

- 确认最新代码在真机可运行。
- 判断“卡住”是否明显缓解。

步骤：

1. 重新 build debug APK。
2. 安装到真机。
3. 断网启动。
4. 等待 `正在唤醒离线大脑...` 进入 `时刻准备记录你的灵感`。
5. 长按录音测试短句。
6. 抓取 logcat。

验收：

- 不崩溃。
- UI 不明显卡顿。
- partial 能出现。
- final 能进入确认卡片。

### P0：扩展生活记录热词

当前已有热词方向：

- 跑步
- 买牛奶
- 周报
- 体重
- 睡觉
- 咖啡
- 待办
- 番茄
- 加班
- 心情
- 焦虑
- 开心

建议补充：

- 吃饭
- 早餐
- 午餐
- 晚餐
- 宵夜
- 分钟
- 二十分钟
- 三十分钟
- 花了
- 支出
- 记账
- 喝咖啡
- 买咖啡
- 散步
- 运动
- 会议
- 开会
- 复盘
- 读书
- 洗澡
- 睡眠
- 早睡
- 晚睡
- 难过
- 生气
- 放松

注意：

- 热词不是越多越好。
- 应优先加入 Dayline 高频意图词和用户真实说法。
- 每次扩展后要做 baseline 对比。

### P0：建立误识别纠错表

第一批可以针对用户已经遇到的问题：

- `枝花` -> 待观察，可能根据上下文纠为 `吃饭` 或其他生活词，但不能盲目全局替换。

建议做法：

- 不做硬编码全局替换。
- 建立 context-aware correction：
  - 如果句子中出现时间量词、分钟、运动、吃饭等上下文，再应用修正。
  - 保留原始 transcript 到 metadata，便于排查。

### P1：调整 VAD 与 endpoint

可调方向：

- pre-roll 长度。
- VAD threshold。
- min speech duration。
- min silence duration。
- endpoint trailing silence。
- partial decode interval。

目标：

- 不说话时不生成乱码。
- 说完短句后尽快 finalize。
- 不截断尾字。

重点场景：

- “吃饭二十分钟。”
- “待办买牛奶。”
- “花了十八元买咖啡。”
- “心情有点焦虑。”

### P1：模型对比

当前模型：

- `sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16`
- int8
- streaming

优点：

- 体积和速度相对可控。
- 可离线。
- Flutter 接入路径已经跑通。

不足：

- 中文生活短句准确率不稳定。
- 尾部词确认较慢。
- 小模型对口语短句和噪声环境可能吃力。

下一轮可以评估：

- sherpa-onnx 其他中文 streaming 模型。
- 更大一些的 Zipformer。
- Paraformer 类中文模型。
- SenseVoiceSmall 作为后续路线，但第一版不接情感识别。

### P2：专项测试

延后但需要记录：

- 低电量模式。
- 省电模式。
- 后台/前台切换。
- 音乐播放时音频焦点抢占。
- 嘈杂环境。
- 连续 5 分钟录音的发热和稳定性。

## 12. 建议建立的 STT baseline

为了让后续优化不靠感觉，建议固定一组短句，每次改模型、热词、VAD、endpoint 后都测。

### 安静环境

1. 今天跑步三十分钟。
2. 吃饭二十分钟。
3. 待办买牛奶。
4. 花了十八元买咖啡。
5. 心情有点焦虑。
6. 今天睡觉太晚了。
7. 明天写周报。
8. 体重七十公斤。
9. 番茄钟二十五分钟。
10. 今天加班到九点。

### 轻微噪声

1. 我在路上散步二十分钟。
2. 晚饭花了三十五元。
3. 买了一杯冰美式。
4. 今天心情还不错。
5. 明天上午开会。

### 不说话

目标：

- 不生成乱码。
- 不进入确认卡片。
- 波形可以动，但 STT final 应为空。

## 13. 文件地图

核心 STT 文件：

- `lib/core/stt/stt_engine.dart`
- `lib/core/stt/local_stt_service.dart`
- `lib/core/stt/debug_stt_engine.dart`
- `lib/core/stt/stt_providers.dart`
- `lib/core/stt/stt_audio.dart`
- `lib/core/stt/stt_text_post_processor.dart`
- `lib/core/stt/stt_asset_manager.dart`

Flash Record 集成：

- `lib/features/flash_record/application/flash_record_notifier.dart`
- `lib/features/flash_record/application/flash_record_state.dart`
- `lib/features/flash_record/presentation/flash_record_page.dart`
- `lib/features/flash_record/widgets/voice_button.dart`
- `lib/features/flash_record/widgets/audio_waveform.dart`

模型资产：

- `assets/stt/dayline-stt-v1.zip`
- `assets/stt/life_keywords.txt`
- `.gitattributes`

测试：

- `test/core/stt/stt_audio_test.dart`
- `test/core/stt/stt_text_post_processor_test.dart`
- `test/core/stt/stt_asset_manager_test.dart`

QA 报告：

- `docs/qa/2026-05-09-device-smoke/QA_REPORT.md`

临时下载和解压材料：

- `.codex_tmp/stt_downloads/`

## 14. 风险与注意事项

### APK 与存储体积

当前 debug APK 约 287 MB。模型内置后，安装包和安装后占用都会明显增加。

这是本地离线 STT 的预期代价，但后续需要：

- 确认 release APK 体积。
- 确认是否需要 ABI split。
- 确认是否需要模型按需下载。

### Git LFS

已经添加 `.gitattributes`，但后续提交前需要确认 Git LFS 已安装并正确跟踪：

- `git lfs install`
- `git lfs track`
- `git lfs status`

否则大模型 zip 可能仍污染普通 Git 历史。

### Flutter/Gradle 路径问题

Windows 用户目录含中文和特殊字符时，Kotlin/Gradle 对 pub cache 路径处理可能失败。

建议固定使用项目内 ASCII `PUB_CACHE`：

- `E:\codexapp\Dayline\dayline_app\.codex_tmp\pub-cache`

### Android 平台限定

当前第一版只保证 Android 真机方向。

非 Android：

- debug 可用 mock。
- release 应提示不可用并引导文字输入。

### 模型质量

当前最主要风险是模型质量达不到 Dayline 生活记录体验标准。

如果经过热词、后处理、VAD/endpoint、worker isolate 优化后仍不够好，需要接受更换模型路线，而不是继续在错误模型上过度打补丁。

## 15. 当前现状

已经完成：

- 系统 STT 依赖移除。
- 本地 STT 抽象层。
- sherpa-onnx 接入。
- record PCM16 音频流接入。
- Silero VAD 接入。
- 模型资产打包、解压、checksum 校验。
- 热词文件接入。
- 录音波形。
- partial/final 文本展示。
- 轻量文本后处理。
- debug mock engine。
- Android 真机初步跑通。
- analyze/test 通过。

正在验证中：

- worker isolate 后的真机表现。

主要待解决：

- “吃饭二十分钟”等生活短句识别速度与准确率。
- 热词扩展。
- 领域纠错。
- VAD/endpoint 参数调优。
- 模型路线评估。

下一步最建议做：

1. 重新构建并安装 worker isolate 版本到真机。
2. 用固定 baseline 记录每句的 partial 延迟、final 延迟、识别文本。
3. 扩展 `life_keywords.txt`。
4. 加入保守的生活词纠错层。
5. 再次对比 analyze/test/build/真机日志。

## 16. 一句话复盘

今天已经把 Dayline 从“受限于系统语音服务是否存在”推进到了“自有本地离线 STT 可控链路”，这是架构层面的关键转折；下一轮的重点不再是能不能识别，而是把短句生活记录的速度、准确率和稳定性打磨到用户愿意每天用。
