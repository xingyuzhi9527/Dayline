# 开发日志：盘页重构 → 长笔记 → 时间线优化 → 改名 Liflow

**日期**: 2026-05-13 ~ 2026-05-14  
**工作区**: `E:\codexapp\Dayline\dayline_app`  
**验证**: `dart analyze` 零错误 + `flutter test` 178/178 全过

---

## 一、盘页重构（计划书: `docs/dashboard_review_ball_plan.md`）

### 数据层
- 新建 `daily_reviews_repository.dart` — `daily_reviews` 表（date/kept/adjust/next_action）
- `local_database.dart` v1→v2→v3 迁移
- 新建 `dashboard_providers.dart` — `DashboardSummary` 聚合类 + `dashboardSummaryProvider`
- 替换 `DashboardPage` 全部假数据为真实数据源

### 复盘球
- 新建 `widgets/review_orb.dart` — 呼吸动画复盘球（260px，21点节奏条）
- 展开态：今日状态 / 节奏条 / 组成胶囊 / 洞察 / 复盘输入 / 生成笔记
- 新建 `widgets/dashboard_expanded.dart` — 六大区块组件
- 球体动画优化：`AnimatedBuilder.child` 缓存 + `RepaintBoundary` 隔离

### Markdown 导出统一
- `DaylineNotes/daily/YYYY/MM/YYYY-MM-DD.md` — 每日复盘
- `DaylineNotes/notes/YYYY/MM/YYYY-MM-DD_HH-mm_title.md` — 长笔记
- 首次使用弹窗配置目录（`MarkdownDirectoryDialog`）

## 二、长笔记系统（计划书: `docs/long_note_markdown_plan.md`）

### 核心模块
- `lib/core/markdown/markdown_filename.dart` — 文件名生成（3种模式）+ 非法字符清理
- `lib/core/markdown/markdown_directory_service.dart` — 统一目录管理
- `lib/core/markdown/markdown_note_service.dart` — 保存每日复盘/长笔记 + front matter

### 编辑器
- 新建 `lib/features/long_note/` — 全屏编辑器（标题 + Markdown 正文 + 工具条）
- `MarkdownToolbar` — H1/H2/B/I/[]/-/>/```/表格模板 插入
- 编辑模式：打开已有笔记 → 修改 → 覆盖保存 + 更新记录索引
- 保存自动写入时间线（`type: long_note`）

### 阅读视图
- `MarkdownReader` — 纯 Dart 解析渲染（标题/加粗/斜体/列表/引用/代码块/表格）
- 点击长笔记卡片 → 阅读视图 → 双击或右上角编辑按钮 → 编辑器

### 入口
- 记页展开键盘胶囊 → `edit_note` 图标打开长笔记编辑器

## 三、时间线优化

### 回收站
- `records` 表加 `is_deleted` 字段（软删除）
- `RecordsRepository`: softDelete / restore / findDeleted / permanentDelete
- 时间线标题栏右侧常驻垃圾桶图标 + 红色数字徽章
- 点击弹出 bottom sheet：恢复 / 永久删除

### 布局调整
- 待办和长笔记移至时间线右侧（左: memo/sleep/mood/...，右: todo/long_note）
- 卡片标题限制 3 行 + 溢出省略
- 添加 `long_note` 到图标/标签/颜色映射（绿色 + edit_note 图标）

### 编辑简化
- 日常记录编辑：只保留 **内容 + 标签 + 删除**，移除假的"修改时间"
- 多行文本框加 `TextInputAction.newline` 支持换行
- 长笔记编辑：打开全屏编辑器，加载已有内容（JSON metadata 解码）

## 四、记页交互优化

### 键盘按钮响应
- **核心修复**：同一 tap 不再同时触发展开+收起（`_dismissAmbientState` 加 `_keyboardLaunchExpanding` 守卫）
- 键盘关闭动画期间点击 → 延迟 180ms 重试（`_keyboardHiding` 标记）
- `didChangeMetrics` 去掉 `addPostFrameCallback` 延迟 → 键盘来的瞬间直接展开
- Fallback 500ms + 焦点重试 + 400ms 防误收窗口

### 波形动画丝滑
- `AudioWaveform` 从 `StatelessWidget` 改为 `StatefulWidget` + `Ticker`
- 内部做平滑插值（每帧逼近目标值 18%），消除 dBFS 跳变抖动

### 待办面板
- 上滑阈值从 30px→18px，速度从 -420→-250，横向容差 34→52
- 关闭动效加 `RepaintBoundary` + `ShaderMask` 隔离，消除掉帧

## 五、页面滑动导航

- `DaylineShell` → `StatefulWidget` + `PageView` + `PageScrollPhysics`
- `TickerMode(enabled: i==current)` 关闭非当前页动画（复盘球呼吸休眠）
- 底部导航与 PageView 双向同步（`_fromNavTap` 防重复触发）

## 六、UI 微调

- 删除顶栏 "我的日记" + 菜单 + 设置按钮（无功能占位）
- 盘页文案：*今天 N 条碎片 / 还在生长 / 该收束了 / 今日已收束*
- 盘页布局对齐记页：`Align(0, -0.03)` + 复盘球放大 260px + 底部 pill 120×48
- 球体光晕缩小（220→190px），眼睛图标下移（`Alignment(0, 0.12)`）

## 七、改名 Liflow

### 覆盖范围
- `package:dayline_app/` → `package:liflow_app/`
- `DaylineApp/Shel​​/KB` → `LiflowApp/Shell/KB`
- 数据库 `dayline.db` → `liflow.db`
- 笔记目录 `DaylineNotes` → `LiflowNotes`
- Android: namespace/applicationId/label/Kotlin package
- Web: title/manifest.json
- 导出文件名 `dayline_*` → `liflow_*`

### 验证
- `dart analyze lib/` — 零错误
- `flutter test` — 178/178 全过

### 构建问题
- Windows 中文用户名路径导致 Kotlin 编译器 crash（URL 编码 `（无密码）`）
- 解决方案：`subst Z: "E:\codexapp\Dayline"` 映射 ASCII 盘符编译

---

## 文件变更统计

### 新建文件
| 文件 | 用途 |
|------|------|
| `lib/core/database/daily_reviews_repository.dart` | 晚间复盘 CRUD |
| `lib/core/markdown/markdown_filename.dart` | 文件名生成 |
| `lib/core/markdown/markdown_directory_service.dart` | 统一目录管理 |
| `lib/core/markdown/markdown_note_service.dart` | 笔记保存服务 |
| `lib/features/dashboard/dashboard_providers.dart` | DashboardSummary 聚合 |
| `lib/features/dashboard/widgets/review_orb.dart` | 复盘球组件 |
| `lib/features/dashboard/widgets/dashboard_expanded.dart` | 展开态六区块 |
| `lib/features/markdown_setup/markdown_directory_dialog.dart` | 首次配置弹窗 |
| `lib/features/long_note/long_note_state.dart` | 编辑器状态 |
| `lib/features/long_note/long_note_notifier.dart` | 保存+索引 |
| `lib/features/long_note/long_note_editor_page.dart` | 全屏编辑器 |
| `lib/features/long_note/long_note_reader_page.dart` | 阅读视图 |
| `lib/features/long_note/widgets/markdown_toolbar.dart` | Markdown 工具条 |
| `lib/features/long_note/widgets/markdown_reader.dart` | Markdown 渲染器 |
| `lib/features/timeline/widgets/recycle_bin_bar.dart` | 回收站组件 |
| `test/features/dashboard/dashboard_providers_test.dart` | 聚合层测试 |
| `test/features/dashboard/review_orb_test.dart` | 复盘球测试 |

### 重度修改文件
| 文件 | 改动 |
|------|------|
| `lib/shell/dayline_shell.dart` → `liflow_shell.dart` | PageView 导航+改名 |
| `lib/features/dashboard/dashboard_page.dart` | 复盘球+展开态+改名 |
| `lib/features/flash_record/flash_record_page.dart` | 键盘响应+长笔记入口+改名 |
| `lib/features/timeline/widgets/timeline_list.dart` | 布局+编辑+回收站+改名 |
| `lib/core/database/repositories.dart` | 软删除+改名 |
| `lib/core/database/local_database.dart` | v2+v3 迁移+改名 |
| `lib/features/flash_record/widgets/audio_waveform.dart` | 平滑动画 |
| `lib/features/dashboard/widgets/review_orb.dart` | 性能优化+改名 |
| `pubspec.yaml` | 改名 |
| `android/app/build.gradle.kts` | 改名 |
| `android/app/src/main/AndroidManifest.xml` | 改名 |

## 测试覆盖
- 178 个测试全部通过
- 新增 11 个测试（dashboard providers + review orb）
- 更新旧测试适配新布局
