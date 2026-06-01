"""seed-vc 变声层 —— STUB（已注册，未实现）。

权重已就位：
  model/ft_model.pth   你微调过的 seed-vc 模型

待实现时需引入 seed-vc 推理代码，把源 wav 零样本/微调转成目标音色。
"""

from __future__ import annotations

from .base import SynthesisResult, VoiceConverter


class SeedVCConverter(VoiceConverter):
    name = "seed-vc"

    def __init__(self, model_path: str | None = None):
        self.model_path = model_path
        self._loaded = False

    def load(self) -> None:
        raise NotImplementedError(
            "seed-vc 变声层尚未实现（当前阶段只做 VoxCPM）。权重: model/ft_model.pth"
        )

    def convert(self, wav_bytes: bytes, sample_rate: int) -> SynthesisResult:
        raise NotImplementedError("seed-vc 变声层尚未实现。")
