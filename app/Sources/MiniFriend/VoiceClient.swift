import AVFoundation
import Foundation

// 把回复发给 /tts 用你的音色播放，并做到「声画同步」：
// - 按句切分；每句的音频开始播放时，回调 onSentenceStart 让 UI 显示这句文字
// - 流水线预取：播第 i 句时已在后台合成第 i+1,i+2 句，减少句间停顿
// - 首句就绪即播，不等全部合成完成
// 服务未启动时静默跳过。
final class VoiceClient: NSObject, AVAudioPlayerDelegate {
    private let endpoint: URL
    private var player: AVAudioPlayer?

    private var sentences: [String] = []
    private var prefetched: [Int: Data] = [:]
    private var attempted: Set<Int> = []          // 已完成合成（成功或失败），防无限重试
    private var fetching:  Set<Int> = []          // 进行中的请求，防止重复发起
    private var pendingCallbacks: [Int: [() -> Void]] = [:]  // 等待某句完成的回调队列
    private var idx = 0
    private var gen = 0
    private var started = false
    private var onSentence: ((String) -> Void)?
    private var onStartCb: (() -> Void)?
    private var onFinishCb: (() -> Void)?

    init(host: String = "127.0.0.1", port: Int = 8765) {
        self.endpoint = URL(string: "http://\(host):\(port)/tts")!
        super.init()
    }

    func speak(_ raw: String,
               onSentenceStart: @escaping (String) -> Void = { _ in },
               onStart: @escaping () -> Void = {},
               onFinish: @escaping () -> Void = {}) {
        stop()
        let s = Self.sentences(from: Self.sanitize(raw))
        guard !s.isEmpty else { onFinish(); return }
        gen += 1
        let g = gen
        sentences = s; idx = 0; prefetched = [:]; attempted = []; fetching = []; pendingCallbacks = [:]; started = false
        onSentence = onSentenceStart; onStartCb = onStart; onFinishCb = onFinish
        // 先预取第 0 句，合成完成立即开始播放
        fetch(0, g) { [weak self] in self?.play(0, g) }
    }

    func stop() {
        gen += 1
        player?.stop(); player = nil
        sentences = []; prefetched = [:]; attempted = []; fetching = []; pendingCallbacks = [:]
        onSentence = nil; onStartCb = nil; onFinishCb = nil
    }

    // MARK: - 流水线

    /// 预取第 i 句，并且在后台额外预取后续的 prefetchAhead 句
    private let prefetchAhead = 2   // 播 i 时并行预取 i+1, i+2

    private func fetch(_ i: Int, _ g: Int, then: (() -> Void)? = nil) {
        guard g == gen, i < sentences.count else { then?(); return }

        // 先请求当前句
        if prefetched[i] != nil || attempted.contains(i) {
            then?()                                        // 已完成 → 直接回调
        } else if fetching.contains(i) {
            // 请求在途：把 then 挂到等待队列，完成后统一触发
            if let cb = then { pendingCallbacks[i, default: []].append(cb) }
        } else {
            fetching.insert(i)
            fetchTTS(sentences[i]) { [weak self] data in
                guard let self, g == self.gen else { return }
                self.fetching.remove(i)
                self.attempted.insert(i)
                if let data { self.prefetched[i] = data }
                then?()
                // 触发所有等待这句完成的回调（比如 play 在预取途中调用了 fetch）
                let callbacks = self.pendingCallbacks.removeValue(forKey: i) ?? []
                callbacks.forEach { $0() }
            }
        }

        // 后台并行预取后续句，用 fetching 防重复，绝不提前标记 attempted
        for ahead in 1...prefetchAhead {
            let j = i + ahead
            guard j < sentences.count,
                  prefetched[j] == nil,
                  !attempted.contains(j),
                  !fetching.contains(j) else { continue }
            fetching.insert(j)
            fetchTTS(sentences[j]) { [weak self] data in
                guard let self, g == self.gen else { return }
                self.fetching.remove(j)
                self.attempted.insert(j)
                if let data { self.prefetched[j] = data }
                // 触发等待这句的回调（play 在预取途中挂进来的）
                let cbs = self.pendingCallbacks.removeValue(forKey: j) ?? []
                cbs.forEach { $0() }
            }
        }
    }

    private func play(_ i: Int, _ g: Int) {
        guard g == gen else { return }
        guard i < sentences.count else {
            let f = onFinishCb; onFinishCb = nil
            DispatchQueue.main.async { f?() }
            return
        }
        let text = sentences[i]
        if let data = prefetched[i] {                        // 已合成好：播放
            if !started { started = true; let s = onStartCb; DispatchQueue.main.async { s?() } }
            DispatchQueue.main.async { [weak self] in self?.onSentence?(text) }
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                player = p; idx = i
                p.play()
            } catch {
                play(i + 1, g); return
            }
            fetch(i + 1, g)                                  // 边播边触发下一批预取
            return
        }
        if attempted.contains(i) {                           // 合成失败：显示文字、跳过这句
            if !started { started = true; let s = onStartCb; DispatchQueue.main.async { s?() } }
            DispatchQueue.main.async { [weak self] in self?.onSentence?(text) }
            play(i + 1, g)
            return
        }
        fetch(i, g) { [weak self] in self?.play(i, g) }      // 还没合成：合成完再播
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        play(idx + 1, gen)
    }

    private func fetchTTS(_ text: String, completion: @escaping (Data?) -> Void) {
        // sanitize 后可能变空字符串（全英文/路径被过滤），直接跳过避免服务卡死
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(nil); return
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90      // CPU 合成最慢约 15-20s，留足余量
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        URLSession.shared.dataTask(with: req) { data, response, error in
            guard let data, error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let error { NSLog("VoiceClient 跳过: \(error.localizedDescription)") }
                completion(nil); return
            }
            completion(data)
        }.resume()
    }

    // MARK: - 文本清洗 / 切句（保留句末标点，文字显示更自然）

    static func sanitize(_ text: String) -> String {
        var s = text
        func strip(_ p: String, _ r: String = "") {
            if let re = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r)
            }
        }
        // 先整体清理
        strip("```.*?```")                              // 代码块
        strip("`[^`]*`", "")                            // 行内代码
        strip("!?\\[([^\\]]*)\\]\\([^)]*\\)", "$1")    // markdown 链接取文字
        strip("https?://\\S+", "")                     // URL
        strip("/(?:[\\w.~@-]+/)+[\\w.~@.-]*", "")     // 文件路径
        strip("[*_#>|\\[\\]\\\\]", "")                 // markdown 符号

        // 只保留中文字符 + 常用标点 + 空格，过滤路径/英文等不适合朗读的内容
        let keepSet: Set<Character> = Set("，。！？、；：\u{201C}\u{201D}\u{2018}\u{2019}（）【】《》\u{2026}—～·「」『』\n ")
        s = s.filter { ch in
            if let scalar = ch.unicodeScalars.first {
                let v = scalar.value
                if v >= 0x4E00 && v <= 0x9FFF { return true }
                if v >= 0x3000 && v <= 0x303F { return true }
                if v >= 0xFF00 && v <= 0xFFEF { return true }
            }
            return keepSet.contains(ch)
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sentences(from text: String) -> [String] {
        // 一级：按句末标点切（含中文波浪号、省略号、破折号等）
        var raw: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if "。！？!?\n～…—".contains(ch) {
                let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { raw.append(t) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { raw.append(tail) }

        // 二级：过长的句子按逗号再切，单段控制在 ~30 字内
        // 更短的句子 = 更快的单句合成 + 更低的卡死风险
        let maxLen = 30
        var out: [String] = []
        for s in raw {
            if s.count <= maxLen { out.append(s); continue }
            var chunk = ""
            for ch in s {
                chunk.append(ch)
                if "，,、；;".contains(ch), chunk.count >= maxLen / 2 {
                    out.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines)); chunk = ""
                }
            }
            let r = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty { out.append(r) }
        }
        return out
    }
}
