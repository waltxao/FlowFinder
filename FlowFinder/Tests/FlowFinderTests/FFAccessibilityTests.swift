import AppKit
import XCTest
@testable import FlowFinder

final class FFAccessibilityTests: XCTestCase {

    func testToolbarConfigButtonHasAccessibilityLabel() {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 600, height: 72))
        XCTAssertEqual(toolbar.displaySettingsButton.accessibilityLabel(), "显示设置")
        XCTAssertFalse(toolbar.displaySettingsButton.toolTip?.isEmpty ?? true)
        XCTAssertFalse(toolbar.displaySettingsButton.isHidden)
    }

    func testHitTargetsMeetDesktopMinimum() {
        XCTAssertGreaterThanOrEqual(FFVisualTokens.rowHeight, 24)
        XCTAssertGreaterThanOrEqual(FFVisualTokens.statusBarHeight, 24)
        XCTAssertGreaterThanOrEqual(FFToolRowView.preferredHeight, 24)
        XCTAssertGreaterThanOrEqual(FFVisualTokens.activePaneEdge, 2)
    }

    func testContextMenuDoesNotStealCmdIFromDetailsBar() {
        let menu = FFPaneMenuBuilder.buildMenu(for: NSObject(), isLeft: true, tagsSubmenu: nil)
        let infoItem = menu.items.first { $0.title == "显示简介" }
        XCTAssertEqual(infoItem?.keyEquivalent, "",
                       "⌘I 应由主菜单打开区内详情栏，右键菜单不得抢占")
    }

    func testKeyboardContractEveryActionHasDisplay() {
        for action in FFShortcutAction.allCases {
            XCTAssertFalse(FFKeyboardContract.shortcut(for: action).display.isEmpty,
                           "\(action) 缺少显示文案")
        }
    }

    func testPrimaryTextContrastMeetsWCAGAAInLightAndDark() {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            appearance.performAsCurrentDrawingAppearance {
                let ratio = FFContrast.ratio(.labelColor, .windowBackgroundColor)
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                            "\(appearanceName.rawValue) 主文本对比度不足")
            }
        }
    }

    func testPrimaryTextContrastMeetsWCAGAAInHighContrastModes() {
        let names: [NSAppearance.Name] = [.accessibilityHighContrastAqua,
                                          .accessibilityHighContrastDarkAqua]
        for appearanceName in names {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            appearance.performAsCurrentDrawingAppearance {
                let ratio = FFContrast.ratio(.labelColor, .windowBackgroundColor)
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                            "\(appearanceName.rawValue) 主文本对比度不足")
            }
        }
    }
}
