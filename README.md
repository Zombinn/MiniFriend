> **[中文](README.md)** · [English](README.en.md) · [한국어](README.ko.md) · [日本語](README.ja.md)

# MiniFriend

macOS 灵动岛风格悬浮桌面 AI 助手。贴合刘海、鼠标悬停展开，支持语音输入输出、本地/远程模型切换、自定义人设与像素风形象。

## 功能

- **灵动岛 UI**：贴合 MacBook 刘海，悬停展开/移开收起，黑色融入刘海
- **对话后端**：支持 Claude（远程）和 Ollama（本地，完全离线）任意切换
- **语音输出**：VoxCPM-0.5B + 个人 LoRA 微调音色，ONNX 加速 DiT，逐句声画同步
- **语音输入**：Apple Speech STT，点击麦克风说话转文字
- **像素形象**：Codex Pets 风格 chibi 头像，程序化呼吸/思考/说话动画
- **本地记忆**：Ollama 对话历史持久化，重启后延续上下文
- **设置面板**：助手名称、人设、模型选择、TTS 开关、Ollama 参数，实时保存

## 架构

```
MiniFriend/
├── app/                    # macOS SwiftUI 客户端
│   ├── Sources/MiniFriend/
│   │   ├── main.swift          # 入口，AppDelegate
│   │   ├── ContentView.swift   # 灵动岛 UI
│   │   ├── ChatViewModel.swift # 对话状态管理
│   │   ├── ClaudeClient.swift  # Claude CLI 接口
│   │   ├── OllamaClient.swift  # Ollama 本地模型接口
│   │   ├── VoiceClient.swift   # TTS 客户端，流水线逐句播放
│   │   ├── SpeechRecognizer.swift # STT（Apple Speech）
│   │   ├── VoiceServer.swift   # 语音服务进程管理
│   │   ├── HoverMonitor.swift  # 全局鼠标监听
│   │   ├── AppConfig.swift     # 配置持久化
│   │   ├── SettingsView.swift  # 设置面板
│   │   ├── PixelAvatar.swift   # 像素形象动画
│   │   ├── NotchShape.swift    # 灵动岛形状
│   │   ├── FloatingPanel.swift # 浮动窗口
│   │   └── Resources/          # 像素头像资源
│   ├── Info.plist              # 麦克风/语音识别权限
│   ├── Package.swift
│   └── package_app.sh          # 打包脚本
│
├── voice-service/          # Python TTS 服务（FastAPI, 端口 8765）
│   ├── app.py              # FastAPI 主服务，含 warmup
│   ├── config.py           # 环境变量配置
│   ├── backends/
│   │   ├── voxcpm_backend.py   # VoxCPM + ONNX DiT 加速
│   │   └── base.py
│   ├── lora/               # 个人音色 LoRA（不含在仓库中）
│   │   ├── lora_config.json
│   │   └── lora_weights.safetensors  # 需自行训练
│   └── requirements.txt
│
├── finetune/               # LoRA 微调脚本（在云 GPU 上运行）
│   ├── prepare_data.py     # 音频切片 + Whisper 转录
│   ├── voxcpm_finetune_lora.yaml
│   └── run_finetune.sh
│
└── avatar/                 # 形象生成脚本
    └── stylize_pixel.py    # 照片 → chibi 像素小人
```

## 快速开始

### 依赖

- macOS 14+ (Apple Silicon)
- Xcode Command Line Tools
- Python 3.10+（推荐 Anaconda）
- Claude Code CLI（`~/.local/bin/claude`）或 Ollama

### 1. 语音服务

```bash
cd voice-service
pip install -r requirements.txt
python app.py          # 启动后自动 warmup，~20s 就绪
```

服务监听 `http://127.0.0.1:8765`，提供 `POST /tts` 接口。

### 2. 打包 & 运行 App

```bash
cd app
./package_app.sh       # 编译 + 打包成 MiniFriend.app（含权限签名）
open MiniFriend.app    # 双击或命令行启动
```

> ⚠️ 必须用 `open MiniFriend.app`，不能用 `swift run`（麦克风权限需要 .app 包）

### 3. 个人音色 LoRA（可选）

使用默认零样本克隆（需参考音频）或训练个人 LoRA：

```bash
# 在云 GPU 上（RTX 3090/4090 等，CUDA 12）
cd finetune
# 1. 准备数据（your_audio.wav 为录音文件或目录）
python prepare_data.py --src your_audio.wav --out /workspace/data --lang zh

# 2. 训练（约 30-60 分钟）
python scripts/train_voxcpm_finetune.py --config_path voxcpm_finetune_lora.yaml

# 3. 将 latest/ 目录下 lora_config.json + lora_weights.safetensors 下载到 voice-service/lora/
```

## 配置

所有设置通过 App 内齿轮按钮修改，持久化至：
```
~/Library/Application Support/MiniFriend/config.json
```

| 设置项 | 说明 |
|---|---|
| 助手名称 | 出现在 UI 和系统提示中 |
| 人设 | 追加到 system prompt，影响回复风格 |
| 对话模型 | Claude（远程）或 Ollama（本地离线）|
| Ollama 模型 | 如 `qwen3.5:4b`，需先 `ollama pull` |
| 上下文窗口 | M3 Air 16GB 建议 8192 |
| 回复时朗读 | TTS 开关 |
| 自动启动语音服务 | App 启动时自动拉起 Python 服务 |

### 环境变量（语音服务）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `MF_TTS_BACKEND` | `voxcpm` | TTS 后端 |
| `MF_VOXCPM_MODEL` | `openbmb/VoxCPM-0.5B` | 基座模型 |
| `MF_VOXCPM_DEVICE` | `cpu` | 推理设备 |
| `MF_VOXCPM_LORA` | `voice-service/lora` | LoRA 目录 |
| `MF_HOST` | `127.0.0.1` | 服务地址 |
| `MF_PORT` | `8765` | 服务端口 |

## 本地模型（Ollama）

```bash
# 安装 Ollama
brew install ollama
ollama serve

# 推荐模型（M3 Air 16GB + VoxCPM 共存）
ollama pull qwen3.5:4b   # 3.4GB，支持 think:false，防复读好
```

在 App 设置面板切换到「本地模型」，填写模型名即可。完全离线，对话数据不出本机。

## 技术细节

### 语音合成加速
- VoxCPM DiT 组件导出为 ONNX，推理速度 2.4×
- `inference_timesteps=6`，平衡质量与速度（~5-6s/句）
- FastAPI 串行锁防止并发合成导致的音频损坏
- 启动时静默 warmup，消除首句冷启动延迟

### 灵动岛交互
- 全局 `NSEvent` 鼠标监听（参考 DynamicNotchKit/NotchDrop）
- 回复/说话/合成中三个状态均阻止自动收起
- `isPreparingVoice` 消除"生成文字完成→开始说话"间的收起空窗

### 对话隔离
- Claude：通过 `--resume session_id` 保持多轮上下文，session 存于 `~/.claude/projects/-/`
- Ollama：messages 数组内存维护 + 磁盘持久化，最多保留 10 轮防止撑满 KV Cache

