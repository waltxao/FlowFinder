# FlowFinder v0.7.5 — 独立内容索引契约（Wave2 T5）

> **本契约是 T6 实现的唯一依据。**
> T6（`feat(search): add cancellable FTS5 content index`）及 T7（FFI 接线与搜索面板状态集成）
> 的所有实现决策必须与本文档逐条一致。本文档不存在"待定/看情况"条款；每个决策点只有唯一结论。
> 本文档只读参考现有代码，不修改任何产品代码。

- 文档日期：2026-08-13
- 状态：已定稿（Wave2 T5 deliverable）
- 相关代码（只读参考）：
  - `rust-core/src/core/sqlite_cache.rs`（`init_cache` 的 drop-on-mismatch 危险模式，第 121–130 行）
  - `rust-core/src/core/fsevents.rs`（Wave1 T3 已实现的状态化生命周期：`WatcherStatus` / `start` / `stop` / `status`）
  - `rust-core/src/core/search_engine.rs`（现有文件名模糊匹配，无内容搜索）
  - `rust-core/src/ffi/mod.rs`（FFI 导出层；`ff_cache_init` / `ff_fsevents_start` / 取消注册表模式）
  - `rust-core/include/ff_ffi.h`（C 头文件）
  - `FlowFinderNative/FlowFinderNative/Bridge/FFIFunctions.swift`、`Bridge/CoreBridge.swift`、`Bridge/SearchBridge.swift`
  - `FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift`（`fileContainsText` 第 707–715 行）
  - `FlowFinderNative/FlowFinderNative/App/AppDelegate.swift`（Application Support 路径解析模式，第 72–106 行）

---

## 0. 背景、目标与硬性约束

### 0.1 审计发现

`SearchPanelController.swift` 的 `fileContainsText(path:query:caseSensitive:)`（第 707–715 行）在**主线程**通过
`Data(contentsOf:)` 逐文件读取每个搜索结果的文件内容（最多 4MB），与文件名模糊匹配结果串行叠加，
在搜索结果较多或文件较大时造成 UI 卡顿。用户已决定改为**独立内容索引**。

### 0.2 目标

把"内容包含"从逐文件主线程读取，改为**后台构建的 SQLite FTS5 内容索引**的一次性查询：
构建完成后，内容匹配是一个索引查询 + 集合成员判断，不再触碰文件系统。

### 0.3 硬性约束（本契约不可违反）

1. **不得复用目录缓存 DB，不得继承 drop-on-mismatch 行为。**
   `sqlite_cache.rs` 的 `init_cache` 在 `PRAGMA user_version != SCHEMA_VERSION` 时执行
   `DROP TABLE IF EXISTS dir_cache` 后重建（第 121–130 行）。内容索引使用**独立 DB 文件**
   `content_index.sqlite`，schema 版本不匹配时**绝不 drop**（见 §9）。
2. **不修改任何产品代码/测试/配置** —— 本任务是纯文档。
3. **每个决策点有且只有一个结论**，实现者零判断。

---

## 1. 决策点 1 — 存储位置（独立于目录缓存 DB）

### 唯一结论

内容索引 DB 位于：

```
~/Library/Application Support/FlowFinder/content_index.sqlite
```

- **独立文件**：与目录缓存 DB（`~/Library/Application Support/FlowFinder/dir_cache.db`）是**两个不同的文件**，
  由**两个不同的模块**、**两个不同的连接**访问，绝不共享 schema、连接池或版本号。
- **目录**：与 `dir_cache.db` 相同目录（`~/Library/Application Support/FlowFinder/`）。
  该目录已由 `AppDelegate.initPersistentDirectoryCache()`（第 72–106 行）创建并确保存在；
  内容索引初始化沿用同一目录（目录创建逻辑由 Swift 侧复用，Rust 侧不负责建目录）。

### 路径解析建议

**生产路径：Swift 解析，通过 FFI 传入 Rust（唯一方案）。**

- 完全沿用现有 `ff_cache_init` 模式（`AppDelegate.swift` 第 76–88 行 + `ffi/mod.rs` `ff_cache_init`）：
  1. Swift：`FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)`
  2. 追加 `FlowFinder` 目录：`appSupportURL.appendingPathComponent("FlowFinder", isDirectory: true)`
  3. 追加 DB 文件：`appDir.appendingPathComponent("content_index.sqlite", isDirectory: false)`
  4. 调用 `ff_content_index_init(db_path)` 把路径字符串传给 Rust。
- **Rust 侧不解析路径**（与 `ff_cache_init` 的 `CACHE_DB_PATH` `OnceLock` 模式一致）：
  Rust 通过 `ff_content_index_init` 接收路径并以 `OnceLock<String>` 保存，进程内只设置一次。
  这样做的好处：单一路径来源（Swift 的 FileManager 语义），Rust 不依赖任何平台路径 crate，
  与现有目录缓存保持完全一致的架构。

**测试/独立工具路径（仅当 Rust 需要脱离 Swift 自行解析时）**：
- 语义等价于 macOS 的 Application Support：`dirs::data_dir()` 返回 `~/Library/Application Support`。
  如 T6 需要自解析，在 `Cargo.toml` 增加 `dirs = "5"`，路径 = `dirs::data_dir()?.join("FlowFinder").join("content_index.sqlite")`。
- 本契约不要求 T6 增加 `dirs` 依赖 —— 生产路径由 Swift 传路径。**此段仅为文档说明，不作为 T6 的必做项。**

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `FlowFinderNative/FlowFinderNative/App/AppDelegate.swift` | 新增 `initContentIndex()`，解析 `content_index.sqlite` 路径并调用 `ff_content_index_init`（模式复制 `initPersistentDirectoryCache`）。 |
| `rust-core/src/ffi/mod.rs` | 新增 `ff_content_index_init` 及 `CONTENT_INDEX_DB_PATH: OnceLock<String>`。 |

---

## 2. 决策点 2 — 存储格式（SQLite FTS5）

### 唯一结论

SQLite **FTS5** 虚拟表，采用 **external content** 方案（`content='documents'` + `content_rowid='id'`）。

### 2.1 FTS5 方案选择：external content（选定），非独立 FTS5 表

| 方案 | 结论 |
|---|---|
| 独立 FTS5 表（`CREATE VIRTUAL TABLE f USING fts5(path UNINDEXED, body)`） | ❌ 拒绝。正文文本同时存在 FTS 影子表与身份表中，重复存储；无法用普通 SQL 对身份字段做增量失效判断。 |
| **external content（`content='documents'`）** | ✅ **选定**。`documents` 普通表保存身份 + 正文；FTS5 只保存倒排索引。身份/过期/计数用普通 SQL；索引损坏后可从 `documents.body` 用 `'rebuild'` 命令快速重建，无需重读文件。 |

### 2.2 Schema（版本 1，定稿）

```sql
-- PRAGMA user_version = 1（schema 版本，见 §9）

CREATE TABLE IF NOT EXISTS documents (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    path       TEXT    NOT NULL UNIQUE,   -- 绝对路径，UTF-8
    mtime      INTEGER NOT NULL,          -- 修改时间（UNIX 秒）
    size       INTEGER NOT NULL,          -- 文件大小（字节）
    body       TEXT    NOT NULL,          -- 抽取后的文本（UTF-8），可为空字符串
    indexed_at INTEGER NOT NULL           -- 索引时间（UNIX 秒）
);

CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
    body,
    content='documents',      -- external content：正文来自 documents.body
    content_rowid='id'        -- documents 的 rowid 列
);

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,   -- 'root_path' | 'checkpoint_path' | 'last_build_at' | 'document_count'
    value TEXT NOT NULL
);
```

### 2.3 FTS5 表与 documents 表的手动同步规则（external content 必做）

external content 表不会自动跟随 `documents`，所有写入必须显式同步：

- **新增**：`INSERT INTO documents(...)` 后，`INSERT INTO content_fts(rowid, body) VALUES(last_insert_rowid(), ?body)`。
- **删除**：`INSERT INTO content_fts(content_fts, rowid, body) VALUES('delete', ?id, ?body)`，再 `DELETE FROM documents WHERE id = ?id`。
- **更新（文件内容变化）**：先按"删除"执行，再按"新增"执行。**禁止 `INSERT OR REPLACE` 直接改 `documents`**，
  因为 REPLACE 会改变 AUTOINCREMENT rowid，破坏 FTS 链接。
- **整表重建 FTS 索引**：`INSERT INTO content_fts(content_fts) VALUES('rebuild')`（从 `documents.body` 重建，不重读文件）。

### 2.4 最小索引查询 SQL（T6 必须实现）

```sql
SELECT d.path, d.mtime, d.size
FROM content_fts
JOIN documents d ON d.id = content_fts.rowid
WHERE content_fts MATCH ?1
ORDER BY rank
LIMIT ?2;
```

- `?1` = FTS5 MATCH 表达式（见 §8.4 的转义规则）。
- `?2` = 结果上限（调用方传入，默认 500，与 `FFSearchOptions.max_results` 默认一致）。
- `rank` 为 FTS5 内置相关性排序列（在 `MATCH` 生效时可用）。

### 2.5 FTS5 运行时检测

- **检测命令**：`PRAGMA compile_options` 返回的行中必须包含 `ENABLE_FTS5`。
- **当前工程状态（已验证）**：`rusqlite = { version = "0.31", features = ["bundled"] }` 使用
  libsqlite3-sys 0.28.0 的 bundled 编译，其 `build.rs` 第 129 行带 `-DSQLITE_ENABLE_FTS5`；
  编译产物 `libsqlite3.a` 含 `fts5ApiCallback` 等 FTS5 符号。
  **因此 Cargo.toml 无需新增 feature 即可获得 FTS5。**
- **但 T6 仍必须在 `ff_content_index_init` 中做运行时检测**（防御未来切换到无 FTS5 的系统 SQLite）：
  打开 DB 后执行 `PRAGMA compile_options`，若不含 `ENABLE_FTS5`，进入 `unavailable` 状态（见 §6）。
- **降级策略（不崩溃）**：FTS5 不可用 → 状态 = `unavailable`；
  Swift 侧禁用"内容包含"复选框（置灰，不可勾选），并在状态行显示"内容搜索不可用"。
  查询接口 `ff_content_index_query` 在非 ready 状态一律返回 `FF_ERR_NOT_FOUND`（见 §8.3），不会触碰文件系统。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/Cargo.toml` | **无需改动**（bundled 已含 FTS5）。若未来切换为非 bundled SQLite，需在 features 中显式启用 FTS5 编译，并依赖 §2.5 运行时检测降级。 |
| `rust-core/src/core/content_index.rs`（T6 新建） | schema、FTS 同步规则、运行时检测。 |

---

## 3. 决策点 3 — 索引文件类型与大小策略

### 唯一结论

**扩展名白名单** + **大小上限 4MB** + **NUL 字节嗅探** + **编码探测顺序（BOM → UTF-8 → UTF-16 → ISO-8859-1）**。

### 3.1 默认索引扩展名（全小写比较）

```
txt md rtf json xml log csv s
h c cpp hpp py rs swift js ts mjs cjs html htm css
yaml yml toml ini cfg conf plist sh zsh bash
sql java kt go rb php lua m mm pl tex rst adoc org
env properties gradle
```

外加**无扩展名的已知文本名**（按 basename 全小写匹配）：

```
readme license makefile dockerfile gitignore gitattributes editorconfig
```

**排除规则（无条件跳过，不索引）**：
- 扩展名不在白名单中（`pdf doc docx xls xlsx ppt pptx` 等一切二进制/压缩/文档格式一律不索引）；
- 目录、符号链接、隐藏文件（`is_hidden`，与 `FileEntrySkeleton` 语义一致）、系统保护文件（`is_system_protected`）；
- 大小 > 4MB（见 §3.2）；
- 前 8KB 含 NUL 字节（见 §3.3 二进制嗅探）。

### 3.2 单文件大小上限

- **上限 = 4 * 1024 * 1024 字节（4 MiB）**，与现有 `fileContainsText` 的
  `data.count <= 4 * 1024 * 1024`（`SearchPanelController.swift:709`）完全一致。
- 大小在 `stat`/walk 阶段即可获得：**先查大小再决定是否读取**，超过上限的文件不读内容、不索引。

### 3.3 二进制检测

- 只对"扩展名在白名单内"的文件做**前 8KB 嗅探**：若前 8KB 含 NUL 字节（`0x00`），判定为二进制，跳过。
  （白名单内出现二进制内容极为罕见，此嗅探是第二道确定性防线。）

### 3.4 编码探测顺序（唯一顺序，T6 按此实现）

1. **BOM 嗅探**（文件头固定字节）：
   - `EF BB BF` → UTF-8
   - `FF FE` → UTF-16 LE
   - `FE FF` → UTF-16 BE
2. **UTF-8 严格校验**：`std::str::from_utf8` 成功 → 按 UTF-8 解码。
3. **UTF-16（仅当有 BOM）**：按 BOM 指定的端序解码，替换非法码元为 `U+FFFD`。
4. **ISO-8859-1（Latin-1）兜底**：每个字节映射为同码位 Unicode 字符（无损，1 字节 → 1 字符）。

- 与现有 Swift 行为（`String(data:encoding:.utf8) ?? String(data:encoding:.isoLatin1)`）兼容，并增加 UTF-16 BOM 支持。
- 解码后正文以 UTF-8 写入 `documents.body`。整个解码过程**不 panic**：任何解码失败都走兜底分支。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/src/core/content_index.rs` | 白名单常量、大小上限常量、二进制嗅探、编码探测函数。 |
| `rust-core/src/core/content_index.rs` | 单测：白名单命中/排除、4MB 边界、NUL 二进制跳过、三种编码解码。 |

---

## 4. 决策点 4 — 文件身份（增量失效键）

### 唯一结论

**文件身份 = `(path, mtime, size)` 三元组**，作为增量失效的唯一判断键。不引入内容哈希。

### 判断规则（确定性，T6 照做）

`documents` 表中已存在某 `path` 时：

| 磁盘 `mtime` 与 `size` | 结论 |
|---|---|
| 与表中**完全一致** | 文档是最新的，**跳过**（不读取、不重索引）。 |
| 任一不同 | 文档过期，**重索引**（先删后插，见 §2.3）。 |
| 表中存在但磁盘文件**不存在** | 文档被删除，**从索引删除**。 |
| 表中不存在但磁盘存在 | 新文档，**索引**。 |

- **mtime 单位**：UNIX 秒（`i64`），与 `FileEntrySkeleton.modified`、`SearchResult.modified` 一致。
- **不引入哈希**：`(mtime, size)` 对 4MB 以下文本文件足够精确且零读取开销；
  内容变化的文件 mtime/size 必变，最坏情况（mtime+size 碰巧一致但内容变）可接受且不构成数据错误。

---

## 5. 决策点 5 — 增量失效（FSEvents 事件驱动）

### 唯一结论

**复用现有 FSEvents 单 watcher，Swift 转发变更路径到内容索引**；内容索引**不启动自己的** FSEvents 流。
**FSEvents 不可用时退化整库重建。**

### 5.1 为什么不在 Rust 侧再启一个 watcher

`fsevents.rs` 的 watcher 是**进程全局单例**（`FSEVENTS_STATE: Mutex<Option<FSEventsState>>`），
同一时刻只有一个 watcher。应用已在 `MainWindowController.startFileSystemWatcher()`（第 1320–1332 行）
用它对 `NSHomeDirectory()` 启用了 watcher，回调 `handleFileSystemChange`（第 1335–1354 行）
已收到所有变更路径并做目录缓存失效。再启一个 watcher 会 `stop_internal()` 覆盖前一个，破坏现有功能。

### 5.2 事件流（定稿）

```
FSEvents 回调（已有，Swift 侧）
  └─ handleFileSystemChange(changedPath)          // MainWindowController.swift:1335
       ├─ 现有：invalidateCache(changedPath) + 面板刷新（不动）
       └─ 新增：ContentIndexBridge.shared.markDirty(changedPath)
            └─ ff_content_index_mark_dirty(path)  // §8.2，Rust 侧
                 └─ 加入进程内 dirty 集合 Mutex<HashSet<String>>
                      └─ 下次 ff_content_index_start(mode=0) 时增量处理（§5.3）
```

- `ff_content_index_mark_dirty(path)` 只把路径加入内存 dirty 集合，**不立即读文件、不立即写 DB**（O(1)）。
- dirty 集合由 T6 维护：`Mutex<HashSet<String>>`，进程内状态；索引重建时清空。

### 5.3 增量处理语义

`ff_content_index_start(root, mode=0)` 在以下条件满足时处理 dirty 集合：

- 状态为 `ready` 或 `empty`，且 dirty 集合非空；
- 对每个 dirty 路径按 §4 判断规则处理（存在且过期 → 重索引；不存在 → 删除；未变 → 跳过）。
- **注意**：dirty 路径只精确处理该路径；FSEvents 给出的父目录/祖先路径不做递归展开（避免放大），
  父目录内的其他文件靠下一次完整 walk 兜底（见 §5.4）。

### 5.4 无 FSEvents 时的退化（唯一策略）

- **触发条件**：`fsevents_status()` 非 `Active`（watcher 启动失败 / 非 macOS 平台），
  或 Swift 侧从未调用 `markDirty`（watcher 未启动）。
- **策略**：内容索引**不做任何事件依赖**。每次 `ff_content_index_start(mode=0)` 时，
  若 dirty 集合为空但上次构建不完整，或 Rust 侧记录到 watcher 不可用，则**退化整库重建**
  （即按 mode=1 的完整 walk 流程，见 §7.2）。该重建在后台线程执行，不阻塞 UI。
- 该退化是幂等的：重建完成即 ready，不产生不一致状态。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift` | `handleFileSystemChange` 增加一行转发 `markDirty`。 |
| `rust-core/src/core/content_index.rs` | `mark_dirty` + dirty 集合 + 增量处理 + 退化策略。 |

---

## 6. 决策点 6 — 状态机

### 唯一结论

状态机共 **6 个状态**（5 个核心状态 + 1 个 FTS5 不可用终态）。

```
状态常量（FFI 导出，c_int）：
  FF_CONTENT_INDEX_STATUS_EMPTY        = 0   -- 空：无索引数据（首启 / 重建前 / 清空后）
  FF_CONTENT_INDEX_STATUS_INDEXING     = 1   -- 构建中（含暂停中，paused 通过 stats 区分）
  FF_CONTENT_INDEX_STATUS_READY        = 2   -- 就绪：可查询
  FF_CONTENT_INDEX_STATUS_ERROR        = 3   -- 错误：构建/初始化失败（DB 损坏、权限、FTS5 缺失前的通用错误）
  FF_CONTENT_INDEX_STATUS_CANCELLED    = 4   -- 已取消：构建被用户取消，checkpoint 保留
  FF_CONTENT_INDEX_STATUS_UNAVAILABLE  = 5   -- 不可用（终态）：FTS5 未编译入 SQLite
```

### 6.1 合法转移表（T6 必须只实现这些转移）

```
empty        ──ff_content_index_start──▶ indexing
indexing     ──构建成功────────────────▶ ready
indexing     ──ff_content_index_cancel─▶ cancelled
indexing     ──构建失败────────────────▶ error
cancelled    ──ff_content_index_start──▶ indexing   （从 checkpoint 恢复）
error        ──ff_content_index_start──▶ indexing   （重试；若损坏先按 §9.3 重建 DB）
ready        ──ff_content_index_start(mode=1)──▶ indexing   （显式重建）
ready        ──ff_content_index_start(mode=0)──▶ indexing   （增量更新；处理 dirty 集合后回 ready）
empty        ──init 失败───────────────▶ error
*            ──init 检测到无 FTS5──────▶ unavailable（终态，唯一进入途径）
```

- `unavailable` 是**终态**：不接受任何 start/cancel/pause/resume；仅 `ff_content_index_status` 与 `stats` 可调用。
- `paused` 不是独立状态：暂停时状态仍为 `indexing`，`ff_content_index_stats()` 的 JSON 中
  `"paused": true` 区分（见 §7.3）。

### 6.2 UI 呈现（T7 实现，逐状态唯一映射）

| 状态 | 搜索面板呈现（SearchPanelController） | "内容包含"复选框 |
|---|---|---|
| `empty` | 状态行："内容索引尚未构建"，显示"构建索引"按钮 | 禁用 |
| `indexing` | 状态行："正在构建内容索引…"，进度条（来自 stats）+ "取消"按钮；`paused=true` 时按钮变"继续" | 禁用 |
| `ready` | 状态行："内容索引就绪（N 个文件）"+ "重建"按钮 | **启用** |
| `error` | 状态行：错误描述 + "重试"按钮 | 禁用 |
| `cancelled` | 状态行："内容索引构建已取消"+ "继续构建"按钮 | 禁用 |
| `unavailable` | 状态行："内容搜索不可用"（无操作按钮） | 禁用（永久） |

### 6.3 重建/暂停/恢复语义（唯一结论）

- **重建**：`ff_content_index_start(root, mode=1)`。完整重建，走临时文件 + 原子替换（§10.3）。
- **暂停**：`ff_content_index_pause(handle)`。协作式：构建循环在**批边界**检查 pause 标志后停止读取新文件，
  已读批次已提交；状态仍为 `indexing`，`stats().paused=true`。暂停后 DB 处于一致状态，可安全查询（返回空或部分结果由 UI 在 indexing 状态下忽略）。
- **恢复**：`ff_content_index_resume(handle)`。清除 pause 标志，构建循环从 checkpoint 继续（不重读已完成文件）。
- **取消**：`ff_content_index_cancel(handle)`。协作式：构建循环在批边界停止，提交当前批次 + checkpoint，
  状态 → `cancelled`。取消**不是**暂停：取消后构建不再继续，须由用户再次 `start` 才恢复。
- 暂停/取消/恢复均只作用于**当前活跃构建**的 handle，不影响其他操作（沿用 §8.1 的 handle 隔离模式）。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/src/core/content_index.rs` | 状态机实现 + 转移表。 |
| `rust-core/src/ffi/mod.rs` | 状态常量导出（`FF_CONTENT_INDEX_STATUS_*`）。 |
| `FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift` | 状态行 UI + 复选框启用/禁用逻辑。 |

---

## 7. 决策点 7 — 取消/恢复（checkpoint）

### 唯一结论

**构建可中断（`Arc<AtomicBool>` cancel 标志），中断后从路径游标 checkpoint 恢复，不重复全文。**

### 7.1 取消机制

- 复用 `ffi/mod.rs` 现有的 per-operation 取消注册表模式（`OpGuard` / `ACTIVE_OPS` / `AtomicU64` handle）：
  每次 `ff_content_index_start` 注册一个 `OpKind::Index`（新增枚举值）并返回 handle；
  `ff_content_index_cancel(handle)` / `ff_content_index_pause(handle)` / `ff_content_index_resume(handle)`
  通过 `cancel_op` 模式定位对应标志。
- 构建循环在**每处理一个文件之后**、**每个批次提交之前**检查 cancel / pause 标志（`Ordering::Relaxed`）。

### 7.2 checkpoint 机制（唯一结论：路径游标，非分卷）

- 遍历顺序：`walkdir` 得到的文件路径**按字典序排序**后顺序处理，保证游标单调。
- `meta` 表维护 `checkpoint_path`：每提交一批（500 个文档，§10.1），在**同一事务**内更新
  `checkpoint_path = 该批最后一个文件路径`。
- **恢复**：`ff_content_index_start(root, mode=0)` 且状态为 `cancelled` 时，
  跳过所有 `path <= checkpoint_path` 的已排序文件（它们要么已索引、要么被跳过），从游标继续。
- **不重复全文**：游标之前的文件已写入 `documents` + FTS（事务已提交），恢复时不再读取其内容；
  §4 身份判断进一步保证已索引且未变的文件不重读。

### 7.3 进度暴露

`ff_content_index_stats()` 返回 JSON（`ff_free_string` 释放）：
```json
{
  "status": 1,
  "paused": false,
  "document_count": 1234,
  "total_candidates": 90000,
  "processed": 5678,
  "checkpoint_path": "/Users/x/docs/z.md",
  "last_build_at": 1755120000,
  "root_path": "/Users/x"
}
```

- `processed` = 已完成文件数（游标推进计数）；`total_candidates` = 预估候选文件数（walk 探测，可为 0 = 未知）。
- 该 JSON 是 UI 进度条与 `paused` 显示的唯一数据来源。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/src/core/content_index.rs` | cancel/pause 标志、checkpoint 读写、排序遍历。 |
| `rust-core/src/ffi/mod.rs` | `OpKind::Index`、`ff_content_index_cancel/pause/resume`。 |

---

## 8. 决策点 8 — FFI 契约

### 唯一结论

新增 9 个导出函数（命名 `ff_content_index_*`），字符串所有权规则**沿用 `ff_free_string` 模式**。

### 8.1 错误码与状态常量

- 错误码复用现有 `ff_error_t`：`FF_OK=0`、`FF_ERR_GENERIC=-1`、`FF_ERR_INVALID_PATH=-2`、
  `FF_ERR_IO=-3`、`FF_ERR_NOT_FOUND=-4`。**不新增错误码。**
- 新增状态常量（见 §6）：
  ```c
  #define FF_CONTENT_INDEX_STATUS_EMPTY        0
  #define FF_CONTENT_INDEX_STATUS_INDEXING     1
  #define FF_CONTENT_INDEX_STATUS_READY        2
  #define FF_CONTENT_INDEX_STATUS_ERROR        3
  #define FF_CONTENT_INDEX_STATUS_CANCELLED    4
  #define FF_CONTENT_INDEX_STATUS_UNAVAILABLE  5
  ```
- 模式常量：`FF_CONTENT_INDEX_MODE_INCREMENTAL = 0`、`FF_CONTENT_INDEX_MODE_REBUILD = 1`。

### 8.2 函数清单与签名草案（定稿）

```c
/* 初始化：打开/创建 content_index.sqlite，建 schema，检测 FTS5，设置状态。
   db_path 由 Swift 解析（§1）。可重复调用（幂等，CREATE TABLE IF NOT EXISTS；
   OnceLock 语义：首次设置的路径进程内生效）。FTS5 缺失 → unavailable。 */
ff_error_t ff_content_index_init(const char *db_path);

/* 查询状态机（§6），返回 FF_CONTENT_INDEX_STATUS_* 之一。 */
int ff_content_index_status(void);

/* 启动构建。root_path = 要索引的根目录；mode = INCREMENTAL(0) | REBUILD(1)；
   out_handle 写入本次构建的取消句柄（NULL 可忽略，模式同 ff_scan_duplicates_ex）。
   INCREMENTAL：取消后从 checkpoint 恢复 / 有 dirty 则增量 / 空则全量 walk（§5.4）。 */
ff_error_t ff_content_index_start(const char *root_path, int mode, uint64_t *out_handle);

/* 取消指定构建。FF_OK / FF_ERR_NOT_FOUND（无匹配 handle）。 */
ff_error_t ff_content_index_cancel(uint64_t handle);

/* 暂停指定构建（协作式，批边界生效）。FF_OK / FF_ERR_NOT_FOUND。 */
ff_error_t ff_content_index_pause(uint64_t handle);

/* 恢复指定构建。FF_OK / FF_ERR_NOT_FOUND。 */
ff_error_t ff_content_index_resume(uint64_t handle);

/* 标记路径待更新（§5.2，Swift 转发 FSEvents）。O(1)，不读文件。 */
ff_error_t ff_content_index_mark_dirty(const char *path);

/* 内容查询。query = FTS5 MATCH 表达式（§8.4 转义由 Swift 做）；
   max_results = 结果上限（>0）；命中经 FFSearchCallback 逐个回调；
   状态非 READY 时返回 FF_ERR_NOT_FOUND（last_error="content index not ready"）。 */
ff_error_t ff_content_index_query(const char *query, size_t max_results,
                                  FFSearchCallback callback, void *user_data);

/* 返回 stats JSON（§7.3）。调用方必须 ff_free_string 释放。 */
char *ff_content_index_stats(void);
```

### 8.3 借用 vs 所有权字符串规则（唯一结论，沿用现有模式）

| 方向 | 规则 |
|---|---|
| **入参字符串**（`db_path`/`root_path`/`path`/`query`） | **借用**：NUL 结尾 UTF-8，仅调用期间有效。Rust 侧在入口立即 `CStr::from_ptr(...).to_string_lossy()` 拷贝为自有 `String`（与 `ffi/mod.rs` 全部现有函数一致）。 |
| **出参字符串** | **所有权转移给调用方**：仅 `ff_content_index_stats()` 返回 `*mut c_char`，由 Rust `CString::into_raw` 分配，**必须**用 `ff_free_string` 释放（与 `ff_last_error`/`ff_version_string` 一致）。 |
| **回调内字符串**（`FFSearchResult.path`/`name`） | **借用，仅回调期间有效**：Rust 用 RAII `CString` 保持所有权，回调返回后自动释放（与 `ff_search` 回调一致，`ffi/mod.rs` 第 1115–1128 行模式）。调用方不得 retain 指针。 |
| **输出 handle**（`out_handle`） | 调用方分配 `u64`，Rust 在构建开始前写入（与 `ff_scan_duplicates_ex`/`ff_search_ex` 一致）。 |

- **回调不得跨线程持有 userData 指针**：Swift 侧 `ContentIndexBridge` 用
  `Unmanaged.passRetained`/`takeUnretainedValue` + `DispatchQueue.main.async` 模式（与 `SearchBridge.swift` 完全一致）。

### 8.4 查询字符串转义（唯一结论，Swift 侧实现）

- Swift 把用户输入的纯文本包成 FTS5 **phrase 查询**：`"..."`（双引号包裹），内部双引号翻倍（`""`）。
  例：用户输入 `hello world` → MATCH 表达式 `"hello world"`；用户输入 `say "hi"` → `"say ""hi"""`。
- 这样：FTS5 不把空格/引号/`AND`/`OR`/`NEAR` 当语法处理，避免注入和解析错误，实现子串式包含匹配。
- Rust 侧 `ff_content_index_query` **原样接收**该 MATCH 表达式，不二次转义。

### 8.5 与 `ff_ffi.h` 的同步要求（强制）

新增的 9 个函数、状态常量、模式常量**必须**同步进三处，缺一不可：

| 文件 | 必须添加 |
|---|---|
| `rust-core/include/ff_ffi.h` | 9 个函数原型 + 6 个状态 `#define` + 2 个模式 `#define`（加在 FSEvents 段之后）。 |
| `FlowFinderNative/FlowFinderNative/Bridge/FFIFunctions.swift` | 9 个 `@_silgen_name` 声明 + `ContentIndexStatus`/`ContentIndexMode` Swift enum。 |
| `FlowFinderNative/FlowFinderNative/Bridge/ContentIndexBridge.swift`（新建） | `ContentIndexBridge` 类：`init/status/start/cancel/pause/resume/markDirty/query/stats`，`ffiQueue` + handle 管理 + `passRetained` 回调上下文（模式复制 `SearchBridge.swift`）。 |

- T6 只做 Rust 侧（`content_index.rs` + `ffi/mod.rs`），但**签名在 T6 提交时必须与本节逐字符一致**，供 T7 直接接线。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/include/ff_ffi.h` | 声明新增（§8.5）。 |
| `FlowFinderNative/FlowFinderNative/Bridge/FFIFunctions.swift` | 声明新增（§8.5）。 |
| `FlowFinderNative/FlowFinderNative/Bridge/ContentIndexBridge.swift` | 新建 Swift 封装。 |
| `FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift` | 删除 `fileContainsText`（707–715），`applyFiltersAndReload` 改为索引查询 + 集合成员过滤（§11）。 |

---

## 9. 决策点 9 — 迁移/降级

### 唯一结论

**`PRAGMA user_version` 版本号 + 只增不删的平滑迁移；损坏 → 备份后重建；旧目录缓存 DB 完全不动；v0.7.4 不读新 DB。**

### 9.1 Schema 版本号

- `SCHEMA_VERSION = 1`（v0.7.5 首个版本），通过 `PRAGMA user_version` 持久化（与 `sqlite_cache.rs` 同机制，但行为相反——见 §9.2）。
- 版本语义：**只增不删**。v1 → v2 只允许 ADD 列 / 新增表，禁止 DROP/改名破坏 v1 数据。

### 9.2 版本不匹配处理（**绝不 drop**，与 `sqlite_cache.rs:121-130` 相反）

| 磁盘 `user_version` | 处理（唯一结论） |
|---|---|
| `0`（全新 DB） | 建 schema，`PRAGMA user_version = 1`。 |
| `< 1` 以外的值或 `== 1` | `CREATE TABLE IF NOT EXISTS` 幂等补齐；不 drop、不清空。 |
| `> 1`（未来版本写过的 DB，旧代码读到） | **完全不动**：跳过所有 schema 操作，保持原文件原版本原数据；查询照常（仅列子集可用，未知列不引用）。这是降级安全的基石。 |
| 无法读取 `user_version` | 按 §9.3 走损坏处理。 |

- **`ff_content_index_init` 绝不对 `documents`/`content_fts`/`meta` 执行任何 `DROP`/`DELETE`/`TRUNCATE`。**
  "清空重建"唯一途径是 §10.3 的临时文件 + 原子替换（新文件，不影响旧文件）。

### 9.3 DB 损坏处理（唯一结论）

- **检测**：打开失败（`SQLITE_CORRUPT` / `SQLITE_NOTADB`）、`PRAGMA integrity_check` 非 `ok`、或 `user_version` 读取失败。
- **处理**：
  1. 将损坏文件**重命名备份**为 `content_index.sqlite.corrupt-<UTC时间戳>`（不删除）；
  2. 用同一路径创建全新 DB（§2.2 schema）并 `PRAGMA user_version = 1`；
  3. 状态 → `empty`，等待 `start` 全量重建（文档丢失由重建恢复，**可接受**：这是文件系统快照，原始文件未受损）。
- **绝不**触碰 `dir_cache.db`。

### 9.4 旧目录缓存 DB 完全不动

- 内容索引模块**从不打开、从不写、从不读** `dir_cache.db`；`sqlite_cache.rs` 的连接池（`POOL`）与
  内容索引的专用连接是两套完全独立的连接。
- 目录缓存 schema 版本升级（`sqlite_cache::SCHEMA_VERSION` 变化）**不影响**内容索引，反之亦然。

### 9.5 v0.7.4 降级到 v0.7.5 的兼容性（唯一结论）

- v0.7.4 代码中**不存在任何对 `content_index.sqlite` 的引用**（文件名只在 v0.7.5 新增代码中出现）。
- v0.7.4 启动时只打开 `dir_cache.db`，`content_index.sqlite` 作为一个不被引用的文件安静地留在 Application Support，
  不影响 v0.7.4 的任何行为（不报错、不读取、不删除）。
- v0.7.5 升级回 v0.7.4 后，旧版本对 v0.7.5 写的新 DB 完全无感知 → **旧版本不读新 DB**（无需任何兼容代码）。
- v0.7.4 → v0.7.5 再升级时，`content_index.sqlite` 仍存在且 `user_version == 1`，`init` 幂等通过，索引保留。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/src/core/content_index.rs` | 版本处理、损坏检测/备份/重建。 |
| `rust-core/src/core/content_index.rs` | 单测：版本不匹配不 drop、损坏备份、v1 幂等重入。 |

---

## 10. 决策点 10 — 事务与原子性

### 唯一结论

**批量写入单事务（每批 500 文档）；完整重建走临时文件 + 原子 rename；增量更新在线上库单事务。**

### 10.1 批量写入（单事务）

- 构建循环每累计 **500 个文档**为一个批次，批次内所有 `documents`/`content_fts` 写入 + `checkpoint_path` 更新
  在**同一个 SQLite 事务**中提交（`conn.transaction()` + `tx.commit()`）。
- 事务失败（含取消前的最后一个不完整批次）→ **整批回滚**，不残留半批数据；checkpoint 停留在上一已提交批次，
  恢复时从那里继续，保证 checkpoint 与数据永远一致。
- 最后不足 500 的尾批也在结束时以单事务提交。

### 10.2 线上库的 WAL 配置

- `content_index.sqlite` 使用 `PRAGMA journal_mode=WAL` + `busy_timeout=5000`（与 `sqlite_cache.rs` 的
  `open_configured_connection` 完全一致），保证崩溃安全与并发读不阻塞。

### 10.3 完整重建（临时文件 + 原子替换，唯一策略）

- `ff_content_index_start(root, mode=1)`（以及 §5.4 的退化全量重建）：
  1. 在**同一目录**创建临时库 `content_index.sqlite.tmp-<pid>`（同目录保证 `rename` 原子且同卷）；
  2. 对临时库建 schema + 全量索引（批量事务，支持 cancel/pause/checkpoint 写入临时库的 `meta`）；
  3. 构建成功后：**关闭线上连接 → `rename(content_index.sqlite.tmp-<pid>, content_index.sqlite)`（原子替换）→ 重开连接**；
  4. 构建失败/取消：删除临时文件，线上库保持旧版本不变（用户可继续用旧索引查询）。
- 若同目录存在未清理的 `content_index.sqlite.tmp-*`（上次崩溃遗留），`init` 时**删除全部**（这是唯一允许的删除，仅限临时文件）。

### 10.4 增量更新的原子性

- 增量处理（dirty 集合 / checkpoint 恢复）在**线上库**执行，每个文件或每个小批（≤500）一个事务；
  每事务提交即对其他查询可见（WAL 快照隔离），不存在"半更新"窗口。

### 需要同步的文件

| 文件 | 改动 |
|---|---|
| `rust-core/src/core/content_index.rs` | 批次提交、WAL、临时文件 + rename、临时文件清理。 |
| `rust-core/src/core/content_index.rs` | 单测：中断批次回滚、重建后旧查询不可见、临时文件清理。 |

---

## 11. 涉及 Rust/Swift 边界需同步的文件总清单（T6/T7）

| 文件 | 位置 | 改动 | 阶段 |
|---|---|---|---|
| `rust-core/Cargo.toml` | — | **无需改动**（bundled 已含 FTS5，§2.5 已验证）。 | T6 |
| `rust-core/src/core/mod.rs` | 模块注册 | 新增 `pub mod content_index;` | T6 |
| `rust-core/src/core/content_index.rs` | **新建** | schema、FTS 同步、编码、身份、状态机、checkpoint、事务、临时文件替换、dirty 集合。 | T6 |
| `rust-core/src/ffi/mod.rs` | 导出层 | 9 个 `ff_content_index_*` 函数 + 状态/模式常量 + `OpKind::Index`。 | T6 |
| `rust-core/include/ff_ffi.h` | C 头文件 | 9 个函数原型 + 常量（§8.5）。 | T6/T7 |
| `FlowFinderNative/FlowFinderNative/Bridge/FFIFunctions.swift` | Swift FFI | 9 个 `@_silgen_name` 声明 + enum（§8.5）。 | T7 |
| `FlowFinderNative/FlowFinderNative/Bridge/ContentIndexBridge.swift` | **新建** | `ContentIndexBridge` 封装（SearchBridge 模式）。 | T7 |
| `FlowFinderNative/FlowFinderNative/App/AppDelegate.swift` | 启动 | `initContentIndex()`（路径解析 + `ff_content_index_init`）。 | T7 |
| `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift` | FSEvents | `handleFileSystemChange` 转发 `markDirty`（§5.2）。 | T7 |
| `FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift` | 搜索面板 | 删除 `fileContainsText`；`applyFiltersAndReload` 改为索引查询 + `Set<path>` 成员过滤；状态行 UI + 复选框启用逻辑。 | T7 |

### 11.1 SearchPanelController 内容过滤改造（唯一结论）

`applyFiltersAndReload` 中"内容包含"分支（第 690–694 行）改为：

1. 在 `ffiQueue` 上调用 `ff_content_index_query(转义后的查询, 500, ...)` **一次**，收集匹配路径 `Set<String>`；
2. `filteredResults = results.filter { 其它筛选 && contentMatches.contains(result.path) }`（集合成员判断，O(1)）；
3. 状态非 `READY` 时：查询返回 `FF_ERR_NOT_FOUND`，UI 走 §6.2 状态呈现，**不**回退到逐文件读取（降级只允许"禁用"，不允许恢复主线程 `Data(contentsOf:)`）。

**不变量（验收红线）**：T7 完成后，内容匹配路径上**绝无** `Data(contentsOf:)` 调用。

---

## 12. T6 可执行验收清单

T6 完成后，以下场景必须有**确定性**结果（对应计划 todo 5 验收标准）：

| 场景 | 期望结果 |
|---|---|
| 全新索引 | `init` → 状态 `empty` → `start(mode=0)` → `ready`，可查询。 |
| 中断构建 | `start` 后 `cancel(handle)` → 状态 `cancelled`，checkpoint 已提交；再次 `start(mode=0)` 从 checkpoint 恢复，`document_count` 最终正确。 |
| 过期条目 | 修改文件 mtime/size 后 `mark_dirty(path)` + `start(mode=0)` → 该文档被重索引，查询反映新内容。 |
| 权限错误 | 构建遇到不可读文件 → 跳过并记录计数（不失败整体）；根目录不可读 → 状态 `error`。 |
| 降级/旧 DB | `dir_cache.db` 全程不被内容索引触碰；`user_version > 1` 的 DB 不被修改（§9.2）；损坏 DB → 备份 + 重建（§9.3）。 |
| 二进制/超限 | 4MB+ 文件与 NUL 文件不索引（§3）。 |
| FTS5 缺失 | 检测到无 FTS5 → 状态 `unavailable`（T6 用测试注入模拟，不依赖真机）。 |

证据：T6 在 `.omo/evidence/flowfinder-v074-complete-fix/task-6/cargo-test.log` 记录
`cargo test --all-features` 全绿结果（含本契约 §3/§9/§10 引用的全部单测）。
