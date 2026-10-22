import CoreGraphics

/// 一次拖动的源标签。
struct FFDragSource {
    let windowID: ObjectIdentifier
    let side: PaneSide
    let index: Int
}

/// 一个标签条在屏幕坐标下的几何。
struct FFTabStripGeometry {
    let rect: CGRect
    let tabRects: [CGRect]
}

/// 一个面板卡片在屏幕坐标下的几何。
struct FFPaneGeometry {
    let rect: CGRect
    let realTabCount: Int
}

/// 一个窗口参与落点判定的全部几何。
struct FFWindowDropGeometry {
    let windowID: ObjectIdentifier
    let frame: CGRect
    let isSinglePane: Bool
    let activePane: PaneSide
    let tabStrips: [PaneSide: FFTabStripGeometry]
    let paneContents: [PaneSide: FFPaneGeometry]
    let invalidRects: [CGRect]
}

enum FFDropDecision: Equatable {
    case reorder(windowID: ObjectIdentifier, side: PaneSide, index: Int)
    case merge(windowID: ObjectIdentifier, side: PaneSide, index: Int?)
    case split(windowID: ObjectIdentifier, dropSide: PaneSide)
    case newWindow
    case returnToSource
}

enum FFDropResolver {
    static let stripBuffer: CGFloat = 20

    static func resolve(source: FFDragSource,
                        pointer: CGPoint,
                        geometries: [FFWindowDropGeometry]) -> FFDropDecision {
        guard let window = geometries.first(where: { $0.frame.contains(pointer) }) else {
            return .newWindow
        }

        // 先判无效区：侧栏/红绿灯/“+”即使压在标签条矩形里也不能算落点。
        if window.invalidRects.contains(where: { $0.contains(pointer) }) {
            return .returnToSource
        }

        for side in PaneSide.allCases {
            guard let strip = window.tabStrips[side] else { continue }
            let zone = strip.rect.insetBy(dx: -stripBuffer, dy: -stripBuffer)
            guard zone.contains(pointer) else { continue }
            let index = insertionIndex(pointerX: pointer.x, tabRects: strip.tabRects)
            if window.windowID == source.windowID && side == source.side {
                return .reorder(windowID: window.windowID, side: side, index: index)
            }
            return .merge(windowID: window.windowID, side: side, index: index)
        }

        if window.isSinglePane {
            guard let pane = window.paneContents[window.activePane],
                  pane.rect.contains(pointer) else {
                return .returnToSource
            }
            // 同一面板只剩被拖的这一个标签：拖回自己不算拆分。
            if window.windowID == source.windowID,
               source.side == window.activePane,
               pane.realTabCount <= 1 {
                return .returnToSource
            }
            // 目标只有占位标签：填回现有面板，不拆出一个空面板。
            if pane.realTabCount == 0 {
                return .merge(windowID: window.windowID, side: window.activePane, index: nil)
            }
            let dropSide: PaneSide = pointer.x < pane.rect.midX ? .left : .right
            return .split(windowID: window.windowID, dropSide: dropSide)
        }

        for side in PaneSide.allCases {
            guard let pane = window.paneContents[side], pane.rect.contains(pointer) else { continue }
            if window.windowID == source.windowID && side == source.side {
                return .returnToSource
            }
            return .merge(windowID: window.windowID, side: side, index: nil)
        }

        return .returnToSource
    }

    private static func insertionIndex(pointerX: CGFloat, tabRects: [CGRect]) -> Int {
        guard !tabRects.isEmpty else { return 0 }
        for (index, rect) in tabRects.enumerated() where pointerX < rect.midX {
            return index
        }
        return tabRects.count
    }
}
