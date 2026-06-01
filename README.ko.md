> [中文](README.md) · [English](README.en.md) · **한국어** · [日本語](README.ja.md)

# MiniFriend

macOS 다이내믹 아일랜드 스타일 플로팅 데스크탑 AI 어시스턴트입니다. MacBook 노치에 밀착되어 마우스 호버로 펼쳐지며, 음성 입출력, 로컬/원격 모델 전환, 커스텀 페르소나 및 픽셀 아트 아바타를 지원합니다.

---

## 기능

- **다이내믹 아일랜드 UI**: MacBook 노치에 밀착, 호버 시 펼쳐짐/벗어나면 접힘, 검은색 배경이 노치와 자연스럽게 융합
- **대화 백엔드**: Claude(원격)와 Ollama(로컬, 완전 오프라인) 자유롭게 전환
- **음성 출력**: VoxCPM-0.5B + 개인 LoRA 파인튜닝 음색, ONNX 가속 DiT, 문장별 오디오-비주얼 동기화
- **음성 입력**: Apple Speech STT, 마이크 버튼 클릭으로 음성을 텍스트로 변환
- **픽셀 아바타**: Codex Pets 스타일 chibi 아바타, 절차적 호흡/생각/말하기 애니메이션
- **로컬 메모리**: Ollama 대화 내역 디스크에 저장, 재시작 후에도 컨텍스트 유지
- **설정 패널**: 어시스턴트 이름, 페르소나, 모델 선택, TTS 토글, Ollama 파라미터 — 실시간 저장

---

## 아키텍처

```
MiniFriend/
├── app/                    # macOS SwiftUI 클라이언트
│   ├── Sources/MiniFriend/
│   │   ├── main.swift          # 진입점, AppDelegate
│   │   ├── ContentView.swift   # 다이내믹 아일랜드 UI
│   │   ├── ChatViewModel.swift # 대화 상태 관리
│   │   ├── ClaudeClient.swift  # Claude CLI 인터페이스
│   │   ├── OllamaClient.swift  # Ollama 로컬 모델 인터페이스
│   │   ├── VoiceClient.swift   # TTS 클라이언트, 파이프라인 문장 재생
│   │   ├── SpeechRecognizer.swift # STT (Apple Speech)
│   │   ├── VoiceServer.swift   # 음성 서비스 프로세스 관리
│   │   ├── HoverMonitor.swift  # 글로벌 마우스 이벤트 리스너
│   │   ├── AppConfig.swift     # 설정 지속성
│   │   ├── SettingsView.swift  # 설정 패널
│   │   ├── PixelAvatar.swift   # 픽셀 아바타 애니메이션
│   │   ├── NotchShape.swift    # 다이내믹 아일랜드 셰이프
│   │   ├── FloatingPanel.swift # 플로팅 윈도우
│   │   └── Resources/          # 픽셀 아바타 리소스
│   ├── Info.plist              # 마이크/음성인식 권한
│   ├── Package.swift
│   └── package_app.sh          # 빌드 및 패키징 스크립트
│
├── voice-service/          # Python TTS 서비스 (FastAPI, 포트 8765)
│   ├── app.py              # FastAPI 메인 서비스, 웜업 포함
│   ├── config.py           # 환경 변수 설정
│   ├── backends/
│   │   ├── voxcpm_backend.py   # VoxCPM + ONNX DiT 가속
│   │   └── base.py
│   ├── lora/               # 개인 음색 LoRA (저장소에 미포함)
│   │   ├── lora_config.json
│   │   └── lora_weights.safetensors  # 직접 학습 필요
│   └── requirements.txt
│
├── finetune/               # LoRA 파인튜닝 스크립트 (클라우드 GPU에서 실행)
│   ├── prepare_data.py     # 오디오 슬라이싱 + Whisper 전사
│   ├── voxcpm_finetune_lora.yaml
│   └── run_finetune.sh
│
└── avatar/                 # 아바타 생성 스크립트
    └── stylize_pixel.py    # 사진 → chibi 픽셀 캐릭터
```

---

## 빠른 시작

### 사전 요구사항

- macOS 14+ (Apple Silicon)
- Xcode Command Line Tools
- Python 3.10+ (Anaconda 권장)
- Claude Code CLI (`~/.local/bin/claude`) 또는 Ollama

### 1. 음성 서비스

```bash
cd voice-service
pip install -r requirements.txt
python app.py          # 시작 후 자동 웜업, ~20초 소요
```

서비스는 `http://127.0.0.1:8765`에서 수신하며 `POST /tts` 엔드포인트를 제공합니다.

### 2. App 빌드 및 실행

```bash
cd app
./package_app.sh       # 컴파일 + MiniFriend.app 패키징 (권한 서명 포함)
open MiniFriend.app    # 더블클릭 또는 CLI에서 실행
```

> ⚠️ `open MiniFriend.app`으로만 실행 가능 — `swift run` 사용 불가 (마이크 권한에 .app 번들 필요)

### 3. 개인 음색 LoRA (선택사항)

기본 제로샷 클로닝 (참조 오디오 필요) 또는 개인 LoRA 학습:

```bash
# 클라우드 GPU에서 (RTX 3090/4090+, CUDA 12)
cd finetune
# 1. 데이터 준비 (your_audio.wav는 단일 파일 또는 디렉토리 가능)
python prepare_data.py --src your_audio.wav --out /workspace/data --lang zh

# 2. 학습 (~30-60분)
python scripts/train_voxcpm_finetune.py --config_path voxcpm_finetune_lora.yaml

# 3. latest/ 디렉토리의 lora_config.json + lora_weights.safetensors를 voice-service/lora/로 다운로드
```

---

## 설정

모든 설정은 App 내 톱니바퀴 버튼으로 수정 가능, 저장 위치:
```
~/Library/Application Support/MiniFriend/config.json
```

| 설정 항목 | 설명 |
|---|---|
| 어시스턴트 이름 | UI 및 시스템 프롬프트에 표시 |
| 페르소나 | system prompt에 추가, 응답 스타일 영향 |
| 대화 모델 | Claude(원격) 또는 Ollama(로컬 오프라인) |
| Ollama 모델 | 예: `qwen3.5:4b`, `ollama pull` 선행 필요 |
| 컨텍스트 창 | M3 Air 16GB에 8192 권장 |
| 읽어주기 | TTS 켜기/끄기 |
| 음성 서비스 자동 시작 | App 시작 시 Python 서비스 자동 실행 |

### 환경 변수 (음성 서비스)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `MF_TTS_BACKEND` | `voxcpm` | TTS 백엔드 |
| `MF_VOXCPM_MODEL` | `openbmb/VoxCPM-0.5B` | 베이스 모델 |
| `MF_VOXCPM_DEVICE` | `cpu` | 추론 디바이스 |
| `MF_VOXCPM_LORA` | `voice-service/lora` | LoRA 디렉토리 |
| `MF_HOST` | `127.0.0.1` | 서비스 호스트 |
| `MF_PORT` | `8765` | 서비스 포트 |

---

## 로컬 모델 (Ollama)

```bash
# Ollama 설치
brew install ollama
ollama serve

# 권장 모델 (M3 Air 16GB + VoxCPM 공존)
ollama pull qwen3.5:4b   # 3.4GB, think:false 지원, 반복 방지 우수
```

App 설정 패널에서 '로컬 모델'로 전환하고 모델명을 입력하세요. 완전 오프라인 — 대화 데이터가 기기를 벗어나지 않습니다.

---

## 기술 세부사항

### 음성 합성 가속
- VoxCPM DiT 구성요소 ONNX로 내보내기, 추론 속도 2.4배
- `inference_timesteps=6`으로 품질과 속도 균형 (~5-6초/문장)
- FastAPI 직렬 잠금으로 동시 합성으로 인한 오디오 손상 방지
- 시작 시 무음 웜업으로 첫 문장 콜드스타트 지연 제거

### 다이내믹 아일랜드 상호작용
- 글로벌 `NSEvent` 마우스 리스너 (DynamicNotchKit/NotchDrop 참조)
- 응답 중/말하기 중/합성 중 세 가지 상태에서 자동 접힘 차단
- `isPreparingVoice`로 "텍스트 생성 완료 → 말하기 시작" 사이의 접힘 공백 제거

### 대화 격리
- Claude: `--resume session_id`로 멀티턴 컨텍스트 유지, 세션은 `~/.claude/projects/-/`에 저장
- Ollama: messages 배열을 메모리에 유지 + 디스크에 지속, KV Cache 오버플로 방지를 위해 최대 10턴으로 제한

---

## License

MIT
