# FlowFinder 2026-10-20 实测案例

本文件是 `appkit-interaction-regression-testing` 的案例证据，不是通用规则。项目路径、scheme、环境变量名按实际替换。

## 背景与用户纠正

- AppKit macOS 文件管理器；仓库位于外置卷 `/Volumes/Iris-Data/...`；使用 Xcode-beta；应用单实例。
- 用户第二轮反馈：App 卡顿严重、标签页拖拽“感觉已经被改废”，要求结合历史文档重审，逐项可视化确认后再开发。
- 交接文档声称 Swift XCTest 通道不可用、应用内自检 135 项。

## 基线：先证伪“通道坏了”

桌面版应用在运行，`make swift-test` 会先 `pkill`，因此先征得用户同意。

```sh
pkill -f "MacOS/FlowFinder" 2>/dev/null || true
mkdir -p /tmp/flowfinder-test-home/Desktop /tmp/flowfinder-test-home/Documents
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/文件管理系统/flowfinder-native
/usr/bin/timeout 420 xcodebuild test \
  -project FlowFinder/FlowFinder.xcodeproj \
  -scheme FlowFinderTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

结果：144 条、0 失败、`TEST SUCCEEDED`、exit 0。交接文档的“通道阻塞”是过期结论。

## pbxproj 注册

新增 `FlowFinder/Tests/FlowFinderTests/InteractionRegressionTests.swift`，注册四处：

- `PBXBuildFile`：`FFB100010000000000000001`
- `PBXFileReference`：`FFB200020000000000000002`
- test group `children`
- `PBXSourcesBuildPhase`

已有 ID 段 `FFC2000`/`FFC3000`/`FFC4000`/`FFC5000` 已占用；注册前 grep 候选 ID。漏注册的表现是 `cannot find ... in scope`。

## 红 → 绿

- 18 条回归测试，覆盖占位标签、拖出新窗单栏、缓冲重排、控件点击、按压取侧、4pt 窗口拖动阈值。
- 修前：162 条、19 处失败，例如：

  ```text
  XCTAssertEqual failed: ("2") is not equal to ("1") - 占位标签应被真实标签替换，而不是并列
  ```

- 修后：162 条、0 失败、`TEST SUCCEEDED`。
- 后续 TDD：
  - `FFDropResolverTests` 14 条，stub 阶段 13 条失败；实现后 14/0，全量 176/0。
  - `FFDragGeometryCacheTests` 3 条；全量 179/0。
  - `FFDragIntegrationTests` 6 条，红阶段 5 条失败；修复后全量 185/0。
  - 后续结构/性能护栏累计到 190/0。

## 应用内自检

- 运行：`FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1 <可执行文件>`。
- 实测总数 129：5 拖放 + 71 决策表 + 7 区域 + 4 行为 + 19 焊接 + 22 列表外壳。
- 交接文档写的 135 不实；焊接台账写 21，实测 19。文档已按日志更正。
- 六步落点自检全部 PASS，新增 ⑥ 的日志形态：

  ```text
  [SELFTEST] ⑥ 拖出新窗口为单栏 PASS 单栏=true 左标签=1 期望=1
  ```

- ⑥ 的构造方式：`MainWindowController(startsWithSinglePane: true, showImmediately: false, runsSelfTests: false)`，装配完再显示，防止派生窗口递归跑自检。
- 区域解析自检：真实视图 `hitTest` → 区域，5 项断言。

## 几何日志

文档中记录过以下实测值（项目专用，仅作格式示例）：

- 卡片上边缘：顶部 0 / 底部 8 → 统一为标题区 28 + 留白 8。
- 标签条浮到窗口顶：左标签条 x=280..840，y=872..900。
- 侧栏隐藏避让：标签条 x=106..700。

做法是让应用打印实际 frame，再与设计常量比对；截图只用于视觉核对，不作为几何真值。

## 根因与修法

| 现象 | 根因 | 修法 |
|---|---|---|
| 点任何标签都选中最后一个，拖也拖最后一个 | `PaneTabItemView.hitTest` 直接 `return self`，没有 `frame.contains`；NSStackView 逆序派发 | 先 `guard frame.contains(point)` |
| 同侧落点复制标签 | `receiveTab` 同侧分支走了 `insert` | 同侧只 `move` |
| 重排/指示线偏移 | stack / strip / window 三套坐标混用 | 抽 `FFTabReorder.insertionIndex`，两处统一转 strip 坐标 |
| 侧栏行、标签条按钮、药丸点不动 | 控件在 `.window`/`.title` 内被解析成拖窗口 | `NSControl`/点击手势只在这两个区域豁免；药丸声明 `.panel` 并接管 `hitTest` |
| 拖出新窗默认双栏 | 初始化读取全局 `single_pane_mode` | 显式 `startsWithSinglePane: true`，装配完再显示，`runsSelfTests: false` |
| 单标签拖回多一个标签 | 真实标签填入前未清理占位 | `removeLonePlaceholder()` |
| 自检全绿但真实链路仍坏 | 自检绕过真实视图 | 改为真实 `contentView.hitTest` + 真实 frame |

## 合成事件限制

本机实测到的三重干扰：

- `CGWindowList` 左上原点 vs `CGEvent` 左下原点。
- TCC/辅助功能授权弹窗。
- Finder/WorkBuddy 窗口遮挡。

因此物理拖拽手感没有自动化；交付时明确写“需人工复验”。应用内 `hitTest` 自检负责真实视图几何，合成事件只做 smoke。

## 交付边界

- 未提交代码（用户未要求）。
- 仍待人工：物理拖拽手感、桌面副本控件点击。
- 真位移按用户裁定留到单独一轮。
