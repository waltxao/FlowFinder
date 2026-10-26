import AppKit
import XCTest
@testable import FlowFinder

/// 第四轮审计 R4-31：选择标签弹窗
/// 症状：推荐标签只有一行带色点的文字、无描边无底色，看起来像图例而不是可点选项；
/// 药丸下方还有一大片空白。
final class FFTagSelectorDialogTests: XCTestCase {

    // MARK: - 药丸容器：内容必须贴顶排列

    @MainActor
    func testWrapContainerLaysOutRowsFromTheTop() {
        let container = FFWrapContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        for i in 0..<3 {
            let chip = NSView()
            chip.widthAnchor.constraint(equalToConstant: 120).isActive = true
            chip.heightAnchor.constraint(equalToConstant: 22).isActive = true
            container.addArrangedSubview(chip)
        }
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(container.isFlipped,
                      "非翻转坐标下 y=0 是底边，药丸会贴到容器底部、上方留出一整块空白（R4-31）")
        // 300pt 宽、120pt 药丸、6pt 间距 → 每行 2 个，第 3 个换到第二行
        XCTAssertEqual(container.arrangedSubviews[0].frame.minY, 0, "首行应贴顶")
        XCTAssertEqual(container.arrangedSubviews[2].frame.minY, 28, "第 3 个药丸应换到第二行")
    }

    // MARK: - 推荐药丸：必须看起来可点击

    @MainActor
    func testSuggestedChipsLookSelectable() {
        let dialog = TagSelectorDialog(paths: ["/tmp/ff-r431-sample.bin"],
                                       currentTags: [],
                                       allTags: [Tag(id: "work", name: "工作", color: "#0A84FF")])
        defer { dialog.close() }

        let chips = dialog.suggestedChipsForTesting
        XCTAssertEqual(chips.count, 1, "未选中的标签应出现在推荐区")
        guard let layer = chips.first?.layer else {
            return XCTFail("推荐药丸必须有 layer 才能绘制描边与底色")
        }

        XCTAssertGreaterThanOrEqual(layer.borderWidth, 1,
                                    "无描边的药丸和正文行没有区别，读起来像图例（R4-31）")
        let border = layer.borderColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        let background = layer.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        XCTAssertGreaterThan(border.map(colorSpread) ?? 0, 0.15,
                             "描边应取标签自身颜色，而不是中性灰边")
        XCTAssertGreaterThan(background.map(colorSpread) ?? 0, 0.15,
                             "底色应是标签色的浅淡染色；controlBackgroundColor 的近透明灰在弹窗里等于没有底色")
        XCTAssertLessThanOrEqual(background?.alphaComponent ?? 1, 0.35,
                                 "染色要保持浅淡，实心色块会盖过文字")
    }

    // MARK: - 药丸容器：高度必须贴合内容

    @MainActor
    func testWrapContainerHugsItsContentHeight() {
        let container = FFWrapContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let chip = NSView()
        chip.widthAnchor.constraint(equalToConstant: 120).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 22).isActive = true
        container.addArrangedSubview(chip)

        XCTAssertGreaterThan(container.contentHuggingPriority(for: .vertical).rawValue,
                             NSLayoutConstraint.Priority.defaultHigh.rawValue,
                             "容器能被约束链拉高：弹窗里贴底那条 750 优先级的约束赢了，多出来的高度全变成药丸周围的空白（R4-31）")
    }

    /// 颜色的通道跨度：灰/中性色约为 0，带色相的颜色明显更大
    private func colorSpread(_ color: NSColor?) -> CGFloat {
        guard let color = color?.usingColorSpace(.sRGB) else { return 0 }
        let channels = [color.redComponent, color.greenComponent, color.blueComponent]
        return (channels.max() ?? 0) - (channels.min() ?? 0)
    }
}
