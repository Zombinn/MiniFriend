> [中文](README.md) · **English** · [한국어](README.ko.md) · [日本語](README.ja.md)

# MiniFriend

macOS Dynamic Island-style floating desktop AI assistant. Snaps to the notch, expands on hover, supports voice input/output, local/remote model switching, customizable persona, and pixel-art avatar.

---

## Features

- **Dynamic Island UI**: Snaps to the MacBook notch, expands on hover / collapses on leave, blends into the notch with a black background
- **Conversation Backend**: Supports both Claude (remote) and Ollama (local, fully offline) — switch anytime
- **Voice Output**: VoxCPM-0.5B + personal LoRA fine-tuned voice, ONNX-accelerated DiT, sentence-by-sentence audio-visual sync
- **Voice Input**: Apple Speech STT, click the mic button to speak and convert to text
- **Pixel Avatar**: Codex Pets-style chibi avatar with procedural breathing/thinking/speaking animations
- **Local Memory**: Ollama conversation history persisted to disk, continues after restart
- **Settings Panel**: Assistant name, persona, model selection, TTS toggle, Ollama parameters — all saved in real time

---

## Architecture

```
MiniFriend/
├── app/                    # macOS SwiftUI Client
│   ├── Sources/MiniFriend/
│   │   ├── main.swift          # Entry point, AppDelegate
│   │   ├── ContentView.swift   # Dynamic Island UI
│   │   ├── ChatViewModel.swift # Conversation state management
│   │   ├── ClaudeClient.swift  # Claude CLI interface
│   │   ├── OllamaClient.swift  # Ollama local model interface
│   │   ├── VoiceClient.swift   # TTS client, pipeline sentence playback
│   │   ├── SpeechRecognizer.swift # STT (Apple Speech)
│   │   ├── VoiceServer.swift   # Voice service process management
│   │   ├── HoverMonitor.swift  # Global mouse event listener
│   │   ├── AppConfig.swift     # Configuration persistence
│   │   ├── SettingsView.swift  # Settings panel
│   │   ├── PixelAvatar.swift   # Pixel avatar animation
│   │   ├── NotchShape.swift    # Dynamic Island shape
│   │   ├── FloatingPanel.swift # Floating window
│   │   └── Resources/          # Pixel avatar assets
│   ├── Info.plist              # Microphone / Speech recognition permissions
│   ├── Package.swift
│   └── package_app.sh          # Build & package script
│
├── voice-service/          # Python TTS Service (FastAPI, port 8765)
│   ├── app.py              # FastAPI main service, includes warmup
│   ├── config.py           # Environment variable configuration
│   ├── backends/
│   │   ├── voxcpm_backend.py   # VoxCPM + ONNX DiT acceleration
│   │   └── base.py
│   ├── lora/               # Personal voice LoRA (not included in repo)
│   │   ├── lora_config.json
│   │   └── lora_weights.safetensors  # Must be trained yourself
│   └── requirements.txt
│
├── finetune/               # LoRA fine-tuning scripts (run on cloud GPU)
│   ├── prepare_data.py     # Audio slicing + Whisper transcription
│   ├── voxcpm_finetune_lora.yaml
│   └── run_finetune.sh
│
└── avatar/                 # Avatar generation scripts
    └── stylize_pixel.py    # Photo → chibi pixel character
```

---

## Quick Start

### Prerequisites

- macOS 14+ (Apple Silicon)
- Xcode Command Line Tools
- Python 3.10+ (Anaconda recommended)
- Claude Code CLI (`~/.local/bin/claude`) or Ollama

### 1. Voice Service

```bash
cd voice-service
pip install -r requirements.txt
python app.py          # Auto-warmup on startup, ~20s to ready
```

The service listens on `http://127.0.0.1:8765` and provides a `POST /tts` endpoint.

### 2. Build & Run the App

```bash
cd app
./package_app.sh       # Compile + package into MiniFriend.app (includes entitlement signing)
open MiniFriend.app    # Double-click or launch from CLI
```

> ⚠️ Must use `open MiniFriend.app` — do not use `swift run` (microphone permission requires the .app bundle)

### 3. Personal Voice LoRA (Optional)

Use default zero-shot cloning (requires a reference audio) or train a personal LoRA:

```bash
# On a cloud GPU (RTX 3090/4090+, CUDA 12)
cd finetune
# 1. Prepare data (your_audio.wav can be a single file or directory)
python prepare_data.py --src your_audio.wav --out /workspace/data --lang zh

# 2. Train (~30-60 minutes)
python scripts/train_voxcpm_finetune.py --config_path voxcpm_finetune_lora.yaml

# 3. Download lora_config.json + lora_weights.safetensors from latest/ to voice-service/lora/
```

---

## Configuration

All settings can be modified through the in-app gear icon, persisted to:
```
~/Library/Application Support/MiniFriend/config.json
```

| Setting | Description |
|---|---|
| Assistant Name | Appears in UI and system prompt |
| Persona | Appended to system prompt, influences reply style |
| Conversation Model | Claude (remote) or Ollama (local offline) |
| Ollama Model | e.g. `qwen3.5:4b`, must `ollama pull` first |
| Context Window | 8192 recommended for M3 Air 16GB |
| Read Aloud | TTS toggle |
| Auto-Start Voice Service | Automatically launches the Python service on app start |

### Environment Variables (Voice Service)

| Variable | Default | Description |
|---|---|---|
| `MF_TTS_BACKEND` | `voxcpm` | TTS backend |
| `MF_VOXCPM_MODEL` | `openbmb/VoxCPM-0.5B` | Base model |
| `MF_VOXCPM_DEVICE` | `cpu` | Inference device |
| `MF_VOXCPM_LORA` | `voice-service/lora` | LoRA directory |
| `MF_HOST` | `127.0.0.1` | Service host |
| `MF_PORT` | `8765` | Service port |

---

## Local Model (Ollama)

```bash
# Install Ollama
brew install ollama
ollama serve

# Recommended model (coexists with VoxCPM on M3 Air 16GB)
ollama pull qwen3.5:4b   # 3.4GB, supports think:false, good anti-repetition
```

Switch to "Local Model" in the app settings panel and enter the model name. Fully offline — conversation data never leaves your machine.

---

## Technical Details

### Voice Synthesis Acceleration
- VoxCPM DiT component exported as ONNX, 2.4× inference speedup
- `inference_timesteps=6` for balanced quality and speed (~5-6s/sentence)
- FastAPI serial lock prevents audio corruption from concurrent synthesis
- Silent warmup on startup eliminates cold-start delay on the first sentence

### Dynamic Island Interaction
- Global `NSEvent` mouse listener (inspired by DynamicNotchKit / NotchDrop)
- Auto-collapse blocked during three states: responding, speaking, or synthesizing
- `isPreparingVoice` eliminates the collapse gap between "text generation done" and "speaking begins"

### Conversation Isolation
- Claude: Multi-turn context preserved via `--resume session_id`, sessions stored in `~/.claude/projects/-/`
- Ollama: Messages array maintained in memory + persisted to disk, capped at 10 turns to avoid overflowing KV Cache

---

## License

MIT
