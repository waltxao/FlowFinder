# 联系表与对齐自检

自动测试证明“每个名字有资源”，联系表证明“每个图形看起来正确”。两者缺一不可。

## 1. 临时联系表 XCTest

遍历全部语义名，渲染成一张带标签的 PNG。建议在专用分支或临时测试中运行，核对完删除。

```swift
import AppKit
import XCTest

func testRenderIconContactSheetForInspection() throws {
    let names = IconName.allCases
    let columns = 8
    let cell = NSSize(width: 128, height: 88)
    let rows = Int(ceil(Double(names.count) / Double(columns)))
    let sheetSize = NSSize(width: cell.width * CGFloat(columns),
                           height: cell.height * CGFloat(rows))

    let image = NSImage(size: sheetSize)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: sheetSize).fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9),
        .foregroundColor: NSColor.black,
    ]

    for (index, name) in names.enumerated() {
        let column = index % columns
        let row = index / columns
        let origin = NSPoint(x: CGFloat(column) * cell.width,
                             y: sheetSize.height - CGFloat(row + 1) * cell.height)

        let icon: NSImage
        switch IconResolver.backend(for: name) {
        case .sfSymbol:
            icon = IconRenderer.image(name, size: 30, color: .black, style: .line)
        case .svg:
            icon = IconRenderer.image(name, size: 30, color: .systemBlue, style: .duotone)
        }

        icon.draw(in: NSRect(x: origin.x + 49, y: origin.y + 30, width: 30, height: 30))
        (name.rawValue as NSString).draw(
            at: NSPoint(x: origin.x + 4, y: origin.y + 8),
            withAttributes: attributes
        )
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        return XCTFail("联系表渲染失败")
    }

    try png.write(to: URL(fileURLWithPath: "/tmp/icon-contact.png"))
}
```

运行：

```bash
xcodebuild test \
  -project App.xcodeproj \
  -scheme AppTests \
  -derivedDataPath /tmp/app-xctest-derived \
  -only-testing:AppTests/IconFoundationTests/testRenderIconContactSheetForInspection
```

然后用图片查看工具或 Read 打开 `/tmp/icon-contact.png`。

## 2. 联系表核对清单

- **破图**：空白、问号、只显示一半、颜色透明。
- **重复**：不同语义名显示成同一图形，例如 open/close 面板都映射到同一个符号；确认是否可接受。
- **语义错配**：rows 图标显示成 columns、file-archive 显示成通用文件、tags 显示成单个 tag。
- **粗细**：SF 与 SVG 混排时，线条明显一粗一细。
- **尺寸**：同一个 30pt 单元格里，有的图标视觉上大一圈。
- **留白**：图标在自身画布中偏移，导致按钮里看起来不居中。
- **duotone**：副色是否过淡或抢主色；是否读到了正确的 `-duotone` 资源。
- **深色**：白底联系表看不出深色模式问题，需要单独在深色界面截图。

发现语义错配时改映射，不要只改显示名。发现 SF 与 SVG 视觉重量不一致时，优先调尺寸/字重或换更接近的符号，不要给整组图标加统一阴影。

## 3. 联系表测试的去留

两种做法：

1. **删除**：适合一次性迁移。核对完成后删除测试，保持测试总数稳定。
2. **门禁保留**：适合长期维护。默认跳过，只有显式要求时才写文件：

   ```swift
   guard ProcessInfo.processInfo.environment["RENDER_ICON_SHEET"] == "1" else {
       throw XCTSkip("Set RENDER_ICON_SHEET=1 to render the contact sheet")
   }
   ```

   保留时必须在台账/交接里记录 skip 数，避免“测试总数变了”被误判为回归。

## 4. SF Symbol 内边距与 alignment rect

SF Symbol 放进 `NSButton` 后，按钮的 `frame` 往往比视觉对齐矩形大，直接比较 `frame.midY` 会出现 0.5–1pt 的假失败。

正确做法：

```swift
let visualRect = button.alignmentRect(forFrame: button.frame)
let rectInContainer = container.convert(visualRect, from: button.superview)
XCTAssertLessThan(abs(rectInContainer.midY - expectedCenterY), 0.5)
```

关键点：

- `alignmentRect(forFrame:)` 接收的是 **superview 坐标系里的 frame**，不是 `bounds`。
- 转换时从 `button.superview` 转到目标祖先，不要从按钮自身转换。
- 不要为了转绿放宽容差；先确认测的是视觉对齐矩形。
- 自定义视图通常 `alignmentRect == bounds`，但按钮、带 bezel 的控件、SF Symbol 图像按钮需要单独处理。

更完整的坐标、flipped、NSSplitView 与安全测试命令见 `appkit-layout-tdd` Skill。

## 5. 真实界面核对

联系表通过后，至少核对：

- 工具栏与菜单：模板图是否跟随 tint/深浅色。
- 文件列表：文件类型图标是否与真实文件类型匹配。
- 标签/侧栏：SF 与 SVG 混排时基线是否一致。
- 深色、高对比、1x/2x：是否出现黑边、透明边或模糊。
- 最低部署系统：SF 名称是否存在，布局是否因符号尺寸不同而错位。

没有做的人工项要明确写“未验”，不要用自动化结果代替视觉确认。
