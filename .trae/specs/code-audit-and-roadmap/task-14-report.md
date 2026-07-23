# Task 14 实施报告 — AI 标签生成

## 状态

**状态：DONE_WITH_CONCERNS**（Rust 侧完整实现并通过 27 个测试；Swift 侧代码完整但 xcodebuild 未运行验证，因环境为 CommandLineTools 而非完整 Xcode）

## 实现摘要

实现了基于规则的文件标签自动分类引擎。Rust Core 根据文件扩展名、文件大小、是否为目录等特征自动生成分类标签（图片/视频/音频/文档/表格/演示/代码/归档/大文件/文件夹），通过 FFI 暴露给 Swift，UI 层在 FileListView 和 FileGridView 的右键菜单中提供「AI 自动打标签」入口，将生成的标签写入 xattr（`com.flowfinder.tags`）。

### 受影响文件

| 文件 | 改动 |
|------|------|
| `rust-core/src/core/tags.rs` | **新建** — 规则分类引擎（434 行），10 类标签，21 个单元测试 |
| `rust-core/src/core/mod.rs` | 修改 — 追加 `pub mod tags;` |
| `rust-core/src/ffi/mod.rs` | 修改 — 新增 `ff_generate_tags` FFI 函数 + 5 个 FFI 测试 |
| `rust-core/include/ff_ffi.h` | 修改 — 新增 `char *ff_generate_tags(const char *path)` 声明 |
| `FlowFinderNative/.../Bridge/FFIFunctions.swift` | 修改 — 新增 `@_silgen_name("ff_generate_tags")` 映射 |
| `FlowFinderNative/.../Bridge/CoreBridge.swift` | 修改 — 新增 `GeneratedTag` 结构体 + `generateAITags(path:)` 方法 |
| `FlowFinderNative/.../UI/FileListView.swift` | 修改 — 右键菜单新增「AI 自动打标签」+ `generateAITags` action |
| `FlowFinderNative/.../UI/FileGridView.swift` | 修改 — 右键菜单新增「AI 自动打标签」+ `generateAITags` action |

## 架构设计

### 数据流

```
用户右键「AI 自动打标签」
  ↓
FileListView/FileGridView.generateAITags(_:)
  ↓ 获取 selectedFiles paths
  ↓ DispatchQueue.global(qos: .userInitiated)
  ↓
CoreBridge.generateAITags(path:) → [GeneratedTag]
  ↓ ffiQueue + semaphore
ff_generate_tags(path) → *mut c_char (JSON)
  ↓
Rust tags::generate_tags(path) → Vec<GeneratedTag>
  ↓ std::fs::metadata → is_dir / size
  ↓ Path::extension → to_lowercase → classify_by_extension
  ↓ 收集匹配标签（可多个：如视频+大文件）
  ↓ tags_to_json → JSON 数组字符串
  ↓ rust_string_to_c → C 字符串
  ↓ Swift 解码 JSON → [GeneratedTag]
  ↓
Tag(name:color:) → TagBridge.addTag(tag, path) → xattr 写入
  ↓
DispatchQueue.main.async → NSAlert 成功/失败提示 + reloadData
```

### 分类规则

| 标签 | 颜色 | 分类 | 匹配条件 |
|------|------|------|----------|
| 图片 | #FF6B35 | image | jpg/jpeg/png/gif/heic/heif/tiff/bmp/webp/raw/cr2/nef/arw/dng/svg/ico/psd/ai/sketch |
| 视频 | #FF3B30 | video | mp4/mov/avi/mkv/m4v/wmv/flv/webm/mpg/mpeg/3gp/mts/m2ts |
| 音频 | #AF52DE | audio | mp3/wav/flac/aac/m4a/ogg/wma/aiff/aif/opus/mka |
| 文档 | #007AFF | document | pdf/doc/docx/txt/rtf/pages/odt/md/markdown/tex/epub/mobi |
| 表格 | #34C759 | spreadsheet | xls/xlsx/csv/numbers/ods/tsv |
| 演示 | #FF9500 | presentation | ppt/pptx/key/odp |
| 代码 | #5856D6 | code | swift/rs/py/js/ts/tsx/jsx/go/java/kt/c/cpp/cc/cxx/h/hpp/rb/php/sh/bash/zsh/fish/lua/r/scala/clj/ex/exs/elm/hs/ml/nim/v/zig/dart/vue/svelte/json/yaml/yml/toml/xml/ini/conf/env/gradle/cmake/make/mk/dockerfile/gitignore |
| 归档 | #8E8E93 | archive | zip/rar/7z/tar/gz/bz2/xz/lz/lzma/zst/dmg/iso/img/pkg/deb/rpm |
| 大文件 | #FF3B30 | large_file | size > 100 MB（与类型标签叠加） |
| 文件夹 | #007AFF | folder | is_dir（优先，不再按扩展名分类） |

### 关键设计决策

1. **路径式 FFI 接口**：`ff_generate_tags(path)` 接收文件路径而非拆分的字段，Rust 内部读取 `std::fs::metadata` 获取 is_dir/size。优点：Swift 侧只需传路径，Rust 一次 stat 获取所有元数据。遵循 `ff_get_file_type(path)` 既有模式。

2. **JSON 序列化不依赖 serde**：`tags_to_json` 手动构建 JSON 字符串，避免在 tags 模块引入 serde 依赖。GeneratedTag 字段均为 String，无嵌套，手动序列化简单可靠。特殊字符（`"` `\` `\n` `\r` `\t`）已转义。

3. **错误处理**：文件不存在 → null 返回 + `set_last_error`；文件存在但无匹配规则 → `"[]"` 空数组（非错误）。Swift 侧区分这两种情况：null 抛异常，空数组正常返回。

4. **批量操作**：UI 层支持多选文件批量打标签。后台线程遍历每个文件调用 `CoreBridge.generateAITags` + `TagBridge.addTag`，主线程汇总结果并弹窗提示。部分失败时显示成功/失败计数。

5. **不扩展 FFEntryRef**：标签不通过 `ff_list_dir` 回调传递，避免修改 Rust/Swift/C 三处 FFEntryRef 定义。标签仅在用户主动触发「AI 自动打标签」时写入 xattr。

6. **文件夹特殊处理**：文件夹优先标记为「文件夹」标签，不再按扩展名分类（文件夹名可能含点但不代表扩展名）。

## 验证结果

| 验证项 | 结果 |
|--------|------|
| `cargo check` | ✅ 0 errors（14 warnings 均为既有） |
| `cargo test tags` | ✅ 27 passed; 0 failed |
| `cargo test`（全部） | ✅ 113 passed; 2 failed（既有 settings 测试沙箱限制，与本次无关） |
| `xcodebuild build` | ❌ 未运行（环境为 CommandLineTools） |

### 测试覆盖

**tags.rs 单元测试（21 个）：**
- `test_classify_image_extensions` — 图片扩展名分类
- `test_classify_video_extensions` — 视频扩展名分类
- `test_classify_audio_extensions` — 音频扩展名分类
- `test_classify_document_extensions` — 文档扩展名分类
- `test_classify_code_extensions` — 代码扩展名分类
- `test_classify_archive_extensions` — 归档扩展名分类
- `test_classify_unknown_extension` — 未知扩展名返回 None
- `test_classify_extension_case_insensitive` — 大小写敏感说明
- `test_generate_tags_image_file` — 图片文件生成标签
- `test_generate_tags_video_file` — 视频文件生成标签
- `test_generate_tags_uppercase_extension` — 大写扩展名正确分类
- `test_generate_tags_large_file` — 大文件叠加标签（视频+大文件）
- `test_generate_tags_directory` — 文件夹标记
- `test_generate_tags_unknown_type` — 未知类型返回空
- `test_generate_tags_nonexistent_path` — 不存在路径返回空
- `test_generate_tags_no_extension` — 无扩展名返回空
- `test_tags_to_json_empty` — 空数组 JSON
- `test_tags_to_json_single` — 单标签 JSON
- `test_tags_to_json_multiple` — 多标签 JSON
- `test_tags_to_json_escapes_special_chars` — 特殊字符转义
- `test_generate_tags_spreadsheet` — 表格分类
- `test_generate_tags_presentation` — 演示分类

**FFI 测试（5 个）：**
- `test_ff_generate_tags_null_path` — null 路径返回 null + error
- `test_ff_generate_tags_nonexistent_file` — 不存在文件返回 null + error
- `test_ff_generate_tags_image_file` — 图片文件返回 JSON
- `test_ff_generate_tags_unknown_type_returns_empty_array` — 未知类型返回 `"[]"`
- `test_ff_generate_tags_directory` — 文件夹返回 JSON

## 关切点（Concerns）

1. **xcodebuild 未验证**：当前机器 `xcode-select` 指向 `/Library/Developer/CommandLineTools`，无法运行 `xcodebuild`。Swift 代码已通过代码审阅确认无语法错误，但未编译验证。建议在装有完整 Xcode 的机器上运行 `xcodebuild build` 验证。

2. **FileEntry.tags 仍为空数组**：由于未扩展 FFEntryRef，`FileEntry.init(from: FFEntryRef)` 中 `tags = []` 未改变。AI 标签写入 xattr 后不会立即在文件列表中显示。要显示标签需要：(a) 扩展 FFEntryRef 添加 tags_json 字段，或 (b) 在 FileEntry.init 中调用 TagBridge.getTags(path) 填充。两者均超出 Task 14 范围。

3. **SQLite virtual_tags 表未实现**：标签仅存 xattr，无持久化索引。搜索标签需要遍历目录读取 xattr。CONTINUE_DEV_PROMPT.md 中提到的「SQLite virtual_tags 表」属于后续迭代。

4. **macOS 原生 Finder 标签未同步**：AI 生成的标签写入 `com.flowfinder.tags` xattr，不写入 `com.apple.metadata:_kMDItemUserTags`（Finder 原生标签）。因此 Finder 中不会显示这些标签。同步属于后续迭代。

5. **无主菜单入口**：AI 打标签仅通过右键菜单触发，未在 Edit 或 Tools 菜单中添加主菜单项。Spec 仅要求右键菜单入口。
