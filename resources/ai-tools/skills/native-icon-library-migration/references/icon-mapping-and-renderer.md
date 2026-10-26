# 映射、Resolver 与渲染器模板

这是一个最小可复用的 AppKit 图标层。替换 `IconName` 清单与 `backends` 映射即可用于其他项目。

## 1. 映射规则

- 语义名保持稳定，后端资源键可以不同：

  ```swift
  .fileArchive: .svg("file-zip")
  .fileSpreadsheet: .svg("file-xls")
  .fileType: .svg("file")
  .tags: .sfSymbol("tag.fill")
  ```

- 系统 chrome 优先 SF Symbols；文件类型、文件夹、业务对象优先 SVG。
- 同一个语义名只出现一次；不要用运行时字符串转换猜资源名。
- 每个第三方资源必须同时准备 regular 与 duotone，即使当前只用 line，也避免以后切样式时缺资源。
- 映射表是唯一真源；调用点只传语义名。

## 2. 完整模板

```swift
import AppKit

struct IconName: RawRepresentable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

extension IconName {
    static let search = IconName("search")
    static let fileText = IconName("file-text")
    static let folder = IconName("folder")

    // 生产代码应由资源/设计清单生成这一份列表，而不是手写漏项。
    static let allCases: [IconName] = [.search, .fileText, .folder]
}

enum IconStyle {
    case line
    case duotone
}

enum IconBackend: Equatable {
    case sfSymbol(String)
    case svg(String)
}

enum IconResolver {
    static let backends: [IconName: IconBackend] = [
        .search: .sfSymbol("magnifyingglass"),
        .fileText: .svg("file-text"),
        .folder: .svg("folder"),
    ]

    static func backend(for name: IconName) -> IconBackend {
        backends[name] ?? .sfSymbol("questionmark.square.dashed")
    }

    static var unmappedNames: [IconName] {
        IconName.allCases.filter { backends[$0] == nil }
    }
}

enum IconRenderer {
    private static let lock = NSLock()
    private static var imageCache: [String: NSImage] = [:]
    private static var svgCache: [String: String] = [:]

    /// 模板图：跟随控件 tint、深浅色与强调色。
    static func template(_ name: IconName, size: CGFloat = 16) -> NSImage {
        switch IconResolver.backend(for: name) {
        case .sfSymbol(let symbol):
            return sfImage(symbol, size: size, color: nil, duotone: false, isTemplate: true)
        case .svg(let asset):
            return svgImage(asset, size: size, hex: "000000", duotone: false, isTemplate: true)
        }
    }

    /// 指定色：文件类型、文件夹、彩色标签等固定色场景。
    static func image(_ name: IconName,
                      size: CGFloat = 16,
                      color: NSColor = .labelColor,
                      style: IconStyle = .line) -> NSImage {
        switch IconResolver.backend(for: name) {
        case .sfSymbol(let symbol):
            return sfImage(symbol, size: size, color: color, duotone: style == .duotone, isTemplate: false)
        case .svg(let asset):
            return svgImage(asset, size: size, hex: color.hexRGB, duotone: style == .duotone, isTemplate: false)
        }
    }

    /// 测试用：直接检查映射里的 SF 名称，不经过 fallback。
    static func missingSymbols() -> [String] {
        IconName.allCases.compactMap { name in
            guard case .sfSymbol(let symbol) = IconResolver.backend(for: name) else { return nil }
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? symbol : nil
        }
    }

    /// 测试用：每个 SVG 语义名必须同时有 regular 与 duotone。
    static func missingAssets() -> [String] {
        IconName.allCases.compactMap { name in
            guard case .svg(let asset) = IconResolver.backend(for: name) else { return nil }
            let hasRegular = rawSVG(asset, duotone: false) != nil
            let hasDuotone = rawSVG(asset, duotone: true) != nil
            return hasRegular && hasDuotone ? nil : name.rawValue
        }
    }

    private static func sfImage(_ name: String,
                                size: CGFloat,
                                color: NSColor?,
                                duotone: Bool,
                                isTemplate: Bool) -> NSImage {
        let key = "sf|\(name)|\(size)|\(color?.hexRGB ?? "template")|\(duotone)|\(isTemplate)"
        lock.lock()
        if let hit = imageCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        var config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        if !isTemplate, let color {
            let palette = duotone ? [color, color.withAlphaComponent(0.2)] : [color]
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: palette))
        }

        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            NSLog("[IconRenderer] missing SF Symbol: %@", name)
            return NSImage(size: NSSize(width: size, height: size))
        }

        image.isTemplate = isTemplate
        lock.lock()
        imageCache[key] = image
        lock.unlock()
        return image
    }

    private static func svgImage(_ asset: String,
                                 size: CGFloat,
                                 hex: String,
                                 duotone: Bool,
                                 isTemplate: Bool) -> NSImage {
        let key = "svg|\(asset)|\(size)|\(hex)|\(duotone)|\(isTemplate)"
        lock.lock()
        if let hit = imageCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard var svg = rawSVG(asset, duotone: duotone) else {
            NSLog("[IconRenderer] missing SVG: %@ (%@)", asset, duotone ? "duotone" : "regular")
            return sfImage("questionmark.square.dashed",
                           size: size,
                           color: isTemplate ? nil : .labelColor,
                           duotone: false,
                           isTemplate: isTemplate)
        }

        svg = svg.replacingOccurrences(of: "currentColor", with: "#\(hex)")

        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {
            NSLog("[IconRenderer] cannot parse SVG: %@", asset)
            return NSImage(size: NSSize(width: size, height: size))
        }

        image.size = NSSize(width: size, height: size)
        image.isTemplate = isTemplate
        lock.lock()
        imageCache[key] = image
        lock.unlock()
        return image
    }

    private static func rawSVG(_ asset: String, duotone: Bool) -> String? {
        let variant = duotone ? "duotone" : "regular"
        let resource = duotone ? "\(asset)-duotone" : asset
        let key = "svg/\(variant)/\(asset)"

        lock.lock()
        if let hit = svgCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: resource,
                                        withExtension: "svg",
                                        subdirectory: "Icons/Phosphor/\(variant)"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        lock.lock()
        svgCache[key] = text
        lock.unlock()
        return text
    }
}

extension NSColor {
    var hexRGB: String {
        let color = usingColorSpace(.sRGB) ?? .black
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", red, green, blue)
    }
}
```

## 3. 测试模板

```swift
import XCTest

final class IconFoundationTests: XCTestCase {
    func testEveryIconNameHasBackend() {
        XCTAssertEqual(IconResolver.unmappedNames.map(\.rawValue), [],
                       "每个语义名都必须有后端")
    }

    func testEverySFSymbolExists() {
        XCTAssertEqual(IconRenderer.missingSymbols(), [],
                       "SF Symbol 名称必须在目标 macOS 上存在")
    }

    func testEverySVGAssetExists() {
        XCTAssertEqual(IconRenderer.missingAssets(), [],
                       "每个 SVG 名称必须同时有 regular 与 duotone，并随 App 打包")
    }

    func testBackendPolicy() {
        if case .sfSymbol = IconResolver.backend(for: .search) {
        } else {
            XCTFail("系统 chrome 应使用 SF Symbols")
        }

        if case .svg = IconResolver.backend(for: .fileText) {
        } else {
            XCTFail("文件类型应使用 SVG")
        }
    }
}
```

注意：

- 资源测试必须走 `Bundle.main`，不要只检查仓库目录。
- `missingSymbols()` 不经过 fallback，否则无效名称会被问号图标掩盖。
- `missingAssets()` 直接检查原始 SVG 文本，不能只检查 `NSImage` 尺寸。
- 如果最低部署版本低于当前系统，在最低系统或 CI 再跑一次 SF 名称校验。

## 4. 生成器边界

允许生成：

- `IconName` 常量与 `allCases`。
- 资源清单、映射候选表。

禁止生成：

- `IconResolver.backends` 的手工决策。
- 渲染器、缓存、fallback、测试。

如果仓库里存在“读取 SVG 目录并重写整个图标 Swift 文件”的旧脚本，迁移后必须停用或拆分。典型事故是重跑脚本后，混合映射被替换成单一库映射，测试仍然编译通过但界面全部回退。

## 5. 兼容 SwiftUI

AppKit `NSImage` 可直接用于 SwiftUI：

```swift
Image(nsImage: IconRenderer.template(.search))
```

如果 SwiftUI 层大量使用 `Image(systemName:)`，保留一个轻量包装，最终仍走 `IconResolver`，不要让 SwiftUI 调用点绕开映射表。
