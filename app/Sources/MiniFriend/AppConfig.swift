import Foundation

enum ModelBackend: String, Codable, CaseIterable {
    case claude = "claude"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .claude: return "Claude (远程)"
        case .ollama: return "本地模型 (Ollama)"
        }
    }
}

// 助手的可配置属性，持久化到 ~/Library/Application Support/MiniFriend/config.json。
final class AppConfig: ObservableObject {
    static let shared = AppConfig.load()

    @Published var name: String          { didSet { save() } }
    @Published var persona: String       { didSet { save() } }
    @Published var voiceEnabled: Bool    { didSet { save() } }
    @Published var autoStartVoice: Bool  { didSet { save() } }
    @Published var cfgValue: Double      { didSet { save() } }

    // 模型选择
    @Published var modelBackend: ModelBackend { didSet { save() } }
    @Published var ollamaHost: String    { didSet { save() } }   // e.g. http://localhost:11434
    @Published var ollamaModel: String   { didSet { save() } }   // e.g. qwen3:8b
    @Published var ollamaNumCtx: Int     { didSet { save() } }   // 上下文窗口，4096 省内存
    @Published var ollamaMaxTokens: Int  { didSet { save() } }   // 单次最大回复 token
    @Published var ollamaDisableThinking: Bool { didSet { save() } } // qwen3 等默认开思维链，聊天场景关掉

    init(name: String = "小助手", persona: String = "",
         voiceEnabled: Bool = true, autoStartVoice: Bool = true, cfgValue: Double = 2.0,
         modelBackend: ModelBackend = .claude,
         ollamaHost: String = "http://localhost:11434",
         ollamaModel: String = "qwen3.5:4b",
         ollamaNumCtx: Int = 8192,
         ollamaMaxTokens: Int = 512,
         ollamaDisableThinking: Bool = true) {
        self.name = name
        self.persona = persona
        self.voiceEnabled = voiceEnabled
        self.autoStartVoice = autoStartVoice
        self.cfgValue = cfgValue
        self.modelBackend = modelBackend
        self.ollamaHost = ollamaHost
        self.ollamaModel = ollamaModel
        self.ollamaNumCtx = ollamaNumCtx
        self.ollamaMaxTokens = ollamaMaxTokens
        self.ollamaDisableThinking = ollamaDisableThinking
    }

    var systemPrompt: String {
        var s = "你的名字叫\(name)。严格遵守：口语化，严禁重复已说过的内容，严禁啰嗦，不要列点，因为回复会被语音播报。"
        if !persona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s += "\n人设：\(persona)"
        }
        return s
    }

    // MARK: - 持久化

    private struct Stored: Codable {
        var name: String; var persona: String; var voiceEnabled: Bool
        var autoStartVoice: Bool?; var cfgValue: Double
        var modelBackend: String?; var ollamaHost: String?; var ollamaModel: String?
        var ollamaNumCtx: Int?; var ollamaMaxTokens: Int?; var ollamaDisableThinking: Bool?
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniFriend", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else {
            return AppConfig()
        }
        let backend = ModelBackend(rawValue: s.modelBackend ?? "claude") ?? .claude
        return AppConfig(name: s.name, persona: s.persona,
                         voiceEnabled: s.voiceEnabled,
                         autoStartVoice: s.autoStartVoice ?? true,
                         cfgValue: s.cfgValue,
                         modelBackend: backend,
                         ollamaHost: s.ollamaHost ?? "http://localhost:11434",
                         ollamaModel: s.ollamaModel ?? "qwen3:8b",
                         ollamaNumCtx: s.ollamaNumCtx ?? 4096,
                         ollamaMaxTokens: s.ollamaMaxTokens ?? 512,
                         ollamaDisableThinking: s.ollamaDisableThinking ?? true)
    }

    func save() {
        let s = Stored(name: name, persona: persona, voiceEnabled: voiceEnabled,
                       autoStartVoice: autoStartVoice, cfgValue: cfgValue,
                       modelBackend: modelBackend.rawValue,
                       ollamaHost: ollamaHost, ollamaModel: ollamaModel,
                       ollamaNumCtx: ollamaNumCtx, ollamaMaxTokens: ollamaMaxTokens,
                       ollamaDisableThinking: ollamaDisableThinking)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: Self.fileURL)
        }
    }
}
