import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role { case user, assistant }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isResponding: Bool = false       // Claude 正在生成文字
    @Published var isSpeaking: Bool = false         // 正在用你的音色朗读
    @Published var isPreparingVoice: Bool = false   // 合成中（回复完成→首句出声之间的空窗）
    @Published var isWarmingUp: Bool = false        // 语音服务启动中，灯不闪
    @Published var expanded: Bool = false        // 灵动岛是否展开
    @Published var pinned: Bool = false          // 钉住（如设置面板打开时），期间不自动收起

    private let claude = ClaudeClient()
    private let ollama = OllamaClient()
    private let voice = VoiceClient()
    private var collapseTask: DispatchWorkItem?
    private var streamBuffer = ""     // 生成中先缓存全文，朗读时再逐句显示

    // MARK: - 灵动岛展开/收起

    func expand() {
        collapseTask?.cancel()
        if !expanded { expanded = true }
    }

    /// 空闲一段时间后自动收起（无输入、未在响应/说话时）。
    func collapseSoon(after seconds: Double = 4) {
        collapseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isResponding, !self.isSpeaking, !self.isPreparingVoice, !self.pinned,
               self.input.trimmingCharacters(in: .whitespaces).isEmpty {
                self.expanded = false
            }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    // MARK: - 对话

    func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        input = ""
        expand()
        messages.append(ChatMessage(role: .user, text: prompt))
        let assistantIndex = messages.count
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true
        streamBuffer = ""
        let voiceOn = AppConfig.shared.voiceEnabled

        // 按配置选择对话后端
        let sendFn: (String, @escaping (String)->Void, @escaping (Error?)->Void) -> Void
        if AppConfig.shared.modelBackend == .ollama {
            sendFn = { [weak self] p, chunk, done in self?.ollama.send(p, onChunk: chunk, onComplete: done) }
        } else {
            sendFn = { [weak self] p, chunk, done in self?.claude.send(p, onChunk: chunk, onComplete: done) }
        }

        sendFn(prompt, { [weak self] chunk in
            guard let self else { return }
            self.streamBuffer += chunk
            if !voiceOn { self.messages[assistantIndex].text = self.streamBuffer }
        }, { [weak self] _ in
            guard let self else { return }
            self.isResponding = false
            let reply = self.streamBuffer
            guard !reply.isEmpty else { self.collapseSoon(); return }
            guard voiceOn else {
                self.messages[assistantIndex].text = reply
                self.collapseSoon(); return
            }
            // 声画同步：清空文字，哪句开始播就显示哪句
            self.messages[assistantIndex].text = ""
            self.isPreparingVoice = true       // 合成期间保持展开
            self.voice.speak(reply, onSentenceStart: { [weak self] s in
                self?.messages[assistantIndex].text += s
            }, onStart: { [weak self] in
                self?.isPreparingVoice = false
                self?.isSpeaking = true
            }, onFinish: { [weak self] in
                self?.isSpeaking = false
                self?.collapseSoon()
            })
        })
    }
}
