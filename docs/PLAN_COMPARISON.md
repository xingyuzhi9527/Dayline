# Dayline 三页重构计划对比

> 同一任务「Dayline 四页 → 三页（线/记/盘）」，对比两种工作方式的产出质量。

---

## 对比背景

| | flutter-beginner-orchestrator | Claude Code 自带 Plan Mode |
|---|---|---|
| 触发方式 | 用户调用 skill | Claude 自动进入 |
| 工作流 | 理解→检查→拆分→方案A/B→风险→验证 | 探索→设计→审核→输出 plan 文件 |
| 输出位置 | 直接聊天输出（无文件） | 写入 `.claude/plans/xxx.md` |
| 风格 | 面向小白，中文解释 | 面向工程师，精简技术向 |

---

## 计划 A：flutter-beginner-orchestrator 产出

*来源：skill 触发后，按 SKILL.md 规定的"大改功能工作流"在聊天中输出。*

### 1. 目标复述

把 Dayline 从"四页结构（今日/时间线/记录/复盘）"重构成"三页结构（线/记/盘）"：
- **线** = 原来的时间线，专注回看
- **记** = 新的核心入口页（默认页），中间大话筒，语音闪记为主、文字为辅
- **盘** = 今日概览 + 复盘合并，高信息密度仪表盘

核心理念：降低记录摩擦，把语音闪记变成 App 的第一交互。

### 2. 相关文件清单

按层次分组：

| 层 | 文件 |
|---|------|
| 路由 | `lib/app_routes.dart`（4 个枚举值）、`lib/app_router.dart`（4 个 branch） |
| 导航壳 | `lib/shell/dayline_shell.dart`（AppBar + 底部导航） |
| 记录页 | `lib/features/record/record_page.dart`、`record_state.dart`、`record_notifier.dart` |
| 输入条 | `lib/features/record/widgets/quick_input_bar.dart` |
| 今日页 | `lib/features/today/today_page.dart` + `widgets/today_cards.dart` |
| 复盘页 | `lib/features/review/review_page.dart` + `review_providers.dart` + `widgets/review_cards.dart` |
| 时间线 | `lib/features/timeline/timeline_page.dart` + `timeline_providers.dart` + `widgets/timeline_list.dart` |

### 3. 当前流程

```
打开 App → /today（今日首页）
底部 4 个 tab：今日 | 时间线 | 记录 | 复盘

记录流程：切换到"记录"tab → 打字 → 点"整理"→ 解析预览 → 确认保存
```

### 4. 方案 A：最小改动（推荐）

| 阶段 | 内容 | 文件数 |
|------|------|--------|
| A1 | 改路由和导航（4→3 tab，默认记） | 3 改 |
| A2 | 新建 `flash_record` feature（大话筒 + mock 识别 + 卡片确认） | 5 新建 |
| A3 | 新建 `dashboard` feature（合并 today + review） | 1 新建 |
| A4 | 更新测试 | 2 改 + 1 新建 |

- 不改已有 feature 目录内部结构
- 原有 today/review/timeline 代码不动
- 改动范围：约 12 个文件

### 5. 方案 B：更专业重构

彻底清理：合并 today/review 到 dashboard，删除原目录，统一导航类型映射。代价：改动范围大，需更多测试。

### 6. 推荐方案

**方案 A**——先把流程跑通，后续再清理。

### 7. 风险点

| 风险 | 等级 |
|------|------|
| 数据层不变，已有记录不受影响 | 🟢 |
| 已有页面文件不动，仍可被引用 | 🟢 |
| 路由分支数 4→3，需验证 index 映射 | 🟡 |
| 第一版纯 mock，不依赖任何 SDK | 🟢 |

### 8. 验证方式

```bash
flutter analyze
flutter test
flutter build apk --debug
```

### 特征总结

- ✅ 给出了方案 A/B 两个选项，让用户选择
- ✅ 说明推荐理由
- ✅ 风险分级标注
- ✅ 每阶段可独立验证
- ✅ 用中文解释了每个关键术语
- ❌ 没有写到持久化文件里（纯聊天输出）
- ❌ 阶段内没有精确到"每步改什么文件、什么代码"

---

## 计划 B：Claude Code 自带 Plan Mode 产出

*来源：进入 plan mode → 读取关键文件 → 启动 Explore 子 agent 全面探索 → 写入 plan 文件。*

### Plan 文件内容（`validated-jingling-marble.md`）

```markdown
# Dayline 三页重构：线 / 记 / 盘

## Context
当前 Dayline 是四页结构（今日/时间线/记录/复盘），用户要求重构成三页（线/记/盘），
核心目标是：降低记录摩擦，把语音闪记变成默认入口。

## 策略：方案 A（最小改动）
不改已有 feature 目录内部结构，新建 flash_record 和 dashboard 两个 feature，
改路由和导航壳。原有 today/record/review 目录保留不动。

## 阶段 A1：三 tab 导航重构

### 改 lib/app_routes.dart
- AppRoute 枚举从 4 个改为 3 个
- 记 使用麦克风图标

### 改 lib/app_router.dart
- 3 个 StatefulShellBranch
- initialLocation: AppRoute.record.path

### 改 lib/shell/dayline_shell.dart
- 底部导航栏突出中间"记"按钮：比其他大约 1.3x
- 导航文案单字 ['线', '记', '盘']

## 阶段 A2：记 页面 — 语音闪记

### 新建目录结构
lib/features/flash_record/
├── flash_record_page.dart
├── flash_record_state.dart
├── flash_record_notifier.dart
└── widgets/
    ├── voice_button.dart
    └── flash_card.dart

### 状态枚举
FlashPhase { idle, listening, recognized, confirming, saving, saved }

### 交互流程（6 步状态机）
1. idle: 大话筒 + "按住说话"
2. listening: 按钮 1.15x + 波纹 + "正在聆听…"
3. recognized: mock 文字 + 确认按钮
4. confirming: 弹出底部 FlashCard
5. saving: 复用 RecordNotifier._persist()
6. saved: SnackBar → idle

### Mock 识别
随机返回：跑步30分钟 / 午餐38元 / 待办 / 体重 / 番茄

## 阶段 A3：盘 页面
新建 dashboard_page.dart，组装 today_cards + review_cards 的已有 Widget

## 阶段 A4：测试更新
修改 widget_test.dart + ui_redesign_test.dart

## 不改的文件
数据库、解析器、主题、today/review/timeline 目录

## 验证
flutter analyze → flutter test → flutter build apk --debug
```

### 特征总结

- ✅ 写入了持久化 plan 文件，可追溯
- ✅ 精确到状态枚举定义、文件目录结构
- ✅ 列出了"不改的文件"明确边界
- ✅ 启动了子 agent 做代码探索（获取了更多上下文）
- ❌ 没有方案 A/B 对比，只有一个方案
- ❌ 没有风险分级
- ❌ 没有和小白的解释性语言
- ❌ 对用户的自然语言需求没有先"复述确认"

---

## 评分矩阵

请在每个维度打分（1-5 分，5 最好）：

| 维度 | A: orchestrator | B: plan mode | 备注 |
|------|:---:|:---:|------|
| 需求理解准确度 | __ | __ | 是否正确理解了用户意图 |
| 方案完整度 | __ | __ | 是否覆盖了所有必要的改动 |
| 方案可执行性 | __ | __ | 能否直接照着做 |
| 风险识别 | __ | __ | 是否标注了潜在问题 |
| 分阶段合理性 | __ | __ | 阶段划分和依赖关系 |
| 代码级精度 | __ | __ | 是否精确到具体文件和改动 |
| 小白友好度 | __ | __ | 不懂技术的人能否看懂 |
| 可追溯性 | __ | __ | 计划有文件留存，可复查 |
| 给用户的选择空间 | __ | __ | 是否给了多方案选择 |
| 不做什么的边界 | __ | __ | 是否明确了不改的范围 |

**总分**：A = __ / 50，B = __ / 50

---

## 你的判断

- 哪份计划更适合**你这个 Flutter 小白**直接照着做？
- 哪份计划更适合**丢给其他工程师**看？
- 如果让两个方式合作（orchestrator 做需求理解 + 方案选择，plan mode 做文件级精度 + 持久化），你觉得怎么样？
