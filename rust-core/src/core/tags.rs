//! AI 标签生成引擎 — 基于文件扩展名、文件名模式、文件大小的规则分类。
//!
//! 该模块提供「AI 自动打标签」功能的 Rust 核心实现。虽然名为「AI」，
//! 实际是基于预定义规则的分类引擎，根据文件的扩展名、大小、是否为目录
//! 等特征自动生成分类标签。
//!
//! ## 分类规则
//!
//! | 标签 | 颜色 | 匹配条件 |
//! |------|------|----------|
//! | 图片 | #FF6B35 | jpg/png/gif/heic/... |
//! | 视频 | #FF3B30 | mp4/mov/avi/... |
//! | 音频 | #AF52DE | mp3/wav/flac/... |
//! | 文档 | #007AFF | pdf/doc/txt/... |
//! | 表格 | #34C759 | xls/csv/numbers/... |
//! | 演示 | #FF9500 | ppt/key/... |
//! | 代码 | #5856D6 | swift/rs/py/... |
//! | 归档 | #8E8E93 | zip/rar/7z/... |
//! | 大文件 | #FF3B30 | size > 100 MB |
//! | 文件夹 | #007AFF | is_dir |

use std::path::Path;

/// AI 生成的标签（与 Swift 侧 GeneratedTag 结构体对应）。
///
/// 序列化为 JSON 时字段名为 `name` / `color` / `category`。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeneratedTag {
    /// 标签显示名称（如 "图片"、"视频"）。
    pub name: String,
    /// 标签颜色（hex 格式，如 "#FF6B35"）。
    pub color: String,
    /// 分类标识符（如 "image"、"video"）。
    pub category: String,
}

/// 大文件阈值：100 MB
const LARGE_FILE_THRESHOLD: u64 = 100 * 1024 * 1024;

/// 扩展名 → 分类映射表。
///
/// 返回 `(分类标识符, 标签名称, 颜色)` 元组，未匹配返回 `None`。
fn classify_by_extension(ext: &str) -> Option<(&'static str, &'static str, &'static str)> {
    // 使用静态匹配表，按字母序排列以便维护。
    // 颜色参考 macOS 系统色板。
    match ext {
        // 图片
        "jpg" | "jpeg" | "png" | "gif" | "heic" | "heif" | "tiff" | "tif" | "bmp"
        | "webp" | "raw" | "cr2" | "nef" | "arw" | "dng" | "svg" | "ico" | "psd"
        | "ai" | "sketch" => Some(("image", "图片", "#FF6B35")),

        // 视频
        "mp4" | "mov" | "avi" | "mkv" | "m4v" | "wmv" | "flv" | "webm" | "mpg"
        | "mpeg" | "3gp" | "mts" | "m2ts" => Some(("video", "视频", "#FF3B30")),

        // 音频
        "mp3" | "wav" | "flac" | "aac" | "m4a" | "ogg" | "wma" | "aiff" | "aif"
        | "opus" | "mka" => Some(("audio", "音频", "#AF52DE")),

        // 文档
        "pdf" | "doc" | "docx" | "txt" | "rtf" | "pages" | "odt" | "md" | "markdown"
        | "tex" | "epub" | "mobi" => Some(("document", "文档", "#007AFF")),

        // 表格
        "xls" | "xlsx" | "csv" | "numbers" | "ods" | "tsv" => {
            Some(("spreadsheet", "表格", "#34C759"))
        }

        // 演示文稿
        "ppt" | "pptx" | "key" | "odp" => Some(("presentation", "演示", "#FF9500")),

        // 代码 / 配置
        "swift" | "rs" | "py" | "js" | "ts" | "tsx" | "jsx" | "go" | "java" | "kt"
        | "c" | "cpp" | "cc" | "cxx" | "h" | "hpp" | "rb" | "php" | "sh" | "bash"
        | "zsh" | "fish" | "lua" | "r" | "scala" | "clj" | "ex" | "exs" | "elm"
        | "hs" | "ml" | "nim" | "v" | "zig" | "dart" | "vue" | "svelte"
        | "json" | "yaml" | "yml" | "toml" | "xml" | "ini" | "conf" | "env"
        | "gradle" | "cmake" | "make" | "mk" | "dockerfile" | "gitignore" => {
            Some(("code", "代码", "#5856D6"))
        }

        // 归档 / 磁盘映像
        "zip" | "rar" | "7z" | "tar" | "gz" | "bz2" | "xz" | "lz" | "lzma" | "zst"
        | "dmg" | "iso" | "img" | "pkg" | "deb" | "rpm" => {
            Some(("archive", "归档", "#8E8E93"))
        }

        _ => None,
    }
}

/// 从文件路径生成分类标签。
///
/// 读取文件元数据（是否为目录、大小），从路径提取扩展名，
/// 逐一匹配分类规则。一个文件可匹配多个标签。
///
/// # 参数
/// - `path` — 文件或目录的绝对路径。
///
/// # 返回
/// 匹配到的标签列表。若文件不存在或无法读取元数据，返回空 Vec。
///
/// # 示例
/// ```
/// use flowfinder_core::core::tags::generate_tags;
///
/// // 对一个图片文件生成标签
/// let tags = generate_tags("/tmp/photo.jpg");
/// assert!(tags.iter().any(|t| t.name == "图片"));
/// ```
pub fn generate_tags(path: &str) -> Vec<GeneratedTag> {
    let metadata = match std::fs::metadata(path) {
        Ok(m) => m,
        Err(_) => return Vec::new(),
    };

    let mut tags = Vec::new();

    // 文件夹优先标记
    if metadata.is_dir() {
        tags.push(GeneratedTag {
            name: "文件夹".to_string(),
            color: "#007AFF".to_string(),
            category: "folder".to_string(),
        });
        // 文件夹不再按扩展名分类（文件夹名可能含点但不代表扩展名）
        return tags;
    }

    // 按扩展名分类
    let ext = Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();

    if let Some((category, name, color)) = classify_by_extension(&ext) {
        tags.push(GeneratedTag {
            name: name.to_string(),
            color: color.to_string(),
            category: category.to_string(),
        });
    }

    // 大文件标记（与类型标签叠加）
    if metadata.len() > LARGE_FILE_THRESHOLD {
        tags.push(GeneratedTag {
            name: "大文件".to_string(),
            color: "#FF3B30".to_string(),
            category: "large_file".to_string(),
        });
    }

    tags
}

/// 将标签列表序列化为 JSON 数组字符串。
///
/// 格式：`[{"name":"图片","color":"#FF6B35","category":"image"},...]`
///
/// 序列化失败时返回 `"[]"`（理论上不会失败，因为字段均为 String）。
pub fn tags_to_json(tags: &[GeneratedTag]) -> String {
    // 手动构建 JSON 以避免引入 serde 依赖到该模块。
    // GeneratedTag 字段均为 String，无嵌套，手动序列化简单可靠。
    let items: Vec<String> = tags
        .iter()
        .map(|t| {
            format!(
                r#"{{"name":"{}","color":"{}","category":"{}"}}"#,
                escape_json_string(&t.name),
                escape_json_string(&t.color),
                escape_json_string(&t.category)
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

/// 转义 JSON 字符串中的特殊字符。
fn escape_json_string(s: &str) -> String {
    s.replace('\\', r"\\")
        .replace('"', r#"\""#)
        .replace('\n', r"\n")
        .replace('\r', r"\r")
        .replace('\t', r"\t")
}

// ── 单元测试 ─────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;

    /// 创建临时文件并返回路径。测试结束后由调用方负责清理。
    fn make_temp_file(name: &str, content: &[u8]) -> String {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("ff_test_tags_{}", name));
        let mut f = fs::File::create(&path).expect("create temp file");
        f.write_all(content).expect("write temp file");
        path.to_string_lossy().to_string()
    }

    fn cleanup(path: &str) {
        let _ = fs::remove_file(path);
    }

    #[test]
    fn test_classify_image_extensions() {
        for ext in &["jpg", "png", "gif", "heic", "tiff", "bmp", "webp", "svg"] {
            let result = classify_by_extension(ext);
            assert_eq!(result.map(|(c, _, _)| c), Some("image"));
        }
    }

    #[test]
    fn test_classify_video_extensions() {
        for ext in &["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv"] {
            let result = classify_by_extension(ext);
            assert_eq!(result.map(|(c, _, _)| c), Some("video"));
        }
    }

    #[test]
    fn test_classify_audio_extensions() {
        for ext in &["mp3", "wav", "flac", "aac", "m4a", "ogg", "aiff"] {
            let result = classify_by_extension(ext);
            assert_eq!(result.map(|(c, _, _)| c), Some("audio"));
        }
    }

    #[test]
    fn test_classify_document_extensions() {
        for ext in &["pdf", "doc", "docx", "txt", "rtf", "md", "pages"] {
            let result = classify_by_extension(ext);
            assert_eq!(result.map(|(c, _, _)| c), Some("document"));
        }
    }

    #[test]
    fn test_classify_code_extensions() {
        for ext in &["swift", "rs", "py", "js", "ts", "go", "java", "c", "cpp"] {
            let result = classify_by_extension(ext);
            assert_eq!(result.map(|(c, _, _)| c), Some("code"));
        }
    }

    #[test]
    fn test_classify_archive_extensions() {
        for ext in &["zip", "rar", "7z", "tar", "gz", "dmg", "iso"] {
            let result = classify_by_extension(ext);
            assert_eq!(result.map(|(c, _, _)| c), Some("archive"));
        }
    }

    #[test]
    fn test_classify_unknown_extension() {
        assert!(classify_by_extension("xyz123").is_none());
        assert!(classify_by_extension("").is_none());
    }

    #[test]
    fn test_classify_extension_case_insensitive() {
        // generate_tags 内部会 to_lowercase，但 classify_by_extension 本身区分大小写
        assert!(classify_by_extension("JPG").is_none());
        assert!(classify_by_extension("jpg").is_some());
    }

    #[test]
    fn test_generate_tags_image_file() {
        let path = make_temp_file("photo.jpg", b"fake image");
        let tags = generate_tags(&path);
        cleanup(&path);

        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].name, "图片");
        assert_eq!(tags[0].category, "image");
        assert_eq!(tags[0].color, "#FF6B35");
    }

    #[test]
    fn test_generate_tags_video_file() {
        let path = make_temp_file("video.mp4", b"fake video");
        let tags = generate_tags(&path);
        cleanup(&path);

        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].name, "视频");
        assert_eq!(tags[0].category, "video");
    }

    #[test]
    fn test_generate_tags_uppercase_extension() {
        // 扩展名大写也应正确分类（generate_tags 内部 to_lowercase）
        let path = make_temp_file("photo.JPG", b"fake");
        let tags = generate_tags(&path);
        cleanup(&path);

        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].category, "image");
    }

    #[test]
    fn test_generate_tags_large_file() {
        // 创建一个大于 100MB 的稀疏文件（不实际占用磁盘空间）
        let dir = std::env::temp_dir();
        let path = dir.join("ff_test_tags_large.mp4");
        let f = fs::File::create(&path).expect("create file");
        f.set_len(150 * 1024 * 1024).expect("set len");

        let tags = generate_tags(path.to_str().unwrap());
        let _ = fs::remove_file(&path);

        // 应同时有「视频」和「大文件」两个标签
        assert_eq!(tags.len(), 2);
        assert!(tags.iter().any(|t| t.category == "video"));
        assert!(tags.iter().any(|t| t.category == "large_file"));
    }

    #[test]
    fn test_generate_tags_directory() {
        let dir = std::env::temp_dir();
        let path = dir.join("ff_test_tags_dir");
        fs::create_dir_all(&path).expect("create dir");

        let tags = generate_tags(path.to_str().unwrap());
        let _ = fs::remove_dir_all(&path);

        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].name, "文件夹");
        assert_eq!(tags[0].category, "folder");
    }

    #[test]
    fn test_generate_tags_unknown_type() {
        let path = make_temp_file("data.xyz123", b"unknown");
        let tags = generate_tags(&path);
        cleanup(&path);

        // 未知扩展名 + 小文件 → 无标签
        assert!(tags.is_empty());
    }

    #[test]
    fn test_generate_tags_nonexistent_path() {
        let tags = generate_tags("/nonexistent/path/file.jpg");
        assert!(tags.is_empty());
    }

    #[test]
    fn test_generate_tags_no_extension() {
        let path = make_temp_file("Makefile", b"all: hello");
        let tags = generate_tags(&path);
        cleanup(&path);

        // 无扩展名 + 小文件 → 无标签
        assert!(tags.is_empty());
    }

    #[test]
    fn test_tags_to_json_empty() {
        let json = tags_to_json(&[]);
        assert_eq!(json, "[]");
    }

    #[test]
    fn test_tags_to_json_single() {
        let tags = vec![GeneratedTag {
            name: "图片".to_string(),
            color: "#FF6B35".to_string(),
            category: "image".to_string(),
        }];
        let json = tags_to_json(&tags);
        assert!(json.contains(r#""name":"图片""#));
        // 使用 r##"..."## 避免与颜色值中的 # 冲突
        assert!(json.contains(r##""color":"#FF6B35"##));
        assert!(json.contains(r#""category":"image""#));
        assert!(json.starts_with('['));
        assert!(json.ends_with(']'));
    }

    #[test]
    fn test_tags_to_json_multiple() {
        let tags = vec![
            GeneratedTag {
                name: "视频".to_string(),
                color: "#FF3B30".to_string(),
                category: "video".to_string(),
            },
            GeneratedTag {
                name: "大文件".to_string(),
                color: "#FF3B30".to_string(),
                category: "large_file".to_string(),
            },
        ];
        let json = tags_to_json(&tags);
        // 应包含两个对象
        assert_eq!(json.matches('{').count(), 2);
        assert_eq!(json.matches('}').count(), 2);
    }

    #[test]
    fn test_tags_to_json_escapes_special_chars() {
        let tags = vec![GeneratedTag {
            name: "test\"quote".to_string(),
            color: "#000".to_string(),
            category: "test".to_string(),
        }];
        let json = tags_to_json(&tags);
        assert!(json.contains(r#"test\"quote"#));
    }

    #[test]
    fn test_generate_tags_spreadsheet() {
        let path = make_temp_file("data.xlsx", b"fake");
        let tags = generate_tags(&path);
        cleanup(&path);

        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].category, "spreadsheet");
        assert_eq!(tags[0].name, "表格");
    }

    #[test]
    fn test_generate_tags_presentation() {
        let path = make_temp_file("slides.pptx", b"fake");
        let tags = generate_tags(&path);
        cleanup(&path);

        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].category, "presentation");
        assert_eq!(tags[0].name, "演示");
    }
}
