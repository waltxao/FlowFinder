import Cocoa

// 纯 AppKit 应用入口（v0.7.6 起替换 SwiftUI @main 壳，移除 SwiftUI 运行时依赖）。
// NSApplicationDelegate 是 weak 引用，必须用全局强引用持有，
// 否则 applicationDidFinishLaunching 回调前 delegate 被释放导致窗口不创建。
let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
app.run()
