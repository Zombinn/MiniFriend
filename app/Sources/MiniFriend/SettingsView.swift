import SwiftUI

// 助手设置面板（齿轮弹出）。改动即时保存。
struct SettingsView: View {
    @ObservedObject var config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("助手设置").font(.system(size: 13, weight: .semibold))

            // 对话模型选择
            VStack(alignment: .leading, spacing: 4) {
                Text("对话模型").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: $config.modelBackend) {
                    ForEach(ModelBackend.allCases, id: \.self) { b in
                        Text(b.displayName).tag(b)
                    }
                }.pickerStyle(.segmented).labelsHidden()

                if config.modelBackend == .ollama {
                    TextField("Ollama 地址", text: $config.ollamaHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    TextField("模型名称（如 qwen2.5:7b）", text: $config.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("上下文窗口").font(.system(size: 10)).foregroundStyle(.secondary)
                            TextField("4096", value: $config.ollamaNumCtx, format: .number)
                                .textFieldStyle(.roundedBorder).font(.system(size: 11))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最大回复 token").font(.system(size: 10)).foregroundStyle(.secondary)
                            TextField("512", value: $config.ollamaMaxTokens, format: .number)
                                .textFieldStyle(.roundedBorder).font(.system(size: 11))
                        }
                    }
                    Toggle("关闭思维链（qwen3 等默认开启，聊天建议关）", isOn: $config.ollamaDisableThinking)
                        .font(.system(size: 11))
                    Text("M3 Air 16GB 同时跑 VoxCPM 建议 num_ctx ≤ 4096")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("名称").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("小助手", text: $config.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("人设 / 说话风格").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $config.persona)
                    .font(.system(size: 12))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                Text("例：温柔、爱用颜文字、回答简短")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Toggle("回复时朗读（你的音色）", isOn: $config.voiceEnabled)
                .font(.system(size: 12))

            if config.modelBackend == .ollama {
                Button {
                    OllamaClient.clearHistory()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("清空本地对话历史")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
            }

            Toggle("启动时自动开启语音服务", isOn: $config.autoStartVoice)
                .font(.system(size: 12))
                .onChange(of: config.autoStartVoice) { _, on in
                    if on { VoiceServer.shared.startIfNeeded() } else { VoiceServer.shared.stop() }
                }

            Divider()

            Button(role: .destructive) {
                VoiceServer.shared.stop()
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("退出 MiniFriend")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.85))
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 260)
    }
}
