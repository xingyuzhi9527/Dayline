---
name: flutter-android-build-deploy
description: Flutter Android 真机构建与部署完整指南。覆盖：APK构建, Gradle配置, adb安装, 签名, Windows中文路径, 国产手机兼容, Git LFS, APK体积优化, Impeller, 中国大陆镜像, 构建失败, 打包, 安装到手机, 真机测试, release签名。
---

# Flutter Android 真机构建与部署

从零到真机运行的完整 Flutter Android 构建部署流程，重点关注 Windows 环境、中国大陆网络、国产手机兼容性问题。

## 快速上手：验证流水线

```bash
flutter pub get
flutter analyze          # 零错误
flutter test             # 全部通过
flutter build apk --debug
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk
adb logcat -s flutter    # 观察启动日志
```

## 常见陷阱

### 陷阱 1：Windows 中文用户名路径问题（CRITICAL）

**症状**：Kotlin 编译器崩溃、`different roots` 错误、`file not found`、Gradle 构建失败

**根因**：Windows 用户目录包含非 ASCII 字符（如中文、全角括号）时，Kotlin/Ninja/Gradle 在解析 `PUB_CACHE`、`GRADLE_USER_HOME`、`.gradle` 等路径时会失败。这些工具的路径处理不支持 UTF-8 或 MBCS 编码的用户名目录。

**临时方案（推荐用于开发环境）**：

```powershell
# dev-shell.ps1 — 每次开发前执行
subst Z: "C:\Projects\MyApp"
$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"
# 从 Z:\my_app 构建，不要从原始路径构建
```

关键点：
- `Z:` 盘和 `PUB_CACHE` 必须在同一驱动器（Kotlin 增量编译要求）
- `GRADLE_USER_HOME` 也必须是纯 ASCII 路径
- 构建命令必须在虚拟盘路径下执行

**永久方案**：
1. 创建新的 Windows 用户账户，用户名仅含 ASCII 字符
2. 使用 WSL2 进行 Flutter Android 构建（WSL 内部路径均为 ASCII）
3. 更换开发机器时使用纯英文用户名

**验证方法**：
```bash
echo $USERPROFILE  # 如果有中文 → 受影响
flutter doctor -v   # 检查 Gradle 和 Android SDK 路径
```

### 陷阱 2：Gradle 中国镜像配置

**问题**：`google()` 和 `mavenCentral()` 在国内访问极慢或不可达，导致依赖下载超时。

**解决**：在 `android/build.gradle.kts` 中添加镜像：

```kotlin
repositories {
    maven { url = uri("https://maven.aliyun.com/repository/google") }
    maven { url = uri("https://maven.aliyun.com/repository/public") }
    maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public") }
    google()    // 保留为 fallback
    mavenCentral()
}
```

**注意**：镜像可能滞后于官方仓库，如果遇到 "artifact not found"，尝试临时只使用 `google()` + `mavenCentral()` 并开启代理。

### 陷阱 3：adb install 权限拒绝

**症状**：`INSTALL_FAILED_ABORTED: User rejected permissions`

**解决**：使用 `-r -g` 参数自动授予所有权限：

```bash
adb install -r -g app-debug.apk
# -r: 覆盖安装（保留数据）
# -g: 自动授予所有运行时权限（RECORD_AUDIO 等）
```

### 陷阱 4：Impeller 弃用警告

**症状**：每次启动日志中显示：
```
[Action Required]: Impeller opt-out deprecated.
The application opted out of Impeller by using the `--no-enable-impeller` flag
or the `io.flutter.embedding.android.EnableImpeller` AndroidManifest.xml entry.
These options are going to go away in an upcoming Flutter release.
```

**处理**：
- 如果有 `AndroidManifest.xml` 中 `<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />` — 需要在未来 Flutter 版本前移除
- 如果 Impeller 导致渲染问题，应在 GitHub 提 issue 而非依赖 opt-out
- 预期未来 Flutter 版本将移除 opt-out 选项

### 陷阱 5：安装包名冲突

**症状**：`INSTALL_FAILED_UPDATE_INCOMPATIBLE`

**根因**：设备上已有旧包名（如从 `com.example.old_app` 迁移到 `com.example.new_app`），或 debug keystore 发生变化。

**解决**：
```bash
adb uninstall com.example.old_package_name
adb install -r -g app-debug.apk
```

### 陷阱 6：国产手机日志干扰

**症状**：logcat 中出现大量 vivo/OPPO/小米 框架日志

**常见无害日志**：
```
Failed to get service:vcode                    # vivo 图像编码器
Access denied finding property "vendor.vivo..." # vivo 系统属性
Cannot find perfservice                         # vivo 性能服务
com.vivo.framework.securitydetect...            # vivo 安全检测反射监控
OpenGLRenderer: Unable to match desired swap behavior
```

这些是厂商框架的正常日志，不影响应用功能。过滤方式：

```bash
adb logcat -s flutter:V                          # 只看 Flutter 日志
adb logcat | grep -v "vivo\|perfservice\|OpenGL" # 排除已知噪声
```

### 陷阱 7：设备时间不准确

**症状**：`date` 显示 2024 年，实际是 2026 年

**根因**：`adb shell settings get global auto_time` 返回 `0`（手动时间）

**影响**：
- 带日期字段的数据（"今天"的记录会被归档到错误日期）
- 证书有效期校验
- 文件时间戳
- 网络请求中的时间校验

**建议**：
```bash
adb shell settings put global auto_time 1
# 或手动校准
adb shell "date $(date +%m%d%H%M%Y.%S)"
```

## APK 签名

### Debug 签名

默认使用 `$HOME/.android/debug.keystore`，由 Flutter 自动生成。适用于开发和测试。

### Release 签名

```kts
// android/app/build.gradle.kts
signingConfigs {
    create("release") {
        val keyProps = Properties()
        val keyPropsFile = rootProject.file("key.properties")
        if (keyPropsFile.exists()) {
            keyProps.load(keyPropsFile.inputStream())
            storeFile = file(keyProps["storeFile"] as String)
            storePassword = keyProps["storePassword"] as String
            keyAlias = keyProps["keyAlias"] as String
            keyPassword = keyProps["keyPassword"] as String
        }
        // fallback 到 debug 签名
    }
}
```

```
# android/key.properties（gitignored）
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=your_alias
storeFile=E:/path/to/keystore.jks
```

## APK 体积优化

### 现状参考

| 配置 | APK 体积 |
|------|---------|
| Debug + 大模型 (458MB) | ~287 MB |
| Debug + 中等模型 (72MB) | ~347 MB |
| Release (未验证) | 预期更小 |

### 优化策略

1. **ABI Split**（最有效）：
```bash
flutter build apk --split-per-abi
# 生成 arm64-v8a、armeabi-v7a、x86_64 三个 APK
```

2. **模型按需下载**：不将模型打包进 APK，首次启动时从 CDN 下载

3. **ProGuard/R8**：
```properties
# android/app/proguard-rules.pro
-keep class com.example.** { *; }
```

4. **资源压缩**：移除未使用的 drawable、字体、动画

## Git LFS 管理大文件

### 适用场景

模型文件（.onnx, .zip, .tar.bz2, .bin）超过 10MB 时应使用 Git LFS。

### 配置

```bash
git lfs install
git lfs track "assets/stt/**/*"
git lfs track "*.onnx"
```

```gitattributes
assets/stt/**/* filter=lfs diff=lfs merge=lfs -text
*.onnx filter=lfs diff=lfs merge=lfs -text
```

### CI 中的 LFS

```yaml
# GitHub Actions
- uses: actions/checkout@v4
  with:
    lfs: true
```

## adb 工作流速查

```bash
# 设备管理
adb devices                          # 列出设备
adb -s DEVICE_ID shell               # 指定设备
adb tcpip 5555                       # 开启无线调试
adb connect 192.168.1.100:5555       # 无线连接

# 安装与启动
adb install -r -g app.apk            # 覆盖安装 + 自动授权
adb uninstall com.example.app        # 卸载
adb shell am start com.example.app/.MainActivity  # 启动
adb shell am force-stop com.example.app            # 强制停止

# 日志
adb logcat -s flutter:V              # Flutter 日志
adb logcat -s DAYLINE_STT:*          # 特定 TAG
adb logcat -c                        # 清空日志缓冲

# UI 诊断
adb shell uiautomator dump           # 导出 UI 层级
adb exec-out screencap -p > screen.png  # 截图
adb shell dumpsys meminfo com.example.app  # 内存
adb shell dumpsys gfxinfo com.example.app  # 帧率

# 权限
adb shell pm list permissions -g     # 列出权限组
adb shell pm grant com.example.app android.permission.RECORD_AUDIO
```

## Build 环境配置清单

### Android SDK

```bash
flutter doctor -v
# 检查：
# - Android SDK 路径
# - Android SDK Platform-Tools (adb)
# - Android SDK Build-Tools
# - Android SDK Command-line Tools
# - JDK 17+
```

### Gradle 版本（示例，以当前稳定版为准）

```kts
// android/build.gradle.kts
plugins {
    id("com.android.application") version "<latest-stable>" apply false
    id("org.jetbrains.kotlin.android") version "<latest-stable>" apply false
}
// 已验证组合: AGP 8.11.1 + Kotlin 2.2.20
```

### Flutter 版本（示例）

```bash
flutter --version
# 以项目实际 SDK 约束为准（已验证: >=3.35.0）
```

## 平台兼容性

| 问题 | 影响设备 | 状态 |
|------|---------|------|
| 无系统语音服务 | vivo, OPPO, 小米(无GMS) | sherpa-onnx 替代 |
| 无法访问 GitHub | 国产设备 DNS | 模型 sideload 或 CDN |
| Impeller opt-out 警告 | 所有 Android | 关注 Flutter 更新 |
| vivo 安全检测日志 | vivo 设备 | 无害，过滤即可 |
| RECORD_AUDIO 权限 | Android 6+ | `-g` 自动授权 |

## 故障排查速查表

| 症状 | 可能原因 | 检查命令 |
|------|---------|---------|
| Gradle 构建失败 | 中文路径 | `echo $USERPROFILE` |
| 依赖下载超时 | 无镜像/GitHub 不可达 | `curl -I https://maven.aliyun.com` |
| 安装被拒绝 | 权限未授权 | 用 `-g` 参数 |
| APK 无法安装 | 包名冲突/签名变更 | `adb shell pm list packages` |
| App 闪退 | Native crash | `adb logcat -s AndroidRuntime:E` |
| 帧率低/卡顿 | Impeller 渲染问题 | 检查 enableImpeller 配置 |
