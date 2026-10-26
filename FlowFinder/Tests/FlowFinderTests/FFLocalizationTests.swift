import AppKit
import XCTest
@testable import FlowFinder

/// R4-01（docs/AUDIT-2026-10-23-UIUX-R4.md）：bundle 内没有任何 `.lproj` 且
/// `CFBundleDevelopmentRegion = en` 时，AppKit 把进程 locale 判成 en_CN——
/// 于是系统菜单项（Undo/Redo/AutoFill/Start Dictation…/Emoji & Symbols）、
/// NSOpenPanel 外壳、`ByteCountFormatter` 单位（`861 bytes` / `Zero bytes`）、
/// 未显式设 locale 的 `DateFormatter`（`12:34 AM`）整套退回英文。
final class FFLocalizationTests: XCTestCase {

    func testDevelopmentRegionIsSimplifiedChinese() {
        let region = Bundle.main.infoDictionary?["CFBundleDevelopmentRegion"] as? String ?? ""
        XCTAssertTrue(region.hasPrefix("zh"),
                      "CFBundleDevelopmentRegion 应为 zh_CN，实测 \(region)")
    }

    func testBuiltBundleContainsChineseLproj() {
        XCTAssertTrue(Bundle.main.localizations.contains("zh-Hans"),
                      "Contents/Resources 下必须有 zh-Hans.lproj，实测 \(Bundle.main.localizations)")
        XCTAssertNotNil(
            Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: "zh-Hans.lproj"),
            "zh-Hans.lproj 必须随包打进产物，否则 Xcode 只声明不生效")
    }

    func testPreferredLocalizationResolvesToChinese() {
        XCTAssertTrue(Bundle.main.preferredLocalizations.contains { $0.hasPrefix("zh") },
                      "AppKit 选中的本地化必须是中文，实测 \(Bundle.main.preferredLocalizations)")
    }

    func testByteCountUsesChineseUnits() {
        let text = FFFormat.fileSize(861)
        XCTAssertTrue(text.hasPrefix("861") && text.contains("字节"),
                      "小文件必须保留字节单位且用中文，实测 \(text)")
        XCTAssertTrue(FFFormat.fileSize(0).contains("字节"), "实测 \(FFFormat.fileSize(0))")
        XCTAssertFalse(FFFormat.fileSize(861).lowercased().contains("bytes"))
    }

    func testShortDateStyleHasNoAmPm() {
        // 复刻任务面板「创建时间」列原来的写法：只设 dateStyle/timeStyle，不设 locale。
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let text = formatter.string(from: Date())
        XCTAssertFalse(text.contains("AM") || text.contains("PM"),
                       "短日期时间不得出现英文 AM/PM，实测 \(text)")
    }

    func testFileInfoKeepsBytesForTinyFiles() {
        // R4-01：简介窗口原来的 allowedUnits 不含 .useBytes，861 字节显示成「1 KB」。
        let text = FileInfoWindowController.formatFileSize(861)
        XCTAssertTrue(text.hasPrefix("861"),
                      "小于 1 KB 的文件必须按字节显示，实测 \(text)")
    }
}
