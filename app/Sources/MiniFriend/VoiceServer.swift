import AppKit
import Foundation

// 随 app 生命周期托管 Python 语音服务（voice-service/app.py）：
// 启动时自动拉起（若端口未占用），app 退出时自动结束。
// 这样用户不必手动开终端跑 python app.py。
final class VoiceServer {
    static let shared = VoiceServer()

    private var process: Process?
    private let host = "127.0.0.1"
    private let port = 8765

    // 候选 python 解释器（需含 voxcpm/fastapi/uvicorn）
    private static let pythonCandidates = [
        "/opt/homebrew/anaconda3/bin/python",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    // voice-service 目录：优先项目源码路径，其次 app 同级
    private static func serviceDir() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/Public/Zyb_Boxes/MiniFriend/voice-service",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: "\($0)/app.py") }
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// 启动服务（若端口已被占用则认为已在跑，不重复启动）。
    func startIfNeeded() {
        if portOpen() { NSLog("VoiceServer: 端口已占用，复用现有服务"); return }
        guard let dir = Self.serviceDir() else { NSLog("VoiceServer: 找不到 voice-service 目录"); return }
        guard let py = Self.pythonCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { NSLog("VoiceServer: 找不到 python"); return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = ["app.py"]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            process = p
            NSLog("VoiceServer: 已启动 (\(py) app.py @ \(dir))")
        } catch {
            NSLog("VoiceServer 启动失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        process = nil
    }

    private func portOpen() -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }
}
