# T15 Deliverable — Pages 响应式 / 无障碍 / SEO / 架构图修复

**Status:** ✅ Complete — `docs/index.html` 单文件修复 + Playwright 三视口实测证据
**Plan:** `.omo/plans/flowfinder-v074-complete-fix.md` Todo 15（Wave 4）

## 修改文件

| 文件 | 改动 |
|---|---|
| `docs/index.html` | 唯一改动文件（CSS/HTML/原生 JS 均为页面内）。架构三层卡片概念与黑底/蓝绿橙视觉语言完整保留。 |
| `.omo/evidence/flowfinder-v074-complete-fix/task-15/` | `playwright.json`（机器可读全量结果）+ `summary.md` + 11 张截图。 |

## 1. 响应式修复（375/768/1280 实测无横向溢出）

- **FFI 层 margin**：`.arch-layer-ffi` 桌面保留 `margin: 0 48px`（1280 实测 indent=96px），`≤768px` 媒体查询下 `margin: 0`（375/768 实测三层等宽 312/705px，不再挤压）。
- **模块网格**：基础规则改为 `repeat(auto-fill, minmax(min(200px, 100%), 1fr))`（桌面 4 列与旧版一致，窄容器下轨道随容器收缩）；`≤768px` 用 `minmax(0, 1fr)` 单列。
- **长代码标识**：`.arch-module-name { overflow-wrap: anywhere; }`，`FSEventStreamCreate`、`getattrlistbulk(2)` 等不裁剪（实测 cjkClipped=[]）。
- **层头**：`.arch-layer-header` 增加 `flex-wrap: wrap`，375 下副标题自动换行不挤压标题/徽章。
- **header**：`.site-nav .container` 增加 `flex-wrap: wrap; row-gap`，窄屏可优雅换行；DOM 顺序 logo → 操作区 → 链接，视觉顺序由 flex `order` 保持桌面原样。
- **功能网格**：`minmax(320px,1fr)` → `minmax(min(320px,100%),1fr)` 兜底防极窄屏溢出。
- **性能表**：包进 `.table-scroll`（`role="region"` + `tabindex="0"`，横向滚动实测 scrollLeft 0→200），表格不再撑破文档（`min-width:560px`）。
- **移除** `body { overflow-x: hidden }`——所有实测（document.scrollWidth == clientWidth）证明无真实溢出，不留掩盖手段。

## 2. 移动导航（≤768px 菜单按钮）

- 语义 `<button id="menu-toggle">`（inline SVG 汉堡/关闭图标）+ `aria-expanded` + `aria-controls="site-nav"` + `aria-label` 随状态切换（打开/关闭导航菜单）。
- 键盘实测：Tab 4 次可达按钮 → Enter 展开（aria-expanded=true，链接面板 flex）→ Tab 进入第一个链接（#features）→ Enter 导航且菜单自动收起。
- Escape 关闭并归还焦点到按钮；点击面板外部关闭且页面可继续滚动（不锁死）；链接点击收起；`window.resize` 切回桌面宽度时复位状态。
- 桌面（>768px）`.nav-links` 保持原水平布局，菜单按钮 `display:none`。

## 3. 语义 / 无障碍

- 新增 `.skip-link → #main-content`（首次 Tab 即聚焦，滑入可见 top=12，Enter 实测跳到 `#main-content`）。
- 新增 `<main id="main-content" tabindex="-1">` 包住全部内容区；主导航 `nav.site-nav aria-label="主导航"`；页脚链接改为 `nav aria-label="页脚导航"`。
- 全局 `:focus-visible` 2px accent-light 描边（skip-link 用白色描边），focus 不被 fixed nav 遮挡（z-index 2000）。
- 锚点目标 `section[id], main[id] { scroll-margin-top: 80px }`：实测跳转后 `#features` top=80 ≥ navBottom=69，不被遮挡。
- 保留 `lang="zh-CN"`；下载卡 h3→h2 修正标题层级；表格加 `caption`（visually-hidden）；装饰性 emoji span/icon div 加 `aria-hidden="true"`；所有外链 `rel="noopener noreferrer"`。

## 4. SEO / metadata

- canonical `https://waltxao.github.io/FlowFinder/`、robots index/follow、theme-color #000000、color-scheme dark。
- Open Graph 全量（type/site_name/locale/title/description/url/image + 2560×1440 + alt）、Twitter summary_large_image 卡片。
- favicon 保留并加 `sizes="256x256"`；apple-touch-icon 保留加 sizes。
- 图片：截图补 `width=2560 height=1440`（防 CLS）且 `loading="lazy" decoding="async"`；logo 有 alt 与 width/height。

## 5. 对比度 / 动效

- `--text-tertiary: #6e6e73 → #86868b`（黑底 4.27:1 → 5.8:1，卡片底 4.95:1），全部 tertiary 场景（stat-label/arch-layer-sub/arch-link/sys-req/copyright/表头）AA 达标（实测 4.95–6.96）。
- `.btn-primary` / `.skip-link` 底色 `#0A84FF → --accent-dark #0071E3`（白字 3.65:1 → 4.70:1 AA），新增 `--accent-active: #0060C9` 作为 hover（5.97:1）。
- 全页 16 组文本对比度实测全部通过（playwright.json `contrast`）。
- 新增 `@media (prefers-reduced-motion: reduce)`：`scroll-behavior: auto` + 全部 transition/animation 时长降至 0.01ms（实测生效）；本页无功能性动画，全部可禁用。
- `transition: all 0.2s`（旧 .btn）→ 显式属性列表；grep 确认 0 处 `transition: all`。

## 6. 内容核对（页面文案 vs README/CHANGELOG/源码实际状态）

| 项 | 处理 |
|---|---|
| 版本 | v0.7.4 已发布 — 与 README badge、CHANGELOG 最新条目、下载链接一致；未宣称 v0.7.5。 |
| AI 智能打标卡片 | 旧文案「支持 OpenAI / Claude / Ollama 多模型」为虚假宣称 → 改为「本地规则引擎…完全离线；LLM 多模型规划中」，与 README「智能打标」节 + FAQ 一致。 |
| ffi/mod.rs 行数 | 「3000+ 行」→「4800+ 行」（实测 `wc -l` = 4897）。 |
| 架构模块 | UI 层 6 模块 + FFI 3 模块 + Rust 10 模块全部存在于 `rust-core/src/core/`（含 fsevents/path_guard/task_scheduler）；search_engine「名称模糊匹配 + 类型/大小/日期过滤」已对源码验证（`fuzzy_match` + `search_with_filters`）。 |
| 性能表 | 数字与 README 完全一致。 |
| 系统要求 | macOS 13.0+（Apple Silicon）与 README 下载表一致。 |
| 未宣称 | 页面不含 T6/T7 内容索引 FTS5、AI LLM 接入等未发布能力。 |

## 7. 验证证据（Playwright Chromium 实测）

`python3 -m http.server 8765 --directory docs` 提供页面；MCP Playwright 实测。

- **三视口**：375×812 / 768×1024 / 1280×800 — document.scrollWidth == clientWidth（无横向溢出）；所有 `.arch-layer/.arch-module` scrollWidth ≤ clientWidth；架构层 rect 全部在视口内；DOM 重叠审计 0 问题。
- **键盘**：Tab 顺序、Enter/Escape、菜单展开收起、锚点跳转全部通过（详见 playwright.json `keyboardAndMenu`）。
- **reduced-motion**：emulateMedia 实测 scroll-behavior auto、transition 0.01ms。
- **像素级证据**（本模型无视觉输入，改用 canvas 色彩聚类分析截图）：mobile/desktop 架构截图蓝(UI)→绿(FFI)→橙(Rust) 三色层带按序存在，三层卡片概念保留；菜单展开截图与关闭状态在 y70–320 区域 40.5% 像素差异，面板确实渲染。
- **控制台/网络**：0 console error/warning、0 pageerror、0 requestfailed。
- **回归 grep**：`transition: all`=0、`overflow-x: hidden`=0、ASCII 框图=0、必需标记（main/skip/nav-label/meta/aria-expanded/minmax）全部存在。
- 截图 11 张存于 `task-15/`（含菜单展开、skip-link 聚焦特写）。

## 未做（T16/T17 范围）

README/CHANGELOG 版本统一（T16）、发布脚本与 Release 资产（T17）、Swift/Rust 代码未改动。
