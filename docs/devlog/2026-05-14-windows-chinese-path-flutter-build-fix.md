# Windows 中文用户路径导致 Flutter Android 构建失败复盘

**日期**: 2026-05-14  
**项目**: Liflow / 原 Dayline  
**工作区**: `E:\codexapp\Dayline\dayline_app`  
**当前可用构建入口**: `Z:\dayline_app`  
**真机设备**: `V2154A / 3432033034001K3 / Android 14 (API 34)`  

---

## 1. 结论先行

这次问题不是 Liflow 改名本身导致的。改名后的 Dart 代码、包名、Android `namespace` / `applicationId` 等可以正常进入构建流程。

真正的问题是 Windows 用户目录包含中文和全角括号：

```text
C:\Users\ZhuanZ（无密码）
```

Flutter Android 构建链路中会经过 Dart、Pub、Gradle、Kotlin、CMake / NDK、插件源码编译等多个工具。只要其中一环把这个路径做了不一致的编码、解码、转义或相对路径计算，就可能出现找不到源文件、Kotlin daemon 崩溃、JNI/C++ 编译失败等问题。

本次最终跑通的方案是：

```powershell
subst Z: "E:\codexapp\Dayline"

$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"

cd Z:\dayline_app
flutter pub get
flutter build apk --debug
flutter install --debug -d 3432033034001K3
```

成功结果：

```text
Built build\app\outputs\flutter-apk\app-debug.apk
Installed app-debug.apk to V2154A
```

APK 文件位置：

```text
Z:\dayline_app\build\app\outputs\flutter-apk\app-debug.apk
```

这个 APK 可以单独拷贝到手机安装，不需要 Flutter / Gradle / Dart 环境。

---

## 2. 根本原因

### 2.1 默认 Pub cache 在中文用户目录下

如果不显式设置 `PUB_CACHE`，Flutter / Dart 默认会把依赖下载到用户目录：

```text
C:\Users\ZhuanZ（无密码）\AppData\Local\Pub\Cache
```

`.dart_tool/package_config.json` 会记录每个依赖包的真实路径。问题发生时，这个文件里仍然有大量类似路径：

```text
file:///C:/Users/ZhuanZ%EF%BC%88%E6%97%A0%E5%AF%86%E7%A0%81%EF%BC%89/AppData/Local/Pub/Cache/hosted/pub.dev/...
```

这说明虽然项目路径后来映射到了 `Z:`，但插件源码仍然从中文用户目录进入编译链。

### 2.2 Kotlin / Gradle 对路径很敏感

Android 插件不是只编译项目自己的 Dart 代码。像 `record_android`、`sherpa_onnx`、`sqlite3`、`jni` 这类依赖会把 Kotlin、Java、C/C++、native hook 源码带进构建。

当这些源码位于中文用户目录时，Kotlin 编译器或 Gradle daemon 可能把路径二次编码，例如把：

```text
ZhuanZ（无密码）
```

处理成类似：

```text
ZhuanZ%EF%BC%88%E6%97%A0%E5%AF%86%E7%A0%81%EF%BC%89
```

或者在某些错误信息中变成非标准转义形式，最终导致编译器找不到真实文件。

### 2.3 `flutter clean` 会放大问题

`flutter clean` 本身不是错的，但它会清掉构建产物和部分增量缓存。清掉以后，Gradle / Kotlin 需要重新编译更多插件源码。

如果修复路径之前就执行 `flutter clean`，原本还靠缓存侥幸能过的部分会被迫全量重编译，于是中文路径问题更容易暴露。

修复路径之后，`flutter clean` 可以正常使用。

---

## 3. 已经尝试过的方案和结果

| 步骤 | 方案 | 结果 | 说明 |
| --- | --- | --- | --- |
| 1 | Liflow 重命名 | 改名本身可进入构建 | 问题不是改名逻辑 |
| 2 | 直接 `flutter build apk` | 失败 | 插件源码仍在中文用户目录 |
| 3 | `flutter clean` 后重试 | 问题扩大 | 缓存被清理后触发更多全量编译 |
| 4 | `subst Z: "E:\codexapp\Dayline"` | 部分解决 | 项目路径变 ASCII，但依赖仍可能在中文 Pub cache |
| 5 | `PUB_CACHE=C:\flutter_cache\pub_cache` | APK 可构建，但 Kotlin daemon 仍报异常 | 项目在 `Z:`，插件源码在 `C:`，Kotlin 增量缓存报 `different roots` |
| 6 | `PUB_CACHE=Z:\pub_cache` | 成功 | 项目和 Pub cache 同在 `Z:` 根下，构建干净通过 |
| 7 | `flutter install --debug -d 3432033034001K3` | 成功 | 已安装到真机 |

---

## 4. 当前已验证可用方案

### 4.1 每次开新终端后先确认 `Z:` 映射

`subst` 映射重启后会丢失。先执行：

```powershell
subst Z: "E:\codexapp\Dayline"
```

如果已经存在，可以用这个命令查看：

```powershell
cmd /c subst
```

期望看到：

```text
Z:\: => E:\codexapp\Dayline
```

### 4.2 当前终端设置环境变量

PowerShell 当前会话里应该这样设置：

```powershell
$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"
```

注意：不要在当前 PowerShell 里写 `export PUB_CACHE=...`。`export` 是 bash / Linux / macOS 风格，不是 PowerShell 语法。

也不要以为 `setx` 会影响当前窗口。`setx` 只影响之后新打开的终端，不会修改当前进程环境变量。

### 4.3 构建 debug APK

```powershell
cd Z:\dayline_app
flutter pub get
flutter build apk --debug
```

成功后 APK 在：

```text
Z:\dayline_app\build\app\outputs\flutter-apk\app-debug.apk
```

### 4.4 安装到真机

先确认设备：

```powershell
adb devices
flutter devices
```

本次设备是：

```text
3432033034001K3    device
V2154A             Android 14
```

安装：

```powershell
cd Z:\dayline_app
$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"
flutter install --debug -d 3432033034001K3
```

启动：

```powershell
adb -s 3432033034001K3 shell am start -n com.example.liflow_app/.MainActivity
```

---

## 5. 为什么 `PUB_CACHE=Z:\pub_cache` 比 `C:\flutter_cache\pub_cache` 更好

`C:\flutter_cache\pub_cache` 确实是 ASCII 路径，可以避开中文用户名。但它和当前项目路径 `Z:\dayline_app` 不在同一个根路径下。

这会触发 Kotlin 增量编译的另一个问题：

```text
this and base files have different roots:
C:\flutter_cache\pub_cache\hosted\pub.dev\record_android-1.5.1\...
and
Z:\dayline_app\android
```

所以当前最稳的临时方案是：

```text
项目:      Z:\dayline_app
Pub cache: Z:\pub_cache
Gradle:    C:\gradle-cache
```

这样项目源码和 Flutter 插件源码都在 `Z:` 根下面，Kotlin 计算相对路径时不会跨盘符。

---

## 6. 当前方案的限制

当前方案是稳定的临时方案，不是彻底方案。

它依赖三个条件：

1. `Z:` 必须存在，并且映射到 `E:\codexapp\Dayline`。
2. 构建时 `PUB_CACHE` 必须是 `Z:\pub_cache`。
3. 构建时 `GRADLE_USER_HOME` 必须是 ASCII 路径，例如 `C:\gradle-cache`。

只要某次新终端忘了设置这些，Flutter 就可能重新回到默认路径：

```text
C:\Users\ZhuanZ（无密码）\AppData\Local\Pub\Cache
```

然后同类问题会再次出现。

---

## 7. 半永久方案：保留当前 Windows 账号，但自动化 `Z:` 和缓存

如果暂时不想新建 Windows 账号，可以把当前方案固化为启动脚本。

### 7.1 新建脚本

例如保存为：

```text
E:\codexapp\Dayline\dev-shell.ps1
```

内容：

```powershell
if (-not (Test-Path "Z:\")) {
    subst Z: "E:\codexapp\Dayline"
}

$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"

Set-Location "Z:\dayline_app"

Write-Host "Liflow dev shell ready"
Write-Host "PUB_CACHE=$env:PUB_CACHE"
Write-Host "GRADLE_USER_HOME=$env:GRADLE_USER_HOME"
Write-Host "PWD=$(Get-Location)"
```

以后开发前运行：

```powershell
powershell -ExecutionPolicy Bypass -File E:\codexapp\Dayline\dev-shell.ps1
```

### 7.2 可选：写入用户环境变量

可以设置：

```powershell
setx PUB_CACHE "Z:\pub_cache"
setx GRADLE_USER_HOME "C:\gradle-cache"
```

注意：

- `setx` 对当前窗口无效，要新开终端。
- 如果开机后 `Z:` 还没映射，`PUB_CACHE=Z:\pub_cache` 会指向不存在的位置。
- 所以即使用 `setx`，仍然要保证 `subst Z:` 先执行。

### 7.3 这个方案的风险

这个方案能稳定日常构建，但并没有消除根因，因为系统用户目录仍然是：

```text
C:\Users\ZhuanZ（无密码）
```

某些工具仍可能读取 `USERPROFILE`、`HOME`、`PATH`、`.android`、`.gradle` 或 IDE 插件目录。只要某个工具绕过了我们设置的缓存变量，中文路径问题仍可能回来。

---

## 8. 彻底解决方案：使用纯 ASCII Windows 用户和纯 ASCII 开发路径

最彻底、最干净的方案是新建一个 Windows 本地账号，用户名只用英文、数字和普通连字符或下划线。

推荐示例：

```text
ZhuanZDev
liflowdev
dev
```

不要使用中文、空格、全角括号、emoji 或特殊符号。

### 8.1 为什么不建议直接改现有用户目录名

只改 Windows 显示名称没有用，真实目录仍然可能是：

```text
C:\Users\ZhuanZ（无密码）
```

强行改 `C:\Users\...` 目录名并修改注册表 ProfileImagePath 风险很高，可能影响应用、权限、商店应用、IDE、证书、SSH、Android keystore 等。

更安全的方式是新建纯英文账号，然后迁移开发环境。

### 8.2 新账号下推荐目录

建议使用全 ASCII 路径：

```text
E:\src\Dayline\dayline_app
C:\dev-cache\pub_cache
C:\dev-cache\gradle
C:\dev-cache\android
C:\Temp
```

或者：

```text
C:\src\liflow\dayline_app
C:\dev-cache\pub_cache
C:\dev-cache\gradle
```

重点是整条路径都不要出现中文、全角符号、空格或特殊字符。

### 8.3 新账号下设置环境变量

在新账号的 PowerShell 中执行：

```powershell
New-Item -ItemType Directory -Force C:\dev-cache\pub_cache | Out-Null
New-Item -ItemType Directory -Force C:\dev-cache\gradle | Out-Null
New-Item -ItemType Directory -Force C:\dev-cache\android | Out-Null
New-Item -ItemType Directory -Force C:\Temp | Out-Null

setx PUB_CACHE "C:\dev-cache\pub_cache"
setx GRADLE_USER_HOME "C:\dev-cache\gradle"
setx ANDROID_USER_HOME "C:\dev-cache\android"
setx TEMP "C:\Temp"
setx TMP "C:\Temp"
```

然后关闭当前 PowerShell，重新打开，让 `setx` 生效。

### 8.4 迁移项目

推荐用 Git 迁移，避免复制旧的构建缓存。

如果当前改动还没有提交，需要先在旧账号里处理当前工作区：

```powershell
git status
```

可以选择：

```powershell
git add -A
git commit -m "WIP Liflow rename and build path fix"
```

或者如果暂时不想提交：

```powershell
git stash push -u -m "WIP before ASCII user migration"
```

迁移到新账号后：

```powershell
git clone <repo-url> E:\src\Dayline\dayline_app
cd E:\src\Dayline\dayline_app
```

如果用了 stash，需要再恢复；如果用了 commit，就 checkout 对应分支即可。

不要复制这些目录：

```text
.dart_tool
build
android\.gradle
.gradle
```

这些都是生成缓存，迁移后应该重新生成。

### 8.5 新账号下重新生成构建缓存

```powershell
cd E:\src\Dayline\dayline_app
flutter pub get
flutter build apk --debug
```

第一次会比较慢，因为 Pub 和 Gradle cache 都会重新下载。

如果遇到旧缓存残留，可以执行：

```powershell
flutter clean
flutter pub get
flutter build apk --debug
```

在彻底 ASCII 环境下，`flutter clean` 不再是危险操作。

---

## 9. 采用彻底方案后，对当前方案有什么影响

### 9.1 `Z:` 映射可以废弃

如果项目已经迁移到纯 ASCII 路径，例如：

```text
E:\src\Dayline\dayline_app
```

那么不再需要：

```powershell
subst Z: "E:\codexapp\Dayline"
```

也不再需要 `Z:\pub_cache`。

### 9.2 `Z:\pub_cache` 可以保留，也可以删除

`Z:\pub_cache` 只是下载下来的 Pub 依赖缓存。彻底迁移后，如果新账号使用：

```text
C:\dev-cache\pub_cache
```

那么旧的：

```text
Z:\pub_cache
```

可以等新环境稳定后删除。删除它不会影响源码，只会影响以后是否需要重新下载依赖。

### 9.3 `C:\gradle-cache` 可以继续用，也可以迁移

`C:\gradle-cache` 是 ASCII 路径，理论上可以继续使用。但为了新账号环境更清晰，推荐改成：

```text
C:\dev-cache\gradle
```

影响只是第一次构建会重新下载 Gradle 依赖。

### 9.4 已安装在手机上的 debug APK 可能受 debug 签名影响

Android debug 包默认使用用户目录下的 debug keystore：

```text
C:\Users\<用户名>\.android\debug.keystore
```

换新 Windows 用户后，debug keystore 可能变成新的签名。这样再次安装到同一台手机、同一个包名：

```text
com.example.liflow_app
```

时，可能出现：

```text
INSTALL_FAILED_UPDATE_INCOMPATIBLE
```

解决方法有两种：

1. 不保留手机上的旧 debug app 数据：先卸载旧 app，再安装新包。
2. 要保留覆盖安装能力：把旧账号的 debug keystore 复制到新账号同路径。

旧账号 keystore：

```text
C:\Users\ZhuanZ（无密码）\.android\debug.keystore
```

新账号目标：

```text
C:\Users\ZhuanZDev\.android\debug.keystore
```

如果未来要正式分发，应该使用 release 签名，不要依赖 debug keystore。

### 9.5 `.dart_tool/package_config.json` 会随 `PUB_CACHE` 改变

`.dart_tool/package_config.json` 是生成文件。它会记录当前机器上的 Pub cache 路径。

当前临时方案里它会指向：

```text
Z:\pub_cache
```

彻底方案里它会指向：

```text
C:\dev-cache\pub_cache
```

这是正常现象。不要把 `.dart_tool` 当成源码迁移，也不要提交它。

---

## 10. 注意事项清单

### 10.1 当前临时方案下

- 开新终端后先确认 `Z:` 是否存在。
- 构建前确认 `$env:PUB_CACHE` 是 `Z:\pub_cache`。
- 构建前确认 `$env:GRADLE_USER_HOME` 是 ASCII 路径。
- 不要在 `E:\codexapp\Dayline\dayline_app` 下直接构建，优先在 `Z:\dayline_app` 下构建。
- 不要把 `PUB_CACHE` 指回 `C:\Users\ZhuanZ（无密码）\AppData\Local\Pub\Cache`。
- 不要把 `PUB_CACHE` 放在 `C:` 而项目放在 `Z:`，否则 Kotlin 可能再次出现 `different roots`。
- `setx` 后要新开终端才生效。
- `flutter clean` 只在确认路径变量正确后使用。

### 10.2 彻底迁移时

- 先保护当前未提交改动，使用 commit、stash 或完整备份。
- 新 Windows 用户名必须是纯 ASCII。
- 项目路径必须是纯 ASCII。
- Pub cache、Gradle cache、Android user home、Temp 都建议是纯 ASCII。
- 不要复制旧的 `.dart_tool`、`build`、`android\.gradle`。
- 第一次构建慢是正常的。
- 真机覆盖安装失败时优先检查 debug keystore 签名是否变化。

### 10.3 APK 使用

当前 debug APK：

```text
Z:\dayline_app\build\app\outputs\flutter-apk\app-debug.apk
```

可以直接拷贝到安卓手机安装，不需要开发环境。

但 debug APK 只适合测试：

- 体积可能更大。
- 性能不是最终 release 状态。
- 带 debug 签名。
- 手机可能提示需要允许未知来源安装。
- 不适合作为正式发布包。

正式分发应使用 release 构建和正式签名。

---

## 11. 推荐后续动作

短期继续开发：

```powershell
subst Z: "E:\codexapp\Dayline"
$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"
cd Z:\dayline_app
flutter build apk --debug
```

中期减少手误：

- 做一个 `dev-shell.ps1`，自动设置 `Z:`、`PUB_CACHE`、`GRADLE_USER_HOME`。
- 所有 Flutter 构建都从这个脚本开的终端执行。

长期彻底解决：

- 新建纯 ASCII Windows 用户。
- 把项目迁移到纯 ASCII 路径。
- 把 Pub / Gradle / Android / Temp 缓存都放到纯 ASCII 路径。
- 重新 `flutter pub get` 和 `flutter build apk --debug`。

---

## 12. 本次验证记录

本次实际验证过：

```powershell
$env:PUB_CACHE = "Z:\pub_cache"
$env:GRADLE_USER_HOME = "C:\gradle-cache"
cd Z:\dayline_app
flutter pub get
flutter build apk --debug
```

结果：

```text
Built build\app\outputs\flutter-apk\app-debug.apk
```

安装到真机：

```powershell
flutter install --debug -d 3432033034001K3
```

结果：

```text
Installing app-debug.apk to V2154A...
Installing build\app\outputs\flutter-apk\app-debug.apk...
```

启动：

```powershell
adb -s 3432033034001K3 shell am start -n com.example.liflow_app/.MainActivity
```

结果：

```text
Starting: Intent { cmp=com.example.liflow_app/.MainActivity }
Warning: Activity not started, intent has been delivered to currently running top-most instance.
```

这个 warning 表示应用实例已经在前台或已存在，不是安装失败。
