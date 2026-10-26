import AppKit
import XCTest
@testable import FlowFinder

final class FFVisualTokensTests: XCTestCase {
    /// 用户在设置里选过强调色会写进真实 UserDefaults，
    /// 本类断言的是「未设置时回退系统强调色」，必须先隔离该键。
    private var savedAccent: Any?

    override func setUp() {
        super.setUp()
        savedAccent = UserDefaults.standard.object(forKey: FFAccent.storageKey)
        UserDefaults.standard.removeObject(forKey: FFAccent.storageKey)
    }

    override func tearDown() {
        if let savedAccent {
            UserDefaults.standard.set(savedAccent, forKey: FFAccent.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FFAccent.storageKey)
        }
        super.tearDown()
    }

    func testSpacingScaleIsFourBased() {
        XCTAssertEqual(FFVisualTokens.Spacing.xs, 4)
        XCTAssertEqual(FFVisualTokens.Spacing.s, 8)
        XCTAssertEqual(FFVisualTokens.Spacing.m, 12)
        XCTAssertEqual(FFVisualTokens.Spacing.l, 16)
        XCTAssertEqual(FFVisualTokens.Spacing.xl, 24)
    }

    func testRowAndControlMetrics() {
        let defaults = UserDefaults.standard
        let oldSize = defaults.object(forKey: FFSizePreference.storageKey)
        defaults.removeObject(forKey: FFSizePreference.storageKey)
        defer {
            if let oldSize {
                defaults.set(oldSize, forKey: FFSizePreference.storageKey)
            } else {
                defaults.removeObject(forKey: FFSizePreference.storageKey)
            }
        }

        XCTAssertEqual(FFSizePreference.current, .comfortable)
        XCTAssertEqual(FFVisualTokens.rowHeight, 30)
        XCTAssertEqual(FFVisualTokens.rowHeightCompact, 24)
        XCTAssertEqual(FFVisualTokens.toolbarHeight, 34)
        XCTAssertEqual(FFVisualTokens.statusBarHeight, 28)
        XCTAssertEqual(FFVisualTokens.iconSize, 18)
        XCTAssertEqual(FFVisualTokens.Font.body.pointSize, 13)
        XCTAssertEqual(FFVisualTokens.activePaneEdge, 2)
    }

    func testContrastHelperMatchesKnownRatios() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(FFContrast.ratio(white, black), 21, accuracy: 0.1)
        XCTAssertEqual(FFContrast.ratio(white, white), 1, accuracy: 0.01)
    }

    func testAccentIsSystemAccent() {
        XCTAssertEqual(FFVisualTokens.accent, NSColor.controlAccentColor)
    }

    // MARK: - R4-27 深色模式下的文字对比度下限

    /// 把带 alpha 的动态色先合成到背景上再算对比度：
    /// FFContrast 按颜色自身亮度计算，半透明白直接交给它会虚报成 21:1。
    private func contrast(_ foreground: NSColor,
                          on background: NSColor,
                          in appearanceName: NSAppearance.Name) -> CGFloat {
        guard let appearance = NSAppearance(named: appearanceName) else { return -1 }
        var ratio: CGFloat = -1
        appearance.performAsCurrentDrawingAppearance {
            guard let fg = foreground.usingColorSpace(.sRGB),
                  let bg = background.usingColorSpace(.sRGB) else { return }
            let a = fg.alphaComponent
            let composited = NSColor(srgbRed: fg.redComponent * a + bg.redComponent * (1 - a),
                                     green: fg.greenComponent * a + bg.greenComponent * (1 - a),
                                     blue: fg.blueComponent * a + bg.blueComponent * (1 - a),
                                     alpha: 1)
            ratio = FFContrast.ratio(composited, bg)
        }
        return ratio
    }

    func testHintTokenMeetsDarkContrastFloor() {
        let background = NSColor.windowBackgroundColor
        let old = contrast(.tertiaryLabelColor, on: background, in: .darkAqua)
        XCTAssertLessThan(old, 3.0,
                          "对照基线：tertiaryLabel 在深色底上确实接近不可读（R4-27 根因），实测 \(old):1")

        let dark = contrast(FFVisualTokens.hint, on: background, in: .darkAqua)
        XCTAssertGreaterThanOrEqual(dark, 4.5,
                                    "分组标题/提示文字深色下必须达到 4.5:1，实测 \(dark):1")
        // 浅色下系统次级色约 3.5:1（Apple 自身的提示档），本轮审计只在深色翻车
        let light = contrast(FFVisualTokens.hint, on: background, in: .aqua)
        XCTAssertGreaterThanOrEqual(light, 3.0,
                                    "浅色下提示文字不得低于 3:1，实测 \(light):1")
    }
}

final class FFDesignFoundationTests: XCTestCase {
    private var savedSize: Any?

    override func setUp() {
        super.setUp()
        savedSize = UserDefaults.standard.object(forKey: FFSizePreference.storageKey)
        UserDefaults.standard.removeObject(forKey: FFSizePreference.storageKey)
    }

    override func tearDown() {
        if let savedSize {
            UserDefaults.standard.set(savedSize, forKey: FFSizePreference.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FFSizePreference.storageKey)
        }
        super.tearDown()
    }

    func testSizeLevelsMatchApprovedMetrics() {
        XCTAssertEqual(FFSizeLevel.compact.bodyFontSize, 12)
        XCTAssertEqual(FFSizeLevel.compact.rowHeight, 28)
        XCTAssertEqual(FFSizeLevel.compact.iconSize, 16)

        XCTAssertEqual(FFSizeLevel.comfortable.bodyFontSize, 13)
        XCTAssertEqual(FFSizeLevel.comfortable.rowHeight, 30)
        XCTAssertEqual(FFSizeLevel.comfortable.iconSize, 18)

        XCTAssertEqual(FFSizeLevel.large.bodyFontSize, 14)
        XCTAssertEqual(FFSizeLevel.large.rowHeight, 32)
        XCTAssertEqual(FFSizeLevel.large.iconSize, 20)

        XCTAssertEqual(FFSizePreference.current, .comfortable, "默认必须是舒适档")
    }

    func testSizePreferencePersistsAndUpdatesTokens() {
        FFSizePreference.current = .large
        XCTAssertEqual(FFSizePreference.current, .large)
        XCTAssertEqual(UserDefaults.standard.string(forKey: FFSizePreference.storageKey), "large")
        XCTAssertEqual(FFVisualTokens.rowHeight, 32)
        XCTAssertEqual(FFVisualTokens.iconSize, 20)
        XCTAssertEqual(FFVisualTokens.Font.body.pointSize, 14)

        FFSizePreference.current = .compact
        XCTAssertEqual(FFSizePreference.current, .compact)
        XCTAssertEqual(FFVisualTokens.rowHeight, 28)
        XCTAssertEqual(FFVisualTokens.iconSize, 16)
        XCTAssertEqual(FFVisualTokens.Font.body.pointSize, 12)
    }

    func testSettingsVisualAMetrics() {
        XCTAssertEqual(FFSettingsMetrics.cardRadius, 12)
        XCTAssertEqual(FFSettingsMetrics.rowHeight, 40)
        XCTAssertEqual(FFSettingsMetrics.controlHeight, 26)
        XCTAssertEqual(FFSettingsMetrics.cardPadding, 16)
        XCTAssertEqual(FFSettingsMetrics.titleFontSize, 13)
        XCTAssertEqual(FFSettingsMetrics.descFontSize, 11)
    }

    func testTopBarC2Metrics() {
        XCTAssertEqual(FFTopBarMetrics.height, 36)
        XCTAssertEqual(FFTopBarMetrics.tabHeight, 30)
        XCTAssertEqual(FFTopBarMetrics.topStrip, 6)
        XCTAssertEqual(FFTopBarMetrics.centerline, 18)
        XCTAssertEqual(FFTopBarMetrics.tabFontSize, 13)
        XCTAssertEqual(FFTopBarMetrics.iconSize, 16)
        XCTAssertEqual(FFTopBarMetrics.fillet, 10)
        XCTAssertEqual(FFTopBarMetrics.horizontalMargin, 16)
    }
}

final class FFIconFoundationTests: XCTestCase {
    func testEveryIconNameHasBackend() {
        XCTAssertEqual(FFIconResolver.unmappedNames.map(\.rawValue), [],
                       "每个 FFIconName 都必须有 SF/Phosphor 映射")
    }

    func testEverySFSymbolExists() {
        XCTAssertEqual(FFIcon.missingSymbols(), [],
                       "映射里的 SF Symbol 名称必须在当前 macOS 上存在")
    }

    func testEveryPhosphorAssetExists() {
        XCTAssertEqual(FFIcon.missingAssets(), [],
                       "Phosphor 图标 SVG 必须随 App 打包")
    }

    func testSystemChromeUsesSFAndFileTypesUsePhosphor() {
        if case .sfSymbol = FFIconResolver.backend(for: .search) {
        } else {
            XCTFail("系统 chrome 应使用 SF Symbols")
        }
        if case .phosphor = FFIconResolver.backend(for: .fileText) {
        } else {
            XCTFail("文件类型应使用 Phosphor")
        }
        if case .phosphor = FFIconResolver.backend(for: .folder) {
        } else {
            XCTFail("文件夹图标应使用 Phosphor")
        }
    }

}
