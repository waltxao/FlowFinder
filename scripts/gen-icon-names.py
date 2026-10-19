#!/usr/bin/env python3
"""根据 Resources/Icons/*.svg 重新生成 UI/FFIcon.swift 的图标名列表。

新增图标流程：
  1. 把 lucide 的 <name>.svg 放进 FlowFinder/FlowFinder/Resources/Icons/
  2. 跑 `python3 scripts/gen-icon-names.py`
  3. 重新构建

图标名会转成 camelCase 常量：arrow-down-a-z -> .arrowDownAZ
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "FlowFinder/FlowFinder/Resources/Icons"
SWIFT_OUT = ROOT / "FlowFinder/FlowFinder/UI/FFIcon.swift"

TEMPLATE = '''import AppKit

// Lucide 图标层。所有小图标从这里取，不再直接用 SF Symbol。
// 资源：Resources/Icons/<name>.svg（Lucide 0.544，ISC，见同目录 LICENSE-lucide.txt）
// 本文件由 scripts/gen-icon-names.py 生成，改图标请改资源后重跑脚本。

struct FFIconName: RawRepresentable, Hashable {{
    let rawValue: String
    init(rawValue: String) {{ self.rawValue = rawValue }}
    init(_ rawValue: String) {{ self.rawValue = rawValue }}
}}

extension FFIconName {{
{names}
}}

enum FFIconStyle {{
    /// 纯描边，最常用
    case line
    /// 18% 填色 + 描边，用于文件类型与文件夹
    case duotone
}}

enum FFIcon {{
    enum Metrics {{
        static let toolbar: CGFloat = 15
        static let inline: CGFloat = 13
        static let menu: CGFloat = 16
        static let list: CGFloat = 18
        static let duotoneFillOpacity: CGFloat = 0.18
    }}

    private static let lock = NSLock()
    private static var imageCache: [String: NSImage] = [:]
    private static var svgCache: [String: String] = [:]

    /// 模板图（跟随控件 tint / 深浅色自动反色）。按钮、菜单项优先用这个。
    static func template(_ name: FFIconName, size: CGFloat = Metrics.toolbar) -> NSImage {{
        render(name: name, size: size, hex: "000000", duotone: false, isTemplate: true)
    }}

    /// 指定颜色的实色图，用于文件类型、文件夹、彩色标签等需要固定色的场景。
    static func image(_ name: FFIconName,
                      size: CGFloat = Metrics.toolbar,
                      color: NSColor = .labelColor,
                      style: FFIconStyle = .line) -> NSImage {{
        render(name: name, size: size, hex: color.ffHexString, duotone: style == .duotone, isTemplate: false)
    }}

    /// 资源自检：返回资源缺失的图标名
    static func missingAssets() -> [String] {{
        FFIconName.allCases.filter {{ rawSVG($0) == nil }}.map(\\.rawValue)
    }}

    private static func render(name: FFIconName,
                               size: CGFloat,
                               hex: String,
                               duotone: Bool,
                               isTemplate: Bool) -> NSImage {{
        let key = "\\(name.rawValue)|\\(size)|\\(hex)|\\(duotone)|\\(isTemplate)"
        lock.lock()
        if let hit = imageCache[key] {{
            lock.unlock()
            return hit
        }}
        lock.unlock()

        guard var svg = rawSVG(name) else {{
            NSLog("[FFIcon] 缺少图标资源: %@", name.rawValue)
            return NSImage(size: NSSize(width: size, height: size))
        }}
        svg = svg.replacingOccurrences(of: "currentColor", with: "#\\(hex)")
        if duotone {{
            svg = svg.replacingOccurrences(of: "fill=\\"none\\"",
                                           with: "fill=\\"#\\(hex)\\" fill-opacity=\\"\\(Metrics.duotoneFillOpacity)\\"")
        }}
        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {{
            NSLog("[FFIcon] 图标解析失败: %@", name.rawValue)
            return NSImage(size: NSSize(width: size, height: size))
        }}
        image.size = NSSize(width: size, height: size)
        image.isTemplate = isTemplate
        lock.lock()
        imageCache[key] = image
        lock.unlock()
        return image
    }}

    private static func rawSVG(_ name: FFIconName) -> String? {{
        lock.lock()
        if let hit = svgCache[name.rawValue] {{
            lock.unlock()
            return hit
        }}
        lock.unlock()

        guard let url = Bundle.main.url(forResource: name.rawValue, withExtension: "svg", subdirectory: "Icons"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {{
            return nil
        }}
        lock.lock()
        svgCache[name.rawValue] = text
        lock.unlock()
        return text
    }}
}}

extension NSColor {{
    /// "0a84ff" 形式（不带 #），供 SVG 染色使用
    var ffHexString: String {{
        let c = usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }}
}}

extension FFIconName {{
    static let allCases: [FFIconName] = [{all_cases}]
}}

extension NSButton {{
    /// 统一的按钮图标设置：模板图 + 只显示图
    func ffIcon(_ name: FFIconName, size: CGFloat = FFIcon.Metrics.toolbar) {{
        image = FFIcon.template(name, size: size)
        imagePosition = .imageOnly
    }}
}}
'''


def camel(name: str) -> str:
    parts = name.split("-")
    out = parts[0]
    for p in parts[1:]:
        out += p[:1].upper() + p[1:]
    return out


def main() -> int:
    files = sorted(p.stem for p in ICON_DIR.glob("*.svg"))
    if not files:
        print(f"没有找到任何 svg：{ICON_DIR}", file=sys.stderr)
        return 1
    seen = {}
    for f in files:
        c = camel(f)
        if c in seen:
            print(f"命名冲突：{f} 与 {seen[c]} 都会生成 .{c}", file=sys.stderr)
            return 1
        seen[c] = f
    names = "\n".join(f'    static let {camel(f)} = FFIconName("{f}")' for f in files)
    all_cases = ", ".join(f".{camel(f)}" for f in files)
    SWIFT_OUT.write_text(TEMPLATE.format(names=names, all_cases=all_cases), encoding="utf-8")
    print(f"生成 {SWIFT_OUT.relative_to(ROOT)}：{len(files)} 个图标")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
