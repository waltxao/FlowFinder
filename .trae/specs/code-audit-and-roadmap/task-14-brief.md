# Task 14 Brief — AI 标签生成

## 目标

实现基于规则的文件标签自动分类引擎。Rust Core 根据文件扩展名、文件名模式、文件大小等特征自动生成分类标签，通过 FFI 暴露给 Swift，UI 层提供右键菜单「AI 自动打标签」入口，将生成的标签写入 xattr（`com.flowfinder.tags`）。

## 范围

- **包含**：Rust 规则分类引擎、FFI `ff_generate_tags` 函数、Swift CoreBridge 方法、FileListView/FileGridView 右键菜单、批量打标签（多选文件）
- **不包含**：SQLite virtual_tags 表持久化、FFEntryRef 扩展（避免改 3 处）、macOS 原生 Finder 标签同步、ML/真正 AI 模型

## 架构

```
用户右键「AI 自动打标签」
  ↓
FileListView/FileGridView (选中文件 paths)
  ↓ NotificationCenter
MainWindowController.handleAITagging
  ↓ DispatchQueue.global
CoreBridge.generateAITags(path) → [GeneratedTag]
  ↓ ffiQueue + semaphore
ff_generate_tags(path) → *mut c_char (JSON)
  ↓
Rust tags::generate_tags(path) → Vec<GeneratedTag>
  规则引擎：extension → category, size → 大文件, is_dir → 文件夹
  ↓ JSON 序列化
返回 JSON 字符串
  ↓ Swift 解码
TagBridge.addTag(tag, path) → xattr 写入
```

## 分类规则

| 标签名 | 颜色 | 匹配规则 |
|--------|------|----------|
| 图片 | #FF6B35 | jpg/jpeg/png/gif/heic/tiff/bmp/webp/raw/cr2/nef/arw/svg/ico |
| 视频 | #FF3B30 | mp4/mov/avi/mkv/m4v/wmv/flv/webm |
| 音频 | #AF52DE | mp3/wav/flac/aac/m4a/ogg/wma/aiff |
| 文档 | #007AFF | pdf/doc/docx/txt/rtf/pages/odt/md |
| 表格 | #34C759 | xls/xlsx/csv/numbers/ods |
| 演示 | #FF9500 | ppt/pptx/key/odp |
| 代码 | #5856D6 | swift/rs/py/js/ts/go/java/c/cpp/h/rb/php/sh |
| 归档 | #8E8E93 | zip/rar/7z/tar/gz/bz2/xz/dmg/iso |
| 大文件 | #FF3B30 | size > 100MB |
| 文件夹 | #007AFF | is_dir |

一个文件可匹配多个标签（如 `video.mp4` 大于 100MB → [视频, 大文件]）。

## 实现步骤

### 1. Rust: `rust-core/src/core/tags.rs`（新建）

```rust
pub struct GeneratedTag {
    pub name: String,
    pub color: String,
    pub category: String,
}

pub fn generate_tags(path: &str) -> Vec<GeneratedTag>;
```

- 读取 `std::fs::metadata(path)` 获取 is_dir / size
- 从路径提取扩展名（小写化）
- 逐一匹配分类规则，收集匹配的标签
- 单元测试：覆盖图片/视频/大文件/文件夹/未知类型

### 2. Rust: `rust-core/src/core/mod.rs`（修改）

追加 `pub mod tags;`

### 3. Rust: `rust-core/src/ffi/mod.rs`（修改）

```rust
#[no_mangle]
pub extern "C" fn ff_generate_tags(path: *const c_char) -> *mut c_char;
```

- null 检查 → 返回 null_mut + set_last_error
- 调用 `tags::generate_tags` → 序列化为 JSON 数组
- 返回 `rust_string_to_c(json)`
- 错误时返回 null_mut + set_last_error

### 4. Rust: `rust-core/include/ff_ffi.h`（修改）

```c
char *ff_generate_tags(const char *path);
```

### 5. Swift: `FFIFunctions.swift`（修改）

```swift
@_silgen_name("ff_generate_tags")
public func ff_generate_tags(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
```

### 6. Swift: `CoreBridge.swift`（修改）

```swift
func generateAITags(path: String) throws -> [GeneratedTag]
```

- ffiQueue + semaphore 模式
- 调用 ff_generate_tags → String → JSONDecoder → [GeneratedTag]

### 7. Swift: 新增 `GeneratedTag` 结构体（在 CoreBridge.swift 或 Tag.swift 中）

```swift
public struct GeneratedTag: Codable {
    public let name: String
    public let color: String
    public let category: String
}
```

### 8. Swift: `FileListView.swift` + `FileGridView.swift`（修改）

在「添加到收藏夹」后添加：
```swift
menu.addItem(.separator())
menu.addItem(withTitle: "AI 自动打标签", action: #selector(generateAITags(_:)), keyEquivalent: "")
```

实现 `@objc private func generateAITags(_ sender: Any?)`：
- 获取 selectedFiles（支持多选）
- 后台线程遍历，调用 CoreBridge.generateAITags + TagBridge.addTag
- 主线程刷新 UI + 成功提示

### 9. Notification.Name 新增

```swift
static let fileListDidGenerateAITags = Notification.Name("fileListDidGenerateAITags")
```

## 验证

- `cargo check` 零错误
- `cargo test` 新增 tags 模块测试通过
- 选中 .jpg 文件 → 右键「AI 自动打标签」→ xattr 包含「图片」标签
- 多选文件 → 批量打标签
