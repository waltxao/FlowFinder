import AppKit

/// 每窗口的落点几何缓存。
/// 拖动开始时刷新一次；拖动中只读，不做视图命中测试。
final class FFDragGeometryCache {

    private var geometries: [ObjectIdentifier: FFWindowDropGeometry] = [:]

    func update(for controller: MainWindowController) {
        guard let geometry = controller.dragGeometry() else {
            geometries.removeValue(forKey: ObjectIdentifier(controller))
            return
        }
        geometries[geometry.windowID] = geometry
    }

    func remove(_ controller: MainWindowController) {
        geometries.removeValue(forKey: ObjectIdentifier(controller))
    }

    /// 按窗口层级从前到后返回；重叠窗口取最上面的。
    func all() -> [FFWindowDropGeometry] {
        let orderedIDs = NSApp.orderedWindows.compactMap { window -> ObjectIdentifier? in
            guard let controller = window.windowController as? MainWindowController else { return nil }
            return ObjectIdentifier(controller)
        }
        let ordered = orderedIDs.compactMap { geometries[$0] }
        let orderedSet = Set(orderedIDs)
        let remaining = geometries.values.filter { !orderedSet.contains($0.windowID) }
        return ordered + remaining
    }
}
