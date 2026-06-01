import AppKit
import SwiftUI

// 刘海几何信息。
struct NotchMetrics {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screen: NSScreen

    static func current() -> NotchMetrics {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        var h = screen.safeAreaInsets.top
        if h <= 0 {
            h = screen.frame.height - screen.visibleFrame.height
                - (screen.visibleFrame.minY - screen.frame.minY)   // 菜单栏高度
        }
        var w: CGFloat = 200
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            w = screen.frame.width - l.width - r.width
        }
        return NotchMetrics(notchWidth: max(w, 150), notchHeight: max(h, 32), screen: screen)
    }
}

// 灵动岛承载窗口：固定占据屏幕顶部一块区域，顶边贴屏幕物理顶端、水平居中。
// 岛区由 SwiftUI 画在顶部中央，空白区透明且不拦截鼠标（点击穿透）。
final class FloatingPanel: NSPanel {
    init<V: View>(view: V) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .screenSaver                       // 高于菜单栏，盖住刘海区
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                          // 阴影在 SwiftUI 里画
        hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: view)
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // 固定到屏幕顶部中央的承载区（足够容纳展开态）。
    func positionAtTop() {
        let f = (NSScreen.main ?? NSScreen.screens.first!).frame
        let w: CGFloat = min(640, f.width)
        let h: CGFloat = 280
        setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), display: true)
    }
}
