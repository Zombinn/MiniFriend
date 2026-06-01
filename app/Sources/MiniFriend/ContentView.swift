import SwiftUI

// 灵动岛主视图。岛区固定在窗口顶部居中；窗口其余为透明、不拦截鼠标。
// 悬停展开、移出收起；紧凑态头像在刘海左、运行灯在刘海右。
struct ContentView: View {
    @EnvironmentObject var vm: ChatViewModel
    @StateObject private var speech = SpeechRecognizer()
    @ObservedObject private var config = AppConfig.shared
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool
    @State private var m = NotchMetrics.current()

    // 展开宽度 = 收起宽度（只向下生长，宽度不变）
    private var expandedW: CGFloat { m.notchWidth + lobe * 2 + 36 }

    private var topR: CGFloat { vm.expanded ? 12 : 8 }
    private var botR: CGFloat { vm.expanded ? 22 : 12 }

    var body: some View {
        // 背景与裁剪跟随内容尺寸自适应：收起=刘海两侧内容，展开=对话内容高度
        islandContent
            .background(NotchShape(topCornerRadius: topR, bottomCornerRadius: botR).fill(.black))
            .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: botR))
            .shadow(color: .black.opacity(vm.expanded ? 0.45 : 0.2),
                    radius: vm.expanded ? 12 : 4, y: 3)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: vm.expanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)  // 窗口内居中贴顶
    }

    @ViewBuilder private var islandContent: some View {
        if vm.expanded {
            expanded.transition(.opacity)
        } else {
            compact.transition(.opacity)
        }
    }

    private let lobe: CGFloat = 48          // 刘海两侧探出区宽
    private var compactH: CGFloat { m.notchHeight + 12 }   // 略高于刘海，头像完整露出

    // 紧凑：头部 chibi 在刘海左、运行灯在刘海右，中间留出刘海
    private var compact: some View {
        HStack(spacing: 0) {
            PixelAvatar(size: compactH * 0.94, speaking: vm.isSpeaking, thinking: vm.isResponding,
                        resource: "avatar_head")
                .frame(width: lobe)
            Spacer().frame(width: m.notchWidth)
            RunningLight(speaking: vm.isSpeaking, thinking: vm.isResponding, warming: vm.isWarmingUp)
                .frame(width: lobe)
        }
        .frame(height: compactH)
        .padding(.horizontal, 18)      // 避开 NotchShape 顶部凹角，左右内容不被裁
    }

    // 展开：头像 + 状态 + 对话 + 输入
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PixelAvatar(size: 52, speaking: vm.isSpeaking, thinking: vm.isResponding,
                            resource: "avatar_pixel")
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView(config: config)
                }
                .onChange(of: showSettings) { _, open in
                    vm.pinned = open                 // 设置打开时钉住，不自动收起
                    if open { vm.expand() } else { vm.collapseSoon() }
                }
                RunningLight(speaking: vm.isSpeaking, thinking: vm.isResponding, warming: vm.isWarmingUp)
            }
            if !vm.messages.isEmpty { transcript }
            inputBar
        }
        .padding(.top, m.notchHeight + 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(width: expandedW, alignment: .leading)
    }

    private var statusText: String {
        if vm.isResponding { return "思考中…" }
        if vm.isSpeaking { return "说话中…" }
        return config.name
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(vm.messages) { msg in
                        Text(msg.text.isEmpty && msg.role == .assistant ? "…" : msg.text)
                            .font(.system(size: 12))
                            .foregroundStyle(msg.role == .user ? .white.opacity(0.55) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(msg.id)
                    }
                }
            }
            .frame(height: 70)
            .onChange(of: vm.messages.last?.text) { _, _ in
                if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                // 展开时自动滚到最新消息，避免每次展开都回到顶部
                if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Button {
                speech.toggle()
                if speech.isListening { vm.expand() }
            } label: {
                Image(systemName: speech.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 14))
                    .foregroundStyle(speech.isListening ? .red : .white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("按一下开始/结束语音输入")

            TextField(speech.isListening ? "聆听中…" : "和\(config.name)说点什么…", text: $vm.input)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .onSubmit { vm.send() }
                .onChange(of: speech.transcript) { _, t in
                    if !t.isEmpty { vm.input = t }   // 识别结果实时填入
                }
            Button(action: vm.send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(vm.input.isEmpty ? .gray : .cyan)
            }
            .buttonStyle(.plain)
            .disabled(vm.input.isEmpty || vm.isResponding)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.12)))
    }
}

// 运行指示灯：常亮=运行中（绿）；思考=黄；说话=青；激活时呼吸脉动。
struct RunningLight: View {
    let speaking: Bool
    let thinking: Bool
    var warming: Bool = false
    @State private var pulse = false

    var body: some View {
        let color: Color = warming ? .orange : (speaking ? .cyan : (thinking ? .yellow : .green))
        let active = !warming && (speaking || thinking)
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.9), radius: pulse && active ? 5 : 2)
            .scaleEffect(active && pulse ? 1.4 : 1.0)
            .animation(active
                ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                : .default,
                       value: pulse)
            .onAppear { pulse = true }
    }
}
