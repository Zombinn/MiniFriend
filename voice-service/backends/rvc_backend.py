"""RVC 变声层 —— STUB（已注册，未实现）。

权重已就位：
  ~/Downloads/qt2.pth                              推理模型
  ~/Downloads/added_IVF1590_Flat_nprobe_1_qt2_v2.index  特征检索 index

待实现时需引入 RVC 推理代码（fairseq + faiss + hubert content encoder），
把 VoxCPM/基础TTS 产出的 wav 转成 qt2 训练的目标音色。
"""

from __future__ import annotations

from .base import SynthesisResult, VoiceConverter


class RVCConverter(VoiceConverter):
    name = "rvc"

    def __init__(self, model_path: str | None = None, index_path: str | None = None):
        self.model_path = model_path
        self.index_path = index_path
        self._loaded = False

    def load(self) -> None:
        raise NotImplementedError(
            "RVC 变声层尚未实现（当前阶段只做 VoxCPM）。"
            "权重: qt2.pth + added_IVF1590..._qt2_v2.index"
        )

    def convert(self, wav_bytes: bytes, sample_rate: int) -> SynthesisResult:
        raise NotImplementedError("RVC 变声层尚未实现。")
