import Foundation

// 底层对话：spawn `claude -p ... --output-format stream-json`，流式解析回复。
// 维持会话用 session_id + --resume，使多轮对话保留上下文。
// 工作目录设为项目根，让 cowork / claude code 的工具能力可用。
final class ClaudeClient {
    private let executable: String
    private let workingDir: String
    private var sessionID: String?

    init(executable: String? = nil, workingDir: String? = nil) {
        self.executable = executable ?? Self.findClaude()
        self.workingDir = workingDir ?? FileManager.default.currentDirectoryPath
    }

    static func findClaude() -> String {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    // onChunk: 流式文本片段；onComplete: 结束（带可能的错误）。
    func send(_ prompt: String,
              onChunk: @escaping (String) -> Void,
              onComplete: @escaping (Error?) -> Void) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)

        var args = ["-p", prompt,
                    "--append-system-prompt", AppConfig.shared.systemPrompt,
                    "--output-format", "stream-json", "--verbose"]
        if let sid = sessionID {
            args += ["--resume", sid]
        }
        proc.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var buffer = Data()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            // 按行（NDJSON）切分
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                self?.handleLine(lineData, onChunk: onChunk)
            }
        }

        proc.terminationHandler = { _ in
            outPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { onComplete(nil) }
        }

        do {
            try proc.run()
        } catch {
            onComplete(error)
        }
    }

    private func handleLine(_ data: Data, onChunk: @escaping (String) -> Void) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        if let sid = obj["session_id"] as? String { sessionID = sid }

        switch type {
        case "assistant":
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content where block["type"] as? String == "text" {
                    if let text = block["text"] as? String {
                        DispatchQueue.main.async { onChunk(text) }
                    }
                }
            }
        default:
            break
        }
    }

    func resetSession() { sessionID = nil }
}
