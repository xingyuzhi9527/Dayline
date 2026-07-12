# Liflow

> 本地优先的个人生活记录 App。快速记录，轻量整理，温和回顾。

Liflow 是一款 Android Flutter 应用，核心理念是**数据留在本地**：无账号系统、无广告、无埋点、无云端同步。笔记、语音、待办、项目进度、日记草稿、照片和导出的 Markdown 文件全部保存在手机里，你不删就一直在。

[下载 release APK](https://github.com/xingyuzhi9527/Dayline/releases/download/v2.0.0-build10/Liflow-v2.0.0-build10-release.apk) · [Release 页面](https://github.com/xingyuzhi9527/Dayline/releases/tag/v2.0.0-build10)

当前版本：`2.0.0+10`

## 四个页面

| 页面 | 做什么 |
|------|--------|
| **记** | 语音或文字快速记录，支持离线中文语音识别 |
| **线** | 按时间排列的生活时间线，含笔记、待办、长文、照片、回收站 |
| **项** | 个人项目管理，卡片、进度、待办、近期更新 |
| **盘** | 每日回顾面板，查看节奏和未完成项，写日记 |

核心理念：快速记、轻整理、慢回顾，原始数据即使离开 App 也能阅读。

## 本地优先的数据模型

结构化数据存 SQLite，可读副本镜像到手机存储的 `Liflow` 文件夹：

```text
Liflow/
  daily/
  notes/
  documents/
  projects/
```

这意味着：

- 数据默认留在设备上
- Markdown 文件可以脱离 App 查看
- 数据库清空后可从本地文件夹恢复
- 照片和录音附件以本地文件形式保存
- release 版本可直接从 GitHub Releases 安装

## 隐私

Liflow 不含登录、广告、埋点、追踪 SDK 或云同步。麦克风权限仅用于本地录音和离线语音识别。App 可能请求 Flutter 和录音等功能所需的 Android 平台权限，但应用代码未接入任何远程服务。

因为数据在本地，如果需要长期保存，建议自己备份 `Liflow` 文件夹。

## 功能亮点

- 语音 + 文字快速记录（中心「记」页面）
- 离线中文语音识别，模型文件打包在 `assets/stt/`
- 轻量输入解析：待办、时间提示、金额、备注
- SQLite 时间线浏览
- 长文编辑器 + Markdown 阅读器
- 项目工作区，本地 Markdown 持久化
- 每日回顾面板和日记写作
- 本地备份快照与恢复
- 照片时刻与本地文档库
- Android release 签名（通过本地 `android/key.properties`）

## 技术栈

- Flutter `>=3.35.0` / Dart `^3.9.0`
- Riverpod — 状态管理和依赖注入
- GoRouter — 带 indexed shell route 的 tab 导航
- sqflite — 本地 SQLite
- sherpa_onnx — 离线语音识别
- record — 音频录制
- 自研 Markdown/文件服务 — 可读导出与恢复

## 目录结构

```text
lib/
  core/
    database/     SQLite schema 和仓库层
    markdown/     Markdown 路径、持久化、恢复
    media/        音频、播放、照片服务
    parser/       轻量生活输入解析
    stt/          离线语音识别集成
    theme/        颜色、间距、字体 token
  features/
    flash_record/ 「记」页面
    timeline/     「线」页面
    projects/     「项」页面
    dashboard/    「盘」页面
    long_note/    长文笔记
    documents/    本地文档库
    restore/      Markdown 恢复流程
android/
  app/            Android 壳工程和签名配置
assets/
  stt/            离线 STT 模型和关键词
test/             单元测试、Widget 测试、仓库层测试
```

## 安装

Android 手机直接下载签名 release APK 安装：

```text
https://github.com/xingyuzhi9527/Dayline/releases/download/v2.0.0-build10/Liflow-v2.0.0-build10-release.apk
```

APK 体积较大是因为打包了离线语音识别模型。

## 开发

### 环境要求

- Flutter `>=3.35.0`，需配置 Android SDK 和 platform tools
- 一台 Android 真机或模拟器（离线 STT 目前仅支持 Android）

### 克隆和安装

```bash
git clone https://github.com/xingyuzhi9527/Dayline.git
cd dayline_app
flutter pub get
```

### STT 语音模型

离线语音识别依赖 `assets/stt/` 下的 SenseVoice 模型文件：

| 文件 | 大小 | 模型 |
|------|------|------|
| `sense_voice_small_zh.tar.bz2` | ~163 MB | SenseVoice 中文 |

这是标准的 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 模型。没有它 App 也能正常编译运行，语音录制不受影响，只是离线识别功能不可用。

### 日常命令

```bash
flutter run          # 在已连接设备上启动
flutter test         # 运行全部测试
flutter analyze      # 静态分析
```

运行单个测试文件或按名称过滤：

```bash
flutter test test/core/database/repositories_test.dart
flutter test --plain-name "restore"
```

### 打包 Release APK

```bash
flutter build apk --release
```

Release 签名需要本地提供 `android/key.properties`（已加入 .gitignore，不会进入版本库）。如果该文件不存在或字段不完整，release 构建会直接失败；debug 构建不受影响：

```properties
storePassword=<你的密钥库密码>
keyPassword=<你的密钥密码>
keyAlias=<你的密钥别名>
storeFile=<你的密钥库路径>
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

### 发布包体与 ABI

面向 Google Play 或其他支持 AAB 的商店，优先构建 AAB，让商店按设备 ABI
下发所需的 native 库：

```bash
flutter build appbundle --release
```

直接分发 APK 时使用 ABI 拆分，避免把 arm64、armeabi-v7a 和 x86_64 的
native 库全部装进同一个文件：

```bash
flutter build apk --release --split-per-abi
```

输出文件位于 `build/app/outputs/flutter-apk/`，名称会带有
`arm64-v8a`、`armeabi-v7a` 或 `x86_64`。当前 SenseVoice 模型约 163 MB，
仍是包体的主要来源；删除未使用的 Zipformer 压缩包后，仓库不再重复打包
那份约 56 MB 的模型。

Release 构建没有生产密钥时会直接失败，不会回退到 debug 签名。

## 版本

最新 release：

- Tag：`v2.0.0-build10`
- Commit：见 release tag
- APK：`Liflow-v2.0.0-build10-release.apk`
- SHA-256：`FD92FB53493473C736098D06A907CD33C03C58E9D57481DAF37EB9CEC990780C`

## 备注

仓库名仍为 `Dayline`，但 App 名称和产品方向已改为 `Liflow`。
