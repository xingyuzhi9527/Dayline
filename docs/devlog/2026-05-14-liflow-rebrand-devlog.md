# Dayline → Liflow 重命名开发日志

**日期**: 2026-05-14  
**工作区**: `E:\codexapp\Dayline\dayline_app`  
**主线**: 全项目从 Dayline 重命名为 Liflow。覆盖 lib/test/android/web/pubspec，不修改根目录名。

---

## 1. 改名范围

### Dart 代码 (lib/ + test/)
| 类别 | 旧 | 新 |
|------|----|----|
| 包名 | `package:dayline_app/` | `package:liflow_app/` |
| App 类 | `DaylineApp` | `LiflowApp` |
| Shell 类 | `DaylineShell` / `dayline_shell.dart` | `LiflowShell` / `liflow_shell.dart` |
| 数据库 | `dayline.db` | `liflow.db` |
| 笔记目录 | `DaylineNotes` | `LiflowNotes` |
| front matter | `source: dayline` | `source: liflow` |
| 日志标签 | `DaylineKB` / `DaylineInput` | `LiflowKB` |
| 用户提示 | "请允许 Dayline 使用麦克风" | "请允许 Liflow 使用麦克风" |
| 导出文件名 | `dayline_*.md` / `dayline_*.json` | `liflow_*.md` / `liflow_*.json` |
| 临时文件 | `dayline-stt-*` | `liflow-stt-*` |
| Isolate 名 | `DaylineSenseVoiceWorker` | `LiflowSenseVoiceWorker` |

### Android
- `namespace` / `applicationId`: `com.example.dayline_app` → `com.example.liflow_app`
- `AndroidManifest.xml` label: `dayline_app` → `Liflow`
- Kotlin 包目录: `dayline_app/` → `liflow_app/`
- `MainActivity.kt` package 声明更新

### Web
- `index.html`: title + meta description → Liflow
- `manifest.json`: name + short_name → Liflow

### pubspec.yaml
- `name: dayline_app` → `name: liflow_app`
- description 更新

## 2. 构建环境问题

### 根因
Windows 用户名 `ZhuanZ（无密码）` 含中文括号。Kotlin 编译器（Gradle daemon）在内部将路径进行 URL 编码，`（无密码）` 被编码为 `%EF%BC%88%E6%97%A0%E5%AF%86%E7%A0%81%EF%BC%89`，导致找不到源文件。

### 触发条件
`flutter clean` 清除了 `build/` 和 `android/.gradle/`（Gradle 增量编译缓存），Kotlin 编译器需要重新编译所有插件源码，但在中文路径下 crash。

### 解决方案
- `subst Z: "E:\codexapp\Dayline"` 将项目路径映射为 ASCII 盘符
- 在 Z: 盘下执行 `flutter build apk` 即可避开中文路径
- `PUB_CACHE` 和 `GRADLE_USER_HOME` 保持原始路径（缓存完整）

## 3. 验证状态

- `dart analyze lib/` — 零错误（仅 pre-existing warning + info）
- `flutter test` — 178/178 全部通过
- APK 构建 — 待 Z: 盘方案验证

## 4. 后续建议

- 彻底解决：建立纯英文 Windows 本地账户，将项目迁移过去
- 临时方案：`subst Z:` 映射 + 恢复 `flutter clean`
