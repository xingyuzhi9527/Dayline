# 2026-07-13 性能优化开发日志：保存、月账单、资料库与盘页

## 背景

本轮处理三个用户感知明显的卡顿点：

- 语音输入后弹出卡片，点击保存后还要等待几秒转圈。
- 打开盘页面里的月账单卡顿。
- 点击盘页面资料库入口时卡顿。

定位后的共同根因是：SQLite 主数据保存、Markdown/音频镜像同步、月账单生成、资料库目录扫描和盘页统计重算都被放进了用户等待链路里。优化目标是把“用户需要立刻看到结果”的主路径变短，把派生同步、文件镜像和大目录扫描移到后台或缓存层。

## 今天完成了什么

### 1. 保存链路后台化

- 新增持久化派生同步 outbox：`derived_sync_jobs`。
- 语音/文本闪记保存时，SQLite 主写入完成后即可进入已保存状态。
- 日记草稿、月账单 Markdown、项目归档等派生任务改为后台 drain。
- 派生任务支持按 key 合并，例如 `daily:yyyy-MM-dd`、`expense:yyyy-MM`。
- 可见目录音频镜像从保存等待链路移出，避免外部文件复制拖慢保存反馈。

### 2. 月账单查询与打开路径优化

- 月账单 Provider 改为一次 `findByMonth()` 后在 Dart 内存里计算：
  - 总额
  - 分类统计
  - 每日统计
  - 最高消费日
- 点击“查看月账单”时不再“生成 → 写文件 → 再读文件”。
- 页面直接使用已加载的 `MonthlyExpenseSummary` 在内存中生成展示内容。
- Markdown 文件导出改为后台执行。

### 3. 资料库缓存与索引优先

- 资料库增加内存快照和持久快照，页面可以先显示上一次结果。
- 新增 SQLite 索引表 `library_items`。
- 资料库打开顺序改为：
  1. 内存缓存
  2. SQLite 索引
  3. 持久快照
  4. 必要时才扫描文件系统
- 扫描完成后会回写索引表。
- 删除文档、收藏/取消收藏 Markdown 笔记时同步维护索引。

### 4. 盘页 Dashboard 聚合查询

- 新增 `DashboardRepository` 和 `DashboardDayBundle`。
- 将原本分散的 records、todos、tracker、focus、expenses、body、review 查询收敛成共享 bundle。
- `dashboardSummaryForDateProvider`、`dashboardReviewForDateProvider` 和导出日记 Markdown 复用同一份日数据。
- 盘页展开导出时不再重复查询同一天的多张表。

### 5. 日记草稿同步减负

- 日记草稿的活动数量统计改为走各表 `countByDate()`。
- 多表计数使用并发查询，避免为了拿数量读取完整行数据。

### 6. Debug 性能埋点

新增轻量 `PerfTrace`，只在 debug 模式打印耗时，不影响 release：

- `flash_record.derived_sync_drain`
- `dashboard.day_bundle`
- `document_library.load`
- `monthly_expense.open_report`

后续真机测试时可以直接看这些日志判断慢点是否还集中在某条链路。

## 验证结果

已通过关键回归测试：

```text
flutter test --no-pub \
  test/features/flash_record/flash_record_notifier_test.dart \
  test/features/dashboard/daily_note_draft_test.dart \
  test/features/dashboard/dashboard_providers_test.dart \
  test/core/documents/document_library_service_test.dart \
  test/core/database/write_operations_repository_test.dart \
  test/core/database/derived_sync_jobs_repository_test.dart
```

结果：45 项全部通过。

新增规模回归：

- Dashboard 1000+ 条记录 summary 计算正确。
- 资料库 2000 条 SQLite 索引项可直接加载。

追加收尾：

- 修复 `lib/features/projects/projects_page.dart` 的 ReorderableListView API 兼容问题。
- `flutter analyze --no-pub` 已恢复无报错。

当前全量静态检查已经可以作为后续回归门禁使用。

### 7. APK 构建结果

- 通用 release 包已重新构建：`app-release.apk`
- `--split-per-abi` 已产出单独的 arm64 包：`app-arm64-v8a-release.apk`
- 体积对比：
  - 通用包约 `300.5 MB`
  - arm64 包约 `205.4 MB`
- 体积差主要来自三套 ABI native 库与离线语音模型一起进入通用包；arm64 单包更适合日常安装和分发。

## 当前进度表

| 优化项 | 状态 | 说明 |
|---|---|---|
| 保存完成边界前移 | 已完成 | 主 SQLite 写入完成后即可结束用户等待 |
| 派生同步 outbox | 已完成 | 日记、月账单、项目归档后台重试 |
| 文件 I/O 移出主等待链路 | 已完成 | 音频可见目录镜像后台化 |
| 月账单一次查询 + 内存生成 | 已完成 | 打开账单不再先写后读 |
| 资料库缓存优先 | 已完成 | 内存快照 + 持久快照 |
| 资料库索引优先 | 已完成 | 新增 `library_items` 表 |
| Dashboard 聚合收敛 | 已完成 | 新增 day bundle 共享查询结果 |
| 日记草稿计数减负 | 已完成 | 改为 count 查询 |
| Debug 性能埋点 | 已完成 | 关键链路输出 `[perf]` |
| 规模测试 | 已完成 | 覆盖 1000+ / 2000+ 场景 |

## 下一步做什么

建议下一轮按这个顺序继续：

1. 真机跑一遍三条主路径：
   - 语音卡片保存
   - 盘页月账单打开
   - 盘页资料库打开
2. 记录 debug 日志里的 `[perf]` 耗时，重点看：
   - `flash_record.derived_sync_drain`
   - `dashboard.day_bundle`
   - `document_library.load`
   - `monthly_expense.open_report`
3. 如果资料库仍慢，继续做增量索引：
   - 导入文件时写索引
   - 删除文件时删索引
   - 外部目录变化只在手动刷新或低频后台扫描时修复
4. 如果保存后仍有卡顿，继续拆分后台队列：
   - SAF 文件写入单独限流
   - 月账单 Markdown 同步与日记草稿同步分队列
   - 给失败任务增加可查看的诊断状态

## 备注

本轮没有引入云同步、账号系统或新的 ORM。SQLite 仍然是主数据源，Markdown/音频/资料库索引都作为可恢复的派生层处理。
