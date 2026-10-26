import AppKit
import XCTest
@testable import FlowFinder

/// 第 4 批（R4-04/05/13/14/16/17/26）：设置页与对话框打磨的可测契约。
///
/// 这一批多数是视觉问题，但每一条都对应一个可断言的决定：文案、图标是否撞车、
/// 选中态是否真的有持续视觉、空态是否只说一次、重复的筛选控件是否只剩一个入口。
final class FFSettingsPolishTests: XCTestCase {

    // MARK: - R4-16 关于页

    /// 关于页只给版本与构建时间，不再把 .app 的原始路径摊给普通用户。
    func testAboutBuildLineOmitsBundlePath() {
        let line = FFBuildInfo.aboutBuildLine(buildDateText: "2026-10-21 12:30",
                                              bundlePath: "/Users/x/Desktop/FlowFinder.app")
        XCTAssertEqual(line, "构建 2026-10-21 12:30")
        XCTAssertFalse(line.contains("/"))
    }

    // MARK: - R4-04 / R4-26 主题卡

    /// 普通 momentary NSButton 的 `state` 不产生持续视觉——用户点了「深色」
    /// 却看不出当前生效项。卡片必须自己画出可分辨、可回退的选中态。
    func testThemeCardShowsPersistentSelection() {
        let card = FFThemeCardButton(title: "深色", icon: .moon, tag: 1)
        let idleWidth = card.layer?.borderWidth ?? 0
        let idleColor = card.layer?.borderColor

        card.isSelectedCard = true
        XCTAssertGreaterThan(card.layer?.borderWidth ?? 0, idleWidth,
                             "选中卡片的描边必须比未选中更重")
        XCTAssertNotEqual(card.layer?.borderColor, idleColor,
                          "选中卡片必须换成强调色描边")

        card.isSelectedCard = false
        XCTAssertEqual(card.layer?.borderWidth, idleWidth, "取消选中后描边必须收回")
        XCTAssertEqual(card.layer?.borderColor, idleColor, "取消选中后描边颜色必须还原")
    }

    /// layer 拿到的是 CGColor 快照——不在视图自身的外观里解析，深色模式下
    /// `controlBackgroundColor.cgColor` 会按 Aqua 解析成纯白（实测：深色页两张未选中卡白得刺眼）。
    func testThemeCardIdleBackgroundFollowsAppearance() {
        func idleBrightness(_ appearanceName: NSAppearance.Name) -> CGFloat {
            let card = FFThemeCardButton(title: "浅色", icon: .sun, tag: 1)
            card.appearance = NSAppearance(named: appearanceName)
            card.isSelectedCard = true
            card.isSelectedCard = false
            let color = NSColor(cgColor: card.layer?.backgroundColor ?? NSColor.clear.cgColor)
                .flatMap { $0.usingColorSpace(.deviceRGB) }
            guard let rgb = color else { return -1 }
            return rgb.redComponent * 0.299 + rgb.greenComponent * 0.587 + rgb.blueComponent * 0.114
        }

        let light = idleBrightness(.aqua)
        let dark = idleBrightness(.darkAqua)
        XCTAssertGreaterThan(light, 0.8, "浅色外观下未选中卡片应是浅底，实测 \(light)")
        XCTAssertLessThan(dark, 0.5, "深色外观下未选中卡片必须跟着变深，实测 \(dark)")
    }

    /// 侧栏 7 个分区同样看不出当前在哪一页（R4-04 实测：选中行的玻璃描边
    /// 叠在侧栏底色上完全不可见）。行视图必须自己画出可分辨、可回退的选中态。
    func testSettingsSidebarRowShowsSelection() {
        let row = FFSettingsSidebarRow(title: "通用", icon: .settings)
        let idleBorder = row.layer?.borderWidth ?? 0
        let idleBackground = row.layer?.backgroundColor
        let idleText = row.textField?.textColor
        let idleTint = row.imageView?.contentTintColor

        row.isSelectedRow = true
        XCTAssertGreaterThan(row.layer?.borderWidth ?? 0, idleBorder, "选中行描边必须更重")
        XCTAssertNotEqual(row.layer?.backgroundColor, idleBackground, "选中行必须有底色")
        XCTAssertNotEqual(row.textField?.textColor, idleText, "选中行文字要换成强调色")
        XCTAssertNotEqual(row.imageView?.contentTintColor, idleTint, "选中行图标要换成强调色")

        row.isSelectedRow = false
        XCTAssertEqual(row.layer?.borderWidth, idleBorder, "取消选中后描边必须收回")
        XCTAssertEqual(row.layer?.backgroundColor, idleBackground, "取消选中后底色必须还原")
        XCTAssertEqual(row.textField?.textColor, idleText, "取消选中后文字必须还原")
        XCTAssertEqual(row.imageView?.contentTintColor, idleTint, "取消选中后图标必须还原")
    }

    /// 「主题」分区图标与「深色」选项图标都是月亮，同一屏出现两次同形异义。
    func testThemeSectionIconDiffersFromDarkOptionIcon() {
        XCTAssertNotEqual(FFSettingsIcons.themeSection, AppearanceMode.dark.icon)
        XCTAssertNotEqual(FFSettingsIcons.themeSection, AppearanceMode.light.icon)
        XCTAssertNotEqual(FFSettingsIcons.themeSection, AppearanceMode.system.icon)
    }

    // MARK: - R4-13 文件管理分区

    /// 侧栏叫「文件管理」、页内只有「删除与安全」——分区名必须与内容一致。
    func testFileManageSectionTitleMatchesContent() {
        XCTAssertEqual(SettingsSection.fileManage.title, "安全与确认")
    }

    /// 「跳过废纸篓的永久删除始终二次确认」缺谓语中心词，是病句；
    /// 而且它没有控件，不该排成设置行。
    func testPermanentDeleteNoticeIsAGrammaticalFootnote() {
        XCTAssertTrue(FFNaming.permanentDeleteNotice.contains("需二次确认"),
                      "病句：\(FFNaming.permanentDeleteNotice)")
        XCTAssertFalse(FFNaming.permanentDeleteNotice.contains("始终二次确认"))
    }

    // MARK: - R4-05 连接服务器：协议可用性

    /// 只有 SMB 接入了 SMBBridge。选到不可用协议时，界面必须把话说破，
    /// 而不是只把输入框变灰、把提示藏在占位符里。
    func testUnsupportedProtocolExplainsItself() {
        XCTAssertNil(ConnectServerProtocol.smb.unsupportedNotice)
        for proto in [ConnectServerProtocol.ftp, .sftp, .webdav] {
            let notice = proto.unsupportedNotice ?? ""
            XCTAssertFalse(notice.isEmpty, "\(proto.title) 不可用时必须给出说明")
            XCTAssertTrue(notice.contains(proto.title), "说明里要点名是哪个协议：\(notice)")
            XCTAssertTrue(notice.contains("SMB"), "说明要指出当前可用的是 SMB：\(notice)")
        }
    }

    // MARK: - R4-14 网络存储空态

    /// 计数只出现在列表标题一处；状态行不再重复「共 0 个已连接服务器」。
    func testConnectedCountStatedOnce() {
        XCTAssertEqual(SMBManagerPanel.listHeader(connectedCount: 0), "已连接服务器（0）")
        XCTAssertEqual(SMBManagerPanel.listHeader(connectedCount: 3), "已连接服务器（3）")
        XCTAssertNil(SMBManagerPanel.refreshStatus(connectedCount: 0),
                     "空列表时状态行不应再播报一遍数量")
        XCTAssertEqual(SMBManagerPanel.refreshStatus(connectedCount: 2), "共 2 个已连接服务器")
    }

    /// 「添加服务器」是通栏灰底按钮时看起来像一行禁用项；改为普通按钮 + 排版省略号。
    func testAddServerButtonLabel() {
        XCTAssertEqual(FFNaming.addServerTitle, "添加服务器…")
        XCTAssertFalse(FFNaming.addServerTitle.hasPrefix("+"), "全角加号与系统按钮风格不符")
    }

    /// 空态图标 + 一句话是一个整体（实测：设置页里列表可视区被压到 ~30pt，
    /// 只剩图标，说明文字整段被裁掉）。列表可视区必须容得下空态。
    func testListViewportFitsEmptyState() {
        XCTAssertGreaterThanOrEqual(SMBManagerPanel.minListHeight,
                                    SMBManagerPanel.emptyStateHeight,
                                    "列表可视区比空态还矮，说明文字会被裁掉")
    }

    /// 弹窗实体背景取的是 `windowBackgroundColor.cgColor` 一次性快照——
    /// 深色模式下按 Aqua 解析成白色（实测：连接服务器弹窗白底，
    /// 而字段与浅灰标签按深色解析，标签在白底上直接隐形）。
    func testModalSheetBackgroundFollowsAppearance() throws {
        func brightness(_ name: NSAppearance.Name) -> CGFloat {
            let sheet = FFModalSheet(title: "测试",
                                     bodyView: NSView(),
                                     primaryButton: ("确定", .default),
                                     secondaryButton: "取消",
                                     primaryAction: {})
            defer { sheet.close() }
            guard let container = sheet.contentView, container.wantsLayer else { return -1 }
            container.appearance = NSAppearance(named: name)
            container.updateLayer()
            let color = NSColor(cgColor: container.layer?.backgroundColor ?? NSColor.clear.cgColor)
                .flatMap { $0.usingColorSpace(.deviceRGB) }
            guard let rgb = color else { return -1 }
            return rgb.redComponent * 0.299 + rgb.greenComponent * 0.587 + rgb.blueComponent * 0.114
        }

        let light = brightness(.aqua)
        let dark = brightness(.darkAqua)
        XCTAssertGreaterThan(light, 0.7, "浅色下弹窗应是浅灰底，实测 \(light)")
        XCTAssertLessThan(dark, 0.4, "深色下弹窗必须跟着变深，实测 \(dark)")
    }

    /// 空态图标语义：Wi-Fi 斜杠表示「无网络」，这里要说的是「没有已连接的服务器」。
    func testEmptyStateIconIsNotWifiOff() {
        XCTAssertNotEqual(SMBManagerPanel.emptyStateIcon, .wifiOff)
    }

    // MARK: - R4-17 全局搜索筛选语义

    /// 「当前目录 / 全局搜索」段控件已经决定了搜索位置，
    /// 「全部范围 / 当前位置 / 指定位置」popup 在本地模式下与它完全同义。
    func testScopePopupOnlyAppliesToGlobalSearch() {
        XCTAssertFalse(SearchPanelController.showsScopePopup(for: .local))
        XCTAssertTrue(SearchPanelController.showsScopePopup(for: .global))
    }

    /// 类型筛选同时存在于工具栏 popup 与左侧「文件类型」复选框组，两处取交集，
    /// 用户看不出它们的关系。工具栏只保留时间一档，类型交给侧栏。
    func testToolbarFilterPopupsExcludeType() {
        XCTAssertEqual(SearchPanelController.toolbarFilterKinds, [.time])
    }
}
