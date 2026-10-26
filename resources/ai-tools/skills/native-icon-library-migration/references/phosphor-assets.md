# Phosphor 资源：路径、命名与缺口

## 1. 官方来源

仓库：`phosphor-icons/core`（MIT）。

原始文件基地址：

```text
https://raw.githubusercontent.com/phosphor-icons/core/main
```

## 2. URL 与本地命名

| 变体 | 远端路径 | 本地文件 |
|---|---|---|
| regular | `assets/regular/<name>.svg` | `Phosphor/regular/<name>.svg` |
| duotone | `assets/duotone/<name>-duotone.svg` | `Phosphor/duotone/<name>-duotone.svg` |
| 许可证 | `LICENSE` | `Phosphor/LICENSE-phosphor.txt` |

最容易错的点：duotone 的远端文件名也带 `-duotone`。写成 `assets/duotone/<name>.svg` 会 404；本地保存成 `<name>.svg` 会让 `Bundle.main` 查找失败。

## 3. 使用脚本

```bash
bash scripts/fetch-phosphor.sh /path/to/Resources/Icons file folder file-zip
```

输出示例：

```text
OK regular file
OK duotone file
OK regular folder
OK duotone folder
OK license
DONE: 2 icon name(s), regular + duotone under /path/to/Resources/Icons/Phosphor
```

缺图标时：

```text
MISSING regular tags (.../assets/regular/tags.svg)
MISSING duotone tags (.../assets/duotone/tags-duotone.svg)
Missing or invalid:
  - tags (regular)
  - tags (duotone)
FAILED: 2 item(s) missing or invalid
```

脚本对 404、空响应、非 SVG 内容都返回非零。不要把失败当 warning 忽略。

已有有效文件默认跳过；已存在但不是 SVG 的文件会被替换。要强制刷新某个有效资源，先删除对应文件再运行。

## 4. 已知缺口与替代

以下是 2026-10-21 在 `phosphor-icons/core` 验证过的替代，使用前仍应查当前仓库：

| 语义 | Phosphor 情况 | 替代 |
|---|---|---|
| `tags`（多标签） | 没有 `tags` 资源 | SF `tag.fill`；单标签可用 `tag` |
| `file-archive` | 没有该名称 | `file-zip` |
| `file-spreadsheet` | 没有通用表格名 | `file-xls`（或 `file-csv`，按业务选择） |
| `file-type` | 没有通用类型名 | `file` |
| `archive` | 有 `archive` | 可用 Phosphor `archive` |

原则：语义名不因为资源缺口改名；在映射里写 `fileArchive -> file-zip`，让调用点保持稳定。

## 5. 资源打包

Xcode 中 `Resources/Icons` 必须是 **folder reference**（蓝色文件夹），子目录才会原样进入 bundle。如果工程是逐文件引用，新增的 `Phosphor/regular` 与 `Phosphor/duotone` 可能不会被打包。

验证方式不是看 Xcode 导航器，而是测试实际读取：

```swift
let url = Bundle.main.url(
    forResource: "file-text",
    withExtension: "svg",
    subdirectory: "Icons/Phosphor/regular"
)
XCTAssertNotNil(url)
```

加上 `missingAssets()` 覆盖全部资源，避免只验证一个样本。

## 6. 渲染注意

- Phosphor SVG 使用 `currentColor`；渲染前替换成目标色，保留其余 `fill-opacity`。
- duotone SVG 通常包含两条路径，一条带低透明度。不要给 regular 图标整体加透明度来伪造 duotone。
- `NSImage(data:)` 解析失败时要记录资源名与变体；否则界面只会出现空白。
- 缓存键必须包含变体（regular/duotone）、资源名、尺寸、颜色和 template 标志。

## 7. shell 陷阱

在 zsh 中：

```zsh
names="file folder file-zip"
for n in $names; do
  curl ".../$n.svg"
done
```

不会按空格分词，整个字符串会变成一个 URL，出现：

```text
curl: (3) URL rejected: Malformed input to a URL function
```

改用 Bash 数组或显式列表：

```bash
names=(file folder file-zip)
for n in "${names[@]}"; do
  curl ".../$n.svg"
done
```

或直接使用 `fetch-phosphor.sh`，脚本已按 Bash 数组处理。

## 8. 许可证

下载 `LICENSE` 随资源目录保存，并在项目的第三方许可/关于页面保留 MIT 声明。不要只把 SVG 放进仓库而漏掉许可证。
