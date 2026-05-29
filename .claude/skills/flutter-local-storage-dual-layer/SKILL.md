---
name: flutter-local-storage-dual-layer
description: Flutter 本地存储双层架构（SQLite + 文件镜像）。用于设计本地优先应用的数据持久化方案。覆盖：sqflite, SQLite, 本地数据库, 文件存储, Markdown存储, 备份恢复, 数据迁移, Repository模式, 数据库版本管理, SAF, 数据导出, 数据导入, 离线存储, 本地优先。
---

# Flutter 本地存储双层架构（SQLite + 文件镜像）

一种本地优先应用的数据持久化架构：SQLite 做主存储（快速查询），文件系统做可读镜像（数据可移植），两者互补，数据不锁定在应用内部。

## 适用条件

**适合的场景**：
- 日记、笔记、个人知识库等以单用户写作为主的应用
- 本地优先工具（数据主权在用户手中，不依赖云端）
- 需要"数据可移植性"的应用（换 App、换手机时数据不丢失）
- 用户希望用通用工具（文本编辑器、Markdown 阅读器）直接查看原始数据

**不适合的场景**：
- 需要多设备实时同步的协作应用（强一致性要求超出文件镜像能力）
- 多用户共享数据的系统（权限控制、并发冲突解决需要服务端）
- 复杂关系模型且查询频繁（大量 JOIN、聚合、子查询时，ORM 优势明显）
- 对写入性能有极端要求（双写有额外 I/O 开销）
- 需要端到端加密且文件级权限控制的场景

## 架构理念

```
┌──────────────────────────────────────┐
│              App 业务层               │
├──────────────────────────────────────┤
│  SQLite（主存储）    │  文件系统（镜像） │
│  - 结构化查询        │  - Markdown/JSON │
│  - CRUD 高效         │  - 人类可读      │
│  - 索引、聚合        │  - App 外可访问   │
│  - 跨表关联          │  - 备份/迁移      │
└──────────────────────────────────────┘
```

**为什么需要双层**：
- SQLite 数据在 app private 目录，用户不可见，App 卸载后数据丢失
- Markdown/JSON 文件放在用户可见目录，数据长期存活，可用任何工具打开
- 换手机、换 App 时，文件可以直接被新 App 读取和恢复

## 常见陷阱

### 陷阱 1：无 ORM 的 Schema 迁移缺乏框架保护

**问题**：使用原始 SQL 的 `onUpgrade` 手动管理版本迁移，每次加表/改列都需要手写 SQL，容易遗漏或写错。

**当前做法**（sqflite 原始 SQL）：

```dart
class LocalDatabase {
  static const _version = 4;

  Future<Database> open() async {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  void _onUpgrade(Database db, int oldVersion, int newVersion) {
    switch (oldVersion) {
      case 1:
        db.execute('ALTER TABLE records ADD COLUMN is_deleted INTEGER DEFAULT 0');
        db.execute('ALTER TABLE records ADD COLUMN tags TEXT');
        // fallthrough
      case 2:
        db.execute('ALTER TABLE records ADD COLUMN metadata TEXT');
        // fallthrough
      case 3:
        db.execute('''
          CREATE TABLE IF NOT EXISTS daily_reviews (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL UNIQUE,
            ...
          )
        ''');
    }
  }
}
```

**迁移规则**：
- 只用 `ALTER TABLE ... ADD COLUMN`，不重建表（防丢数据）
- 新列必须有 `DEFAULT` 值
- `onUpgrade` 用 `switch` + fallthrough（每个 case 不带 break），确保顺序执行
- 新的 `CREATE TABLE IF NOT EXISTS` 放在最后一个 case

**潜在风险**：
- 复杂变更（改列名、改类型、删列）SQLite 不支持直接 ALTER，需要重建表
- 没有编译时检查，字段名拼写错误要到运行时才发现
- 多版本累积后迁移代码变长且难以测试

**替代方案（如果需要更安全的迁移）**：
- 使用 `drift`（前身 moor）：编译时 SQL 检查 + 自动生成迁移
- 使用 `floor`：基于注解的 ORM + 迁移管理

### 陷阱 2：Map 传参无类型安全

**问题**：所有数据库操作使用 `Map<String, Object?>` 传参，字段名拼写错误到运行时才发现。

```dart
// 容易出错的写法
await db.insert('records', {
  'title': 'test',      // ← 字段名拼错，SQLite 不会报错，数据静默丢失
  'conten': 'body',     // ← 正确字段名是 'content'
});
```

**缓解策略**：
- 使用 Repository 基类统一 CRUD，减少自由写 SQL 的场景
- 为每个表定义字段名常量
- 考虑引入手写 model class（含 `toJson`/`fromJson`），不依赖 codegen

### 陷阱 3：SAF 与普通文件路径的双写复杂性

**问题**：Android 上使用 SAF（Storage Access Framework）获取的用户可见目录返回的是 `content://` URI，不能直接用 `dart:io` 的 `File` 操作；而 app private 目录是普通文件路径。

**处理方式**：

```dart
// 判断是否是 SAF URI
bool isSafUri(String path) => path.startsWith('content://');

// SAF 写入用 DocumentFile API
if (isSafUri(path)) {
  // 通过 Android DocumentFile 写入
} else {
  // 直接用 dart:io File 写入
}

// 双写：同时写到 private 目录和 SAF 目录
await _writeToPrivateDir(data);   // /data/data/.../files/
await _writeToSafDir(data);       // content://...
```

### 陷阱 4：恢复时的数据去重

**问题**：从 Markdown 文件恢复数据到 SQLite 时，如果用户多次恢复同一份文件，会产生重复数据。

**去重策略**：
- 按 `date + content` 组合去重
- 按 `date + timestamps` 判断是否同一条记录
- 恢复时先用已有数据做差集，只插入新记录
- 对 `UNIQUE` 约束的字段使用 `INSERT OR IGNORE`

## Repository 基类模式

```dart
typedef DatabaseRow = Map<String, Object?>;

class Repository {
  final Database _db;
  final String _table;

  const Repository(this._db, this._table);

  Future<int> insert(DatabaseRow row) =>
      _db.insert(_table, _withTimestamps(row));

  Future<DatabaseRow?> findById(int id) =>
      _db.query(_table, where: 'id = ?', whereArgs: [id]);

  Future<List<DatabaseRow>> findAll() =>
      _db.query(_table, orderBy: 'created_at DESC');

  Future<int> update(int id, DatabaseRow changes) =>
      _db.update(_table, _withTimestamps(changes, isUpdate: true),
          where: 'id = ?', whereArgs: [id]);

  Future<int> delete(int id) =>
      _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  DatabaseRow _withTimestamps(DatabaseRow row, {bool isUpdate = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!isUpdate) row['created_at'] = now;
    row['updated_at'] = now;
    return row;
  }
}
```

## 文件镜像实现

### 目录结构设计

```
用户文档/MyApp/           ← SAF 或本地路径，用户可见
  daily/                   ← 日记
    2026/
      05/
        2026-05-28.md
  notes/                   ← 长笔记
    2026/
      05/
        2026-05-28_14-30_会议记录.md
  documents/               ← 文档导入
    photos/
    audio/
  projects/                ← 项目存档
    我的项目/
      README.md
      updates.md
```

### Markdown 格式

```markdown
---
title: 2026-05-28 日记
date: 2026-05-28
tags: [工作, 生活]
---

## 记录

- [备忘] 今天跑步三十分钟 // 08:30
- [待办] 完成周报 // 14:00
- [消费] 咖啡 18元
- [心情] 状态还不错

## 复盘

### 保持
- 准时起床

### 调整
- 减少刷手机时间

### 下一步
- 明天开始阅读计划
```

## 备份与恢复

### 备份格式

```json
// backup_snapshot.json
{
  "version": "2.0.0",
  "exported_at": 1716800000000,
  "records": [...],
  "todos": [...],
  "projects": [...],
  "app_settings": [...]
}
```

### 恢复优先级

1. 优先从 JSON 快照恢复（结构化、精确）
2. 快照不存在则从 Markdown 文件扫描恢复
3. 两者都不存在则提示用户

### 恢复注意事项

- 不要恢复 `markdown_root_*` 相关的设置键（会覆盖当前设备的目录授权）
- 恢复后触发全量数据刷新（通知所有 Provider）

## 测试策略

### 内存数据库注入

```dart
// 生产代码
class LocalDatabase {
  final DatabaseFactory _factory;
  LocalDatabase({DatabaseFactory? factory})
      : _factory = factory ?? databaseFactory;
}

// 测试代码
void main() {
  sqfliteFfiInit();
  final db = LocalDatabase(
    factory: databaseFactoryFfi,
  );
  final database = await db.open(path: inMemoryDatabasePath);
  // 测试结束后自动销毁
}
```

**关键**：不要让业务代码直接依赖 `sqflite` 的全局单例，通过 `DatabaseFactory` 参数注入，测试时替换为 FFI 内存实现。

### 测试隔离

每个测试用例使用独立的 in-memory 数据库，确保用例之间不相互影响。

```dart
setUp(() async {
  database = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (db, version) async {
        // 创建完整 schema
      },
    ),
  );
});

tearDown(() async {
  await database.close();
});
```

## 依赖最小化原则

**选择 sqflite 原始 SQL 而非 Drift/floor 的条件**：
- 表数量 < 15
- 不需要复杂的跨表查询和 JOIN
- 团队对 SQL 熟练
- 希望依赖尽可能少

**以下情况应该考虑 ORM**：
- 表数量增长到 20+
- 需要流式监听数据变化（Drift 的 `watch()` 优于 `DataVersionNotifier`）
- 迁移越来越复杂（Drift 的 `schemaVersion` 自动检测）
- 需要编译时字段名检查

## 文件结构参考

```
lib/core/database/
  local_database.dart              # 数据库生命周期（open/onCreate/onUpgrade）
  repositories.dart                # 各表 Repository 实现
  repository_providers.dart        # Riverpod Provider 注册 + DataVersionNotifier

lib/core/markdown/
  markdown_directory_service.dart  # 根目录管理（本地路径 + SAF URI）
  markdown_storage_service.dart    # 文件读写（文件系统 + SAF 双写）
  markdown_note_service.dart       # 日记/笔记的保存和读取
  markdown_filename.dart           # 文件名生成规则
  markdown_document_parser.dart    # Markdown front matter + 正文解析

lib/core/export/
  export_service.dart              # Markdown / JSON 导出
```
