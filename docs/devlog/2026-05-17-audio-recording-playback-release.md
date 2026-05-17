# 2026-05-17 Audio Recording, Playback, and Release Build Devlog

## Summary

本次迭代把 Liflow 的语音记录从“只转文字”扩展为“可保存原始录音、可选择转文字、可在时间线播放录音附件”的完整闭环。同时对原音录制路径做了轻量化处理：留原音模式不再初始化离线 STT 模型，减少启动卡顿和功耗。

## User-Facing Changes

- 大话筒新增录音模式切换：
  - `转文字`：默认模式，录音后进入识别和闪记卡片确认流程。
  - `留原音`：录音后直接保存为语音片段。
- 转文字保存时，原始音频会作为附件一起保存。
- 时间线中的录音附件现在支持播放和停止。
- 同一时间只播放一个录音，播放另一条会自动切换。
- 录音播放结束、停止或页面销毁时会释放播放器资源。
- 生成了 release 签名 APK：
  - `E:\Liflow apk\liflow-v0.5.0-release.apk`

## Storage Behavior

- 临时录音文件只作为草稿存在。
- 用户保存成功后：
  - 音频复制到 Liflow 文档目录。
  - 数据库写入 `media_attachments` 记录。
  - 临时草稿 WAV 被删除。
- 用户取消确认、重新录音或页面销毁时，临时草稿会被清理。
- 永久删除带录音附件的记录时，同步删除本地音频文件。

## Implementation Details

### Audio Draft Model

扩展了 STT 接口：

- `SttRecordingDraft`
  - `path`
  - `duration`
  - `mimeType`
  - `sampleRate`
  - `codec`
- `SttTranscript.recordingDraft`
- `SttListenSession.stop({bool transcribe = true})`
- `SttEngine.startListening({bool transcribe = true})`

相关文件：

- `lib/core/stt/stt_engine.dart`
- `lib/core/stt/local_stt_service.dart`
- `lib/core/stt/debug_stt_engine.dart`
- `lib/core/stt/stt_providers.dart`

### Audio Save Service

新增 `AudioRecordingService`，负责：

- 创建语音片段记录。
- 把临时 WAV 复制到正式音频目录。
- 写入 `media_attachments(media_type = audio)`。
- 删除录音草稿。
- 删除 record 关联的音频附件文件。

相关文件：

- `lib/core/media/audio_recording_service.dart`
- `lib/core/markdown/markdown_directory_service.dart`

### Flash Record Flow

快速记录页新增：

- `FlashRecordingMode.audioOnly`
- `FlashRecordingMode.transcribe`
- `FlashRecordState.recordingDraft`
- `FlashRecordNotifier.saveAudioOnly()`
- 大话筒模式切换 UI

保存逻辑：

- `memo`、`sleep`、`mood` 类型会创建 record 并附加原始音频。
- `voice_memo` 用于只保存原音的语音片段。
- `todo`、`expense`、`focus`、`body`、`tracker` 暂不挂音频附件，避免改动通用附件模型。

相关文件：

- `lib/features/flash_record/flash_record_state.dart`
- `lib/features/flash_record/flash_record_notifier.dart`
- `lib/features/flash_record/flash_record_page.dart`

### Timeline Playback

时间线录音附件条新增播放按钮：

- 点击播放。
- 播放中点击停止。
- 文件缺失时显示错误状态。

播放实现使用 Android 原生 `MediaPlayer`，通过 MethodChannel 暴露给 Flutter：

- Dart:
  - `lib/core/media/audio_playback_service.dart`
- Android:
  - `android/app/src/main/kotlin/com/example/liflow_app/MainActivity.kt`

### Performance and Power Optimizations

- `留原音` 模式不再初始化 SenseVoice / STT worker。
- `留原音` 模式只检查麦克风权限和 WAV 编码支持。
- 播放器在停止、播放完成、错误或 Activity 销毁时释放。
- 播放状态集中在 `audioPlaybackProvider`，避免每条时间线卡片各自持有播放器。

## Release Build Notes

本次生成的是 release APK：

```powershell
C:\flutter\bin\flutter.bat build apk --release
```

项目存在：

```text
android/key.properties
```

因此 release 构建使用正式签名配置，而不是 debug 签名。

输出文件：

```text
E:\Liflow apk\liflow-v0.5.0-release.apk
```

注意：

- 后续只要继续使用同一个 release keystore 和同一个 `applicationId`，覆盖安装通常不会删除应用数据。
- 如果从 debug 签名包切换到 release 签名包，Android 会认为签名不同，可能需要卸载旧包，卸载会清除应用数据。
- release APK 体积较大主要来自离线 STT 模型和 native 推理库，不是签名导致。

## Verification

已运行：

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat build apk --debug
C:\flutter\bin\flutter.bat test test\features\flash_record\flash_record_notifier_test.dart test\widget_test.dart test\ui_redesign_test.dart
C:\flutter\bin\flutter.bat build apk --release
```

结果：

- Android debug APK 构建通过。
- Android release APK 构建通过。
- 录音和 UI 相关测试通过。
- `flutter analyze` 无本次新增错误，剩余为项目既有 warning/info。

## Git Commits

- `fc6df59` - `Add audio recording save flow`
- `26360a2` - `Add lightweight audio playback`

Both commits have been pushed to:

```text
origin/main
```

## Follow-Ups

- 使用 `--split-per-abi` 生成更小的 arm64 release APK。
- 清理或合并重复 STT 模型资源，降低安装包体积。
- 后续可考虑给 `todo`、`expense`、`focus` 等非 record 实体接入通用附件模型。
- 若需要后台播放或进度拖动，再评估是否引入专业音频播放插件。
