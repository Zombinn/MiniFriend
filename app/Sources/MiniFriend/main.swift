import AppKit
import SwiftUI

// MiniFriend：贴刘海的灵动岛式桌面小助手入口。
// .accessory 策略 —— 无 Dock 图标、无主菜单。窗口固定贴刘海，
// 岛区展开/收起完全由 SwiftUI 在窗口内动画，无需调整窗口尺寸。

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var vm: ChatViewModel!
    private var hover: HoverMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        vm = ChatViewModel()
        let root = ContentView().environmentObject(vm)
        panel = FloatingPanel(view: root)
        panel.positionAtTop()
        panel.orderFrontRegardless()
        hover = HoverMonitor(vm: vm)        // 全局光标监听驱动展开/收起

        if AppConfig.shared.autoStartVoice {
            vm.isWarmingUp = true
            VoiceServer.shared.startIfNeeded()
            // 轮询直到 warmup 完成，完成后关掉闪烁
            pollWarmup()
        }
    }

    private func pollWarmup() {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let ready = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["status"] as? String == "ok"
            DispatchQueue.main.asyncAfter(deadline: .now() + (ready ? 0 : 2)) {
                if ready {
                    // 再等 warmup 合成完（health ok 但还在跑 synthesize，额外等 20s 保守）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                        self?.vm.isWarmingUp = false
                    }
                } else {
                    self?.pollWarmup()
                }
            }
        }.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VoiceServer.shared.stop()              // 退出时关闭自己拉起的服务
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
