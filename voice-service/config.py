"""voice-service 配置。环境变量可覆盖。"""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent

# 默认 TTS 后端
TTS_BACKEND = os.getenv("MF_TTS_BACKEND", "voxcpm")
VOXCPM_MODEL = os.getenv("MF_VOXCPM_MODEL", "openbmb/VoxCPM-0.5B")
# Apple Silicon 上 MPS 会在 warmup matmul 硬崩溃，默认 cpu。想试 mps 设 MF_VOXCPM_DEVICE=mps
VOXCPM_DEVICE = os.getenv("MF_VOXCPM_DEVICE", "cpu")
# 微调产物：把训练得到的 latest/ 目录路径填这，推理即用你的音色（无需参考片段）
# 默认指向本地 lora/（已放入微调权重）；存在才启用，否则空 = 退回零样本克隆需参考片段
_default_lora = str(ROOT / "lora")
VOXCPM_LORA = os.getenv(
    "MF_VOXCPM_LORA",
    _default_lora if (ROOT / "lora" / "lora_weights.safetensors").exists() else "",
)

# 可选变声层 (当前 stub)。空字符串 = 不变声。
VOICE_CONVERTER = os.getenv("MF_VOICE_CONVERTER", "")

# 目标音色参考音频 (VoxCPM 零样本克隆)。由用户提供。
REFERENCE_WAV = os.getenv("MF_REFERENCE_WAV", str(ROOT / "assets" / "reference.wav"))
# 参考音频的文字转录 (给了克隆保真度更高，可空)。
REFERENCE_TEXT = os.getenv("MF_REFERENCE_TEXT", "")

HOST = os.getenv("MF_HOST", "127.0.0.1")
PORT = int(os.getenv("MF_PORT", "8765"))


def reference_wav_or_none() -> str | None:
    p = Path(REFERENCE_WAV)
    return str(p) if p.exists() else None
