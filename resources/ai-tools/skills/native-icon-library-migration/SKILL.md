---
name: native-icon-library-migration
description: "为 macOS 原生应用（AppKit/SwiftUI）迁移图标体系：盘点语义图标名与调用点，按系统 chrome 与文件类型分配 SF Symbols 和 Phosphor 等 SVG 库，程序化校验 SF 名称与资源完整性，从官方仓库下载 regular/duotone 资源，实现 resolver、缓存与 fallback，并用 XCTest 和全图标联系表做回归与人工核对。用于替换 Lucide/Feather 等图标库、修复 duotone 404、缺图、无效 SF 名称、图标对齐自检误报等任务。"
---

# Native Icon Library Migration

把图标迁移当作一次可审计的依赖替换：先盘点语义名和调用点，再建立显式映射，用测试锁定“每个图标都有后端、每个资源都能打包、每个 SF 名称都能解析”，最后用全图标联系表做人工核对。

## 何时使用

- 替换或淘汰 Lucide、Feather、Tabler 等现有图标库。
- 为 macOS 原生应用引入 SF Symbols，或建立 SF Symbols + 第三方 SVG 的混合方案。
- 校验 SF Symbol 名称、下载 Phosphor regular/duotone、排查缺图、404、duotone 命名错误。
- 建立图标映射完整性测试、全图标联系表、图标对齐回归测试。
- 发现图标切换后布局自检误报 0.5–1pt，需要区分真实错位与控件内边距。

## 不适用

- Web 图标字体、Android/Windows 图标迁移。
- App 图标、Logo、品牌插画设计。
- 纯业务逻辑且没有图标资源或调用点变更。
- 只想临时补一张图，不需要建立可复用图标体系。

## 铁律

1. **语义名与资源名分离。** `fileArchive` 是语义名，`file-zip` 是资源键；映射表是唯一真源，不在调用点散落库名。
2. **先盘点，再下载。** 先列出所有语义名、调用点和角色，不要边写边猜图标名。
3. **先红后绿。** 映射完整性、SF 名称存在性、regular/duotone 资源完整性必须有会失败的测试。
4. **fallback 只做运行时兜底。** 缺映射、缺资源、无效 SF 名称必须让测试失败，不能让问号图标静默通过。
5. **生成器不得覆盖手工映射。** 图标名列表可以生成，后端映射和渲染器必须独立维护。
6. **旧资源后删。** 联系表和真机核对通过前保留旧图标库，清理单独成步。
7. **验证当前系统也验证最低系统。** `NSImage(systemSymbolName:)` 只证明当前 macOS 可解析；最低部署版本需在对应系统或 CI 复验。

## 工作流

### 0. 侦察：建立图标清单

1. 找到图标名定义：枚举、`RawRepresentable` 常量、资源清单或设计 token 文件。
2. 搜索调用点，区分系统 chrome、文件类型、文件夹、标签、状态与自定义域：

   ```bash
   rg -n "FFIcon|NSImage\(systemSymbolName|Image\(systemName|image\(named:" --glob '*.swift'
   ```

3. 记录资源目录、Xcode 的资源引用方式（folder reference 还是逐文件引用）、`Bundle.main` 查找路径。
4. 记录最低 macOS 版本、当前 XCTest 基线与应用内自检入口。
5. 输出清单：`语义名 | 调用点 | 角色 | 当前资源 | 目标后端 | 备注`。

### 1. 设计后端与映射

按用途分配，不按“哪个库好看”分配：

| 用途 | 优先后端 | 原因 |
|---|---|---|
| 工具栏、菜单、箭头、面板、状态、导航 | SF Symbols | 跟随系统字重、tint、深浅色与辅助功能 |
| 文件类型、文件夹、标签、业务对象 | Phosphor 或同类 SVG | 语义比 SF 更贴近文件管理 |
| SF 缺少的语义 | 最接近的 SF，或显式备用 SVG | 允许差异，但必须写进映射与说明 |

规则：

- 每条映射显式写资源键，例如 `.fileArchive: .svg("file-zip")`，不要让运行时把 camelCase 猜成 kebab-case。
- 一个语义名只指向一个后端；需要状态变体时在渲染层处理，不拆成语义名。
- 第三方库缺图标时先确认官方清单，再选 SF 或第二资源；把替代原因写进映射注释或台账。
- 映射表建立后，先写测试再实现渲染器。

### 2. 先写失败测试

至少覆盖四类断言：

1. **映射完整**：每个语义名都有后端，`unmappedNames` 为空。
2. **SF 存在**：每个 `.sfSymbol(name)` 都能被 `NSImage(systemSymbolName:)` 解析。
3. **资源完整**：每个 `.svg(name)` 同时具备 `regular/<name>.svg` 与 `duotone/<name>-duotone.svg`，且能从 `Bundle.main` 读到。
4. **策略正确**：系统 chrome 使用 SF，文件类型/文件夹使用 SVG 后端。

运行定向测试，确认失败原因分别是缺映射、无效 SF 名称、缺资源，而不是 0 tests。测试模板见 [references/icon-mapping-and-renderer.md](references/icon-mapping-and-renderer.md)。

### 3. 实现 resolver、渲染器与缓存

最小结构：

```swift
enum IconBackend: Equatable {
    case sfSymbol(String)
    case svg(String)
}

enum IconResolver {
    static let backends: [IconName: IconBackend] = [/* 显式映射 */]
    static var unmappedNames: [IconName] { IconName.allCases.filter { backends[$0] == nil } }
    static func backend(for name: IconName) -> IconBackend { backends[name] ?? .sfSymbol("questionmark.square.dashed") }
}
```

渲染器必须区分：

- **模板图**：`isTemplate = true`，跟随控件 tint 与深浅色，按钮/菜单优先。
- **指定色**：SF 用 `SymbolConfiguration(paletteColors:)`；SVG 替换 `currentColor`。
- **duotone**：SF 用主色 + 20% 透明副色；SVG 读取官方 duotone 资源，不靠给描边图加透明度伪造。
- **缓存键**：包含后端、资源键、尺寸、颜色、duotone、template 标志，避免不同变体互相污染。
- **缺失兜底**：运行时返回 `questionmark.square.dashed` 并记录日志；测试仍需直接检查原始映射和资源。

完整模板见 [references/icon-mapping-and-renderer.md](references/icon-mapping-and-renderer.md)。

### 4. 下载并校验资源

优先使用脚本，不用手写 URL：

```bash
bash scripts/fetch-phosphor.sh /path/to/Resources/Icons file folder file-zip
```

脚本会：

- 从官方仓库下载 `assets/regular/<name>.svg`；
- 从 `assets/duotone/<name>-duotone.svg` 下载 duotone；
- 本地保存为 `Phosphor/regular/<name>.svg` 与 `Phosphor/duotone/<name>-duotone.svg`；
- 下载 MIT 许可证为 `Phosphor/LICENSE-phosphor.txt`；
- 对 404、空文件、非 SVG 内容显式报错并退出非零。

下载后核对：文件数量 = 名称数 × 2，许可证存在，`Bundle.main` 能找到子目录资源。官方路径、命名差异与已知缺口见 [references/phosphor-assets.md](references/phosphor-assets.md)。

### 5. 用全图标联系表做人工核对

自动测试只能证明“有图”，不能证明“图对了”。新增一个临时 XCTest：

- 遍历全部语义名，8 列网格，单元格带图标与名称；
- SF 用黑色 line，SVG 用蓝色 duotone；
- 渲染到 `/tmp/<app>-icon-contact.png`；
- 用 Read 查看图片，检查破图、重复、语义错配、粗细、尺寸与留白；
- 核对完成后删除测试，或加环境变量门禁并明确记录跳过数量。

代码模板与核对清单见 [references/contact-sheet-and-alignment-qa.md](references/contact-sheet-and-alignment-qa.md)。

### 6. 收口验证

1. 运行全量 XCTest，记录实际执行数与失败数，不把定向测试冒充全量。
2. 运行应用内自检（若有）与布局压力检查。
3. 核对对齐自检：SF Symbol 会给 `NSButton` 增加内边距，视觉中心应比较 `alignmentRect`，且传 `frame` 而非 `bounds`；细节遵循 `appkit-layout-tdd`。
4. 在浅色、深色、高对比与 1x/2x 显示下抽查工具栏、菜单、文件列表、标签。
5. 在最低部署系统或 CI 复验 SF 名称。
6. 确认旧库调用点已清零；旧资源是否删除单独决策。
7. 若项目有需求台账/交接文档，同一轮更新实测数字与未验项。

## 失败模式速查

| 症状 | 根因 | 处理 |
|---|---|---|
| duotone 下载 404 | 官方 URL 需要 `<name>-duotone.svg`，不是 `<name>.svg` | 同时修正远端路径与本地文件名 |
| 某个图标 404 | 第三方库没有该语义 | 查官方清单；换最接近资源或 SF；映射写替代原因 |
| `testEverySFSymbolExists` 报一个名称 | 该 SF 名称在当前系统不存在 | 用 `scripts/validate-sf-symbols.swift` 验证，换有效名称 |
| 资源测试全绿但界面是问号 | fallback 掩盖了缺失，或测试只检查尺寸 | 测试直接检查映射与 `Bundle.main` 资源，不只看图片非空 |
| `Bundle.main` 找不到 SVG | 资源是逐文件引用，子目录未打包 | 改为 folder reference，或用测试实际读取 bundle 路径 |
| `curl: (3) URL rejected` | zsh 不会对普通字符串变量按空格分词 | 用 Bash 数组或显式列表，不用 `names="a b"; for n in $names` |
| 对齐自检误报 0.5–1pt | `NSButton` 的 `frame` 含 SF Symbol 内边距 | 比较 `alignmentRect(forFrame: view.frame)`，从 `superview` 转换 |
| 图标空白或渲染失败 | SVG 非文本、`currentColor` 替换错误、资源名不一致 | 校验文件以 `<svg` 开头；检查资源键与本地文件名 |
| 测试总数无故变化 | 临时联系表测试留在套件 | 用后删除，或环境变量门禁并记录 skip |
| 重跑图标名生成器后映射丢失 | 生成器整文件覆盖了手工 resolver | 拆分“名称生成”和“后端映射”；迁移后不要运行旧生成器 |

## 验收清单

- [ ] 每个语义名都有显式后端，`unmappedNames` 为空。
- [ ] 每个 SF 名称在当前系统可解析，且在最低部署系统复验或明确记录未验。
- [ ] 每个 SVG 名称同时具备 regular 与 duotone，且从 `Bundle.main` 可读。
- [ ] 系统 chrome 与文件类型的后端策略有测试锁定。
- [ ] 联系表人工核对无破图、无语义错配、无明显粗细/尺寸跳变。
- [ ] 全量 XCTest 与应用内自检通过，执行数大于 0。
- [ ] 图标对齐回归使用 `alignmentRect`，未通过放宽容差掩盖问题。
- [ ] 旧库调用点已清零；旧资源清理有独立决策。
- [ ] 许可证随包，项目台账/交接文档已同步。

## 资源

- [scripts/fetch-phosphor.sh](scripts/fetch-phosphor.sh)：下载 Phosphor regular + duotone 与许可证，404 显式失败。
- [scripts/validate-sf-symbols.swift](scripts/validate-sf-symbols.swift)：按当前 macOS 验证 SF Symbol 名称，支持参数或 stdin。
- [references/icon-mapping-and-renderer.md](references/icon-mapping-and-renderer.md)：映射、resolver、SF/SVG 渲染、缓存、fallback 与测试模板。
- [references/contact-sheet-and-alignment-qa.md](references/contact-sheet-and-alignment-qa.md)：全图标联系表、人工核对清单、alignment rect 正确用法。
- [references/phosphor-assets.md](references/phosphor-assets.md)：官方路径、duotone 命名、已知缺口、许可证与资源打包。

## 已验证案例

2026-10-21 在 FlowFinder 0.8.0 上完成一次混合迁移，可作为规模与失败模式参考：

- 104 个语义图标名全部映射；系统 chrome 用 SF Symbols，文件类型/文件夹用 Phosphor。
- 12 个 Phosphor 名称 × regular/duotone = 24 个 SVG；`tags` 在 Phosphor 不存在，改用 SF `tag`/`tag.fill`。
- `rectangle.split.1x3` 经测试确认无效，改为 `rectangle.grid.1x2`。
- 全图标联系表人工核对后删除临时测试；最终 XCTest 312 条、应用内自检 153 项 + 20 轮布局压力均 0 失败。
- SF Symbol 内边距导致焊接自检误报，改为 `alignmentRect(forFrame: button.frame)` 后消除。

## 相关 Skill

- `appkit-layout-tdd`：`alignmentRect`、坐标转换、布局回归与安全测试命令。
- `flowfinder-docs-sync`：FlowFinder 仓库的台账、交接与 CHANGELOG 同轮更新。
- `visual-confirmation-tdd-loop`：图标风格/尺寸存在用户可见取舍时，先可视化确认再实现。
