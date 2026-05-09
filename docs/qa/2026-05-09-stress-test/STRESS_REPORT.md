# Dayline 真机压力测试报告

日期：2026-05-09  
设备：`3432033034001K3` / vivo V2154A / Android 14  
包名：`com.example.dayline_app`  
测试范围：非语音压力测试。语音写入未测，按约定留给人工真机口播测试。

## 1. 测试摘要

本轮做了三类压力操作：

1. 文本写入自动化尝试。
2. 底部三 tab 高频切换。
3. `线` / `盘` 页面连续划屏。

结果：

- App 未崩溃，最终进程仍存活。
- 高频切页和划屏未发现 `RenderFlex overflowed`、`BOTTOM OVERFLOWED`、`FlutterError`、`ANR`、`FATAL EXCEPTION`。
- 文本写入自动化暴露了一个重要问题：在当前输入法和布局下，用 ADB 坐标批量点击发送不稳定，大量输入会停留在输入框里，不能视为成功写入。
- 数据库核验显示，本轮自动化真实新增记录很少，不应把脚本层面的 60/50 次输入尝试当成入库成功。

## 2. 测试材料

目录：

- `docs/qa/2026-05-09-stress-test/`

关键文件：

- `start.png`：测试开始截图。
- `after_writes.png`：第一次 60 次文本写入尝试后截图。
- `after_navigation.png`：84 次切页/划屏后截图。
- `after_enter_writes.png`：第二轮 Enter 提交尝试后截图。
- `current_after_failed_writes.png`：失败写入后的输入框状态截图。
- `submit_attempt.png`：尝试点击发送后设备回到桌面的截图。
- `text_write_steps.csv`：第一次 60 次写入尝试步骤。
- `enter_write_steps.csv`：第二次 50 次 Enter 写入尝试步骤。
- `navigation_scroll_steps.csv`：切页/划屏步骤。
- `logcat_full.txt` / `logcat_final.txt`：日志。
- `logcat_findings.txt` / `logcat_final_findings.txt`：异常关键字筛选结果。
- `meminfo.txt`：内存快照。
- `gfxinfo_framestats.txt`：帧统计。
- `after_50_enter_writes.db`：压力测试后的数据库快照。
- `db_final_snapshot.txt`：数据库数量和最近记录摘要。

## 3. 执行步骤

### 3.1 启动与日志清理

执行：

- 启动 App：`adb shell am start -n com.example.dayline_app/.MainActivity`
- 清理日志：`adb logcat -c`
- 抓取开始截图：`start.png`

结果：

- App 启动成功。
- 初始页面可见。

### 3.2 文本写入尝试一：坐标点击发送

执行：

- 循环 60 次：
  - 点击文本框。
  - 输入 `stress_todo_001` 到 `stress_todo_060`。
  - 点击预估的发送按钮坐标。

脚本层结果：

- 60 次 ADB 操作均完成。

数据库核验：

- 记录数未按 60 增长。
- 后续截图显示输入内容残留在文本框中。

结论：

- 这轮不能算“60 条成功写入”。
- 当前布局加输入法状态下，发送按钮坐标不稳定，ADB 批量点击容易点空或点到输入法区域。

### 3.3 页面切换和划屏压力

执行：

- 共 84 次动作：
  - 切到 `线`。
  - `线` 页面上/下划屏。
  - 切到 `盘`。
  - `盘` 页面上/下划屏。
  - 回到 `记`。

结果：

- App 未崩溃。
- 最终进程仍存活。
- 未筛到布局溢出或 Flutter 运行时异常。

注意：

- 写 CSV 时 PowerShell 出现过 2 次文件占用错误，但 ADB 操作本身已执行。
- 后续改为一次性写入步骤记录，避免逐行追加文件锁问题。

### 3.4 文本写入尝试二：Enter 提交

先做单条探针：

- 输入 `enter_submit_probe_001`。
- 发送 Enter keyevent。
- 数据库从 8 条 records 增至 9 条。

说明：

- `ENTER` 提交路径本身可行。

随后执行 50 次循环：

- 点击文本框。
- 输入 `enter_stress_001` 到 `enter_stress_050`。
- 发送 Enter keyevent。

数据库核验：

- records 最终从 9 增至 10。
- 只有 `enter_stress_001` 成功入库。

结论：

- 首次 Enter 提交有效。
- 保存后页面/焦点状态变化，后续自动输入没有稳定重新命中文本框。
- 当前 UI 对 ADB 自动化批量文本写入不友好。

## 4. 数据库核验

测试后数据库摘要：

```text
records: 10
todos: 5
```

最近 records：

```text
10|memo|enter——stress——001
9|memo|enter——submit——probe——001
8|memo|吃了一碗面
7|memo|明天记得戴头盔
6|memo|晚上记得洗袜子
5|memo|去了沃尔玛
4|memo|吃饭二十分钟
3|memo|拿快递
2|memo|记着拿快递的拿
1|memo|吃饭二十分钟
```

观察：

- ADB `input text` 会把 `_` 转成类似长横线的字符，这是系统输入法/ADB text 行为，不影响本轮关于“是否入库”的判断。
- 真正入库的自动化新增记录是：
  - `enter_submit_probe_001`
  - `enter_stress_001`

## 5. 日志与稳定性

筛选关键字：

- `FATAL EXCEPTION`
- `AndroidRuntime`
- `FlutterError`
- `RenderFlex overflowed`
- `BOTTOM OVERFLOWED`
- `ANR`
- `DatabaseException`
- `SQLiteException`

最终筛选结果：

- 未发现上述关键异常。

进程状态：

- 最终 pid：`9616`
- App 仍存活。

## 6. 性能快照

### 6.1 内存

来自 `dumpsys meminfo com.example.dayline_app`：

```text
TOTAL PSS: 500084 KB
TOTAL RSS: 609404 KB
Native Heap: 154588 KB
Java Heap: 16512 KB
Graphics: 87760 KB
Private Other: 181676 KB
```

判断：

- 内存占用偏高，但符合当前本地 STT 模型常驻、Flutter debug 包、真机图形资源叠加后的预期。
- 后续 release 包需要单独测一次内存，debug 数字不能直接代表线上表现。

### 6.2 帧统计

来自 `dumpsys gfxinfo ... framestats`：

```text
Total frames rendered: 78
Janky frames: 7 (8.97%)
50th percentile: 7ms
90th percentile: 18ms
95th percentile: 23ms
99th percentile: 1250ms
Number Missed Vsync: 2
Number High input latency: 62
```

判断：

- 大部分帧在可接受范围。
- 99 分位 1250ms 明显异常，可能来自启动、模型初始化、安装后首次绘制或页面切换时的重负载。
- 需要单独做一轮启动性能和 STT 初始化性能分析，不能只靠本轮混合压力测试判断。

## 7. 发现的问题

### P1：文本输入自动化不稳定

现象：

- 坐标点击发送时，脚本显示执行成功，但数据库没有新增对应记录。
- Enter 提交第一条有效，后续循环大量失效。
- 截图显示文本可能残留在输入框，或 App 被返回到桌面。

影响：

- 当前很难用纯 ADB 坐标做可靠的大批量文本写入压力测试。
- 用户手动输入不一定受影响，但自动化测试能力受限。

建议：

- 给文字输入框和发送按钮加更稳定的 widget key/semantics label，便于自动化通过 UI tree 定位。
- 或增加 debug-only 批量写入入口，只在 debug/profile 包开启，用于数据库和列表性能压测。
- 或编写 Flutter integration test，绕开系统输入法坐标问题。

### P1：输入框布局仍需继续打磨

现象：

- 键盘弹出时输入框位置已经不会溢出，但需要在更多输入法上验证。
- 输入法候选栏高度不同，`viewInsets` 与真实可点击区域可能不完全一致。

建议：

- 用多种键盘模式测试：全键盘、九宫格、英文键盘、手写/语音输入入口。
- 输入框 dock 位置最好由实际 `viewInsets` + 保守安全间距控制，避免写死偏移。

### P2：本地 STT 常驻带来的内存压力

现象：

- debug 状态下 TOTAL PSS 约 500 MB。

建议：

- release 包单独测。
- 增加“STT 未使用时延迟加载/可释放”策略评估。
- 分离启动冷路径和首次语音路径。

## 8. 已通过项

- App 在 84 次切页/划屏后未崩溃。
- 未出现新一轮 Flutter 布局溢出。
- 未出现数据库异常日志。
- `线`、`盘`、`记` 三个主 tab 可反复切换。
- SQLite 文件可正常拉取和读取。

## 9. 下一步建议

1. 加一个 debug-only 批量造数工具：
   - 一键插入 100 / 1000 / 5000 条 records。
   - 可选插入 todos、expenses、focus sessions。
   - 只在 debug/profile 开启，不进 release。

2. 增加自动化友好的语义：
   - 文本输入框：`record-text-input`
   - 发送按钮：`record-text-submit`
   - 三个 tab：`tab-line` / `tab-record` / `tab-review`

3. 继续做列表压力：
   - 先造 1000 条 timeline 数据。
   - 再测 `线` 页首屏、滚动、编辑、删除。

4. 单独做启动性能：
   - 冷启动。
   - 热启动。
   - 首次 STT 模型加载。
   - 模型已解压后的二次启动。

## 10. 总结

本轮压力测试结论不是“批量写入通过”，而是更真实地暴露了当前自动化瓶颈：页面切换和划屏稳定，App 没崩；但文字输入批量自动化不可靠，主要卡在输入法、焦点、发送按钮定位和保存后状态恢复。后续如果要严肃测“大量写入后的列表性能”，应该先加 debug 造数能力，再测数据库和 UI 渲染，而不是继续用 ADB 坐标硬点。
