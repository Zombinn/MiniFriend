import Foundation

// 本地模型对话客户端 —— Ollama /api/chat 真流式实现。
// 用 URLSessionDataDelegate 实时接收每一行 JSON，不等完整响应。
final class OllamaClient: NSObject {
    private var messages: [[String: Any]] = [] {
        didSet { saveHistory() }   // 每次消息变化自动保存到磁盘
    }

    // 对话历史持久化路径
    private static var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniFriend", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ollama_history.json")
    }

    override init() {
        super.init()
        loadHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        messages = arr
        NSLog("OllamaClient: 加载历史 \(arr.count) 条消息")
    }

    private func saveHistory() {
        guard let data = try? JSONSerialization.data(withJSONObject: messages) else { return }
        try? data.write(to: Self.historyURL)
    }

    // 当前请求的状态（每次 send 重置）
    private var onChunkCb: ((String) -> Void)?
    private var onCompleteCb: ((Error?) -> Void)?
    private var accumulated = ""
    private var lineBuffer = ""
    private var session: URLSession?
    private var task: URLSessionDataTask?

    func send(_ prompt: String,
              onChunk: @escaping (String) -> Void,
              onComplete: @escaping (Error?) -> Void) {
        // 取消上一个请求
        task?.cancel()

        let cfg = AppConfig.shared
        guard let url = URL(string: "\(cfg.ollamaHost)/api/chat") else {
            onComplete(NSError(domain: "OllamaClient", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "无效的 Ollama 地址"]))
            return
        }

        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "model": cfg.ollamaModel,
            "messages": buildMessages(systemPrompt: cfg.systemPrompt),
            "stream": true,
            "options": [
                "num_ctx": cfg.ollamaNumCtx,
                "num_predict": cfg.ollamaMaxTokens,
                "repeat_penalty": 1.15,   // 防复读核心参数
                "temperature": 0.7,
                "top_k": 40,
            ],
        ]
        if cfg.ollamaDisableThinking { body["think"] = false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        onChunkCb = onChunk
        onCompleteCb = onComplete
        accumulated = ""
        lineBuffer = ""

        log("send: model=\(cfg.ollamaModel) url=\(url) think=\(!cfg.ollamaDisableThinking)")

        let sess = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = sess
        task = sess.dataTask(with: req)
        task?.resume()
    }

    func resetSession() {
        task?.cancel()
        messages = []
        try? FileManager.default.removeItem(at: Self.historyURL)
    }

    /// 清空磁盘历史（供设置面板调用，不影响人设）
    static func clearHistory() {
        try? FileManager.default.removeItem(at: historyURL)
        NSLog("OllamaClient: 对话历史已清空")
    }

    private func buildMessages(systemPrompt: String) -> [[String: Any]] {
        var result: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        // 只保留最近 10 轮（20条消息），防止历史撑满上下文、遗忘人设
        let maxHistory = 20
        let trimmed = messages.count > maxHistory ? Array(messages.suffix(maxHistory)) : messages
        result.append(contentsOf: trimmed)
        return result
    }

    // 解析一行 JSON
    private func handleLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let msg = obj["message"] as? [String: Any],
           let content = msg["content"] as? String, !content.isEmpty {
            accumulated += content
            let chunk = content
            log("chunk: \(chunk.prefix(30))")
            DispatchQueue.main.async { self.onChunkCb?(chunk) }
        }

        if let done = obj["done"] as? Bool, done {
            log("done! accumulated=\(accumulated.prefix(50))")
            let full = accumulated
            if !full.isEmpty {
                messages.append(["role": "assistant", "content": full])
            }
            let cb = onCompleteCb
            onChunkCb = nil; onCompleteCb = nil
            DispatchQueue.main.async { cb?(nil) }
        }
    }
}

private func log(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/ollama_debug.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else { try? data.write(to: url) }
    }
}

extension OllamaClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { log("didReceive: no text"); return }
        log("didReceive \(data.count)B: \(text.prefix(100))")
        lineBuffer += text
        // 按换行切分，不完整的行留在 buffer
        var lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = lines.removeLast()   // 最后一个可能不完整
        for line in lines { handleLine(line) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        log("didComplete: error=\(error?.localizedDescription ?? "nil")")
        // 处理 buffer 里剩余内容
        if !lineBuffer.isEmpty { handleLine(lineBuffer); lineBuffer = "" }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            let cb = onCompleteCb; onCompleteCb = nil
            DispatchQueue.main.async { cb?(error) }
        } else if onCompleteCb != nil {
            // done:true 没触发（异常结束），也要回调
            let cb = onCompleteCb; onCompleteCb = nil
            DispatchQueue.main.async { cb?(nil) }
        }
    }
}
