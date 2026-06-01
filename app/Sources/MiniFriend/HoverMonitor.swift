import AppKit

// 全局光标位置监听：判断鼠标是否在刘海热区，驱动灵动岛展开/收起。
// 比 SwiftUI .onHover 在非激活悬浮面板里可靠（参考 NotchDrop/DynamicNotchKit）。
final class HoverMonitor {
    private let vm: ChatViewModel
    private var globalMon: Any?
    private var localMon: Any?

    init(vm: ChatViewModel) {
        self.vm = vm
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.check() }
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { handler($0) }
        localMon = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in handler(e); return e }
    }

    // 收起态触发区（小，刘海药丸）；展开态保持区（大，整个面板）。
    private func rects() -> (collapsed: CGRect, expanded: CGRect) {
        let m = NotchMetrics.current()
        let f = m.screen.frame
        let lobe: CGFloat = 48
        let w = m.notchWidth + lobe * 2 + 36
        let cH = m.notchHeight + 12
        let eH: CGFloat = 210
        let collapsed = CGRect(x: f.midX - w / 2, y: f.maxY - cH, width: w, height: cH)
        // 保持区比面板略大，留点容错，避免移动中误收起
        let expanded = CGRect(x: f.midX - w / 2 - 8, y: f.maxY - eH - 8, width: w + 16, height: eH + 16)
        return (collapsed, expanded)
    }

    private func check() {
        let p = NSEvent.mouseLocation
        let (collapsed, expanded) = rects()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.vm.pinned { return }                    // 设置面板打开时钉住
            if self.vm.isResponding || self.vm.isSpeaking || self.vm.isPreparingVoice { return }
            if self.vm.expanded {
                if !expanded.contains(p) { self.vm.collapseSoon(after: 0.25) }
            } else if collapsed.contains(p) {
                self.vm.expand()
            }
        }
    }

    deinit {
        if let g = globalMon { NSEvent.removeMonitor(g) }
        if let l = localMon { NSEvent.removeMonitor(l) }
    }
}
