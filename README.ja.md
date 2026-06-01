> [中文](README.md) · [English](README.en.md) · [한국어](README.ko.md) · **日本語**

# MiniFriend

macOS ダイナミックアイランドスタイルのフローティングデスクトップ AI アシスタント。MacBook のノッチにぴったりとフィットし、マウスホバーで展開、音声入出力、ローカル/リモートモデルの切り替え、カスタムペルソナ、ピクセルアートアバターに対応しています。

## 機能

- **ダイナミックアイランド UI**: MacBook ノッチに密着、ホバーで展開／離れると収納、黒背景でノッチに自然に融合
- **会話バックエンド**: Claude（リモート）と Ollama（ローカル、完全オフライン）を自由に切り替え
- **音声出力**: VoxCPM-0.5B + 個人 LoRA ファインチューニング音声、ONNX 加速 DiT、文ごとの音声・映像同期
- **音声入力**: Apple Speech STT、マイクボタンをクリックして音声をテキストに変換
- **ピクセルアバター**: Codex Pets スタイルの chibi アバター、手続き型の呼吸／思考／発話アニメーション
- **ローカルメモリ**: Ollama 会話履歴をディスクに保存、再起動後もコンテキストを継続
- **設定パネル**: アシスタント名、ペルソナ、モデル選択、TTS トグル、Ollama パラメータ — すべてリアルタイム保存

## アーキテクチャ

```
MiniFriend/
├── app/                    # macOS SwiftUI クライアント
│   ├── Sources/MiniFriend/
│   │   ├── main.swift          # エントリポイント、AppDelegate
│   │   ├── ContentView.swift   # ダイナミックアイランド UI
│   │   ├── ChatViewModel.swift # 会話状態管理
│   │   ├── ClaudeClient.swift  # Claude CLI インターフェース
│   │   ├── OllamaClient.swift  # Ollama ローカルモデルインターフェース
│   │   ├── VoiceClient.swift   # TTS クライアント、文単位のパイプライン再生
│   │   ├── SpeechRecognizer.swift # STT（Apple Speech）
│   │   ├── VoiceServer.swift   # 音声サービスプロセス管理
│   │   ├── HoverMonitor.swift  # グローバルマウスイベントリスナー
│   │   ├── AppConfig.swift     # 設定の永続化
│   │   ├── SettingsView.swift  # 設定パネル
│   │   ├── PixelAvatar.swift   # ピクセルアバターアニメーション
│   │   ├── NotchShape.swift    # ダイナミックアイランド形状
│   │   ├── FloatingPanel.swift # フローティングウィンドウ
│   │   └── Resources/          # ピクセルアバターリソース
│   ├── Info.plist              # マイク/音声認識の許可
│   ├── Package.swift
│   └── package_app.sh          # ビルド＆パッケージスクリプト
│
├── voice-service/          # Python TTS サービス（FastAPI、ポート 8765）
│   ├── app.py              # FastAPI メインサービス、ウォームアップ含む
│   ├── config.py           # 環境変数設定
│   ├── backends/
│   │   ├── voxcpm_backend.py   # VoxCPM + ONNX DiT 高速化
│   │   └── base.py
│   ├── lora/               # 個人の音声 LoRA（リポジトリには非含）
│   │   ├── lora_config.json
│   │   └── lora_weights.safetensors  # 自身で学習が必要
│   └── requirements.txt
│
├── finetune/               # LoRA ファインチューニングスクリプト（クラウド GPU で実行）
│   ├── prepare_data.py     # オーディオスライス + Whisper 文字起こし
│   ├── voxcpm_finetune_lora.yaml
│   └── run_finetune.sh
│
└── avatar/                 # アバター生成スクリプト
    └── stylize_pixel.py    # 写真 → chibi ピクセルキャラクター
```

## クイックスタート

### 前提条件

- macOS 14+ (Apple Silicon)
- Xcode Command Line Tools
- Python 3.10+（Anaconda 推奨）
- Claude Code CLI（`~/.local/bin/claude`）または Ollama

### 1. 音声サービス

```bash
cd voice-service
pip install -r requirements.txt
python app.py          # 起動後自動ウォームアップ、約20秒で準備完了
```

サービスは `http://127.0.0.1:8765` で待機し、`POST /tts` エンドポイントを提供します。

### 2. App のビルド＆実行

```bash
cd app
./package_app.sh       # コンパイル + MiniFriend.app にパッケージ（権限署名含む）
open MiniFriend.app    # ダブルクリックまたは CLI から起動
```

> ⚠️ `open MiniFriend.app` で起動必須 — `swift run` は使用不可（マイク権限に .app バンドルが必要）

### 3. 個人音声 LoRA（オプション）

デフォルトのゼロショットクローニング（参照音声が必要）または個人 LoRA の学習：

```bash
# クラウド GPU 上で（RTX 3090/4090+、CUDA 12）
cd finetune
# 1. データ準備（your_audio.wav は単一ファイルまたはディレクトリ）
python prepare_data.py --src your_audio.wav --out /workspace/data --lang zh

# 2. 学習（約30-60分）
python scripts/train_voxcpm_finetune.py --config_path voxcpm_finetune_lora.yaml

# 3. latest/ ディレクトリの lora_config.json + lora_weights.safetensors を voice-service/lora/ にダウンロード
```

## 設定

すべての設定は App 内の歯車ボタンから変更可能、保存先:
```
~/Library/Application Support/MiniFriend/config.json
```

| 設定項目 | 説明 |
|---|---|
| アシスタント名 | UI と system prompt に表示 |
| ペルソナ | system prompt に追加、応答スタイルに影響 |
| 会話モデル | Claude（リモート）または Ollama（ローカルオフライン）|
| Ollama モデル | 例: `qwen3.5:4b`、事前に `ollama pull` が必要 |
| コンテキストウィンドウ | M3 Air 16GB では 8192 推奨 |
| 読み上げ | TTS オン/オフ |
| 音声サービス自動起動 | App 起動時に Python サービスを自動起動 |

### 環境変数（音声サービス）

| 変数 | デフォルト値 | 説明 |
|---|---|---|
| `MF_TTS_BACKEND` | `voxcpm` | TTS バックエンド |
| `MF_VOXCPM_MODEL` | `openbmb/VoxCPM-0.5B` | ベースモデル |
| `MF_VOXCPM_DEVICE` | `cpu` | 推論デバイス |
| `MF_VOXCPM_LORA` | `voice-service/lora` | LoRA ディレクトリ |
| `MF_HOST` | `127.0.0.1` | サービスホスト |
| `MF_PORT` | `8765` | サービスポート |

## ローカルモデル（Ollama）

```bash
# Ollama インストール
brew install ollama
ollama serve

# 推奨モデル（M3 Air 16GB + VoxCPM 共存）
ollama pull qwen3.5:4b   # 3.4GB、think:false 対応、反復防止に優れる
```

App 設定パネルで「ローカルモデル」に切り替え、モデル名を入力してください。完全オフライン — 会話データが端末の外に出ることはありません。

## 技術詳細

### 音声合成の高速化
- VoxCPM DiT コンポーネントを ONNX にエクスポート、推論速度 2.4 倍
- `inference_timesteps=6` で品質と速度のバランス（約5-6秒/文）
- FastAPI 直列ロックで同時合成による音声破損を防止
- 起動時のサイレントウォームアップで最初の文章のコールドスタート遅延を解消

### ダイナミックアイランドの操作
- グローバル `NSEvent` マウスリスナー（DynamicNotchKit/NotchDrop 参考）
- 応答中/発話中/合成中の3状態で自動収納をブロック
- `isPreparingVoice` で「テキスト生成完了→発話開始」間の収納空白を解消

### 会話の分離
- Claude: `--resume session_id` でマルチターンコンテキストを維持、セッションは `~/.claude/projects/-/` に保存
- Ollama: messages 配列をメモリに保持 + ディスクに永続化、KV Cache オーバーフロー防止のため最大10ターンに制限

