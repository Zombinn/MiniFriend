"""语音后端抽象。

设计为方案 B（VoxCPM 当底 + 可选变声层），但当前只实现 VoxCPM。
所有后端实现 `synthesize(text) -> wav bytes`，由 registry 统一调度。
变声层 (RVC / seed-vc) 走 VoiceConverter 接口，当前为 stub。
"""

from __future__ import annotations

import abc
from dataclasses import dataclass


@dataclass
class SynthesisResult:
    """合成结果：PCM 写入的 wav 字节流 + 采样率。"""

    wav_bytes: bytes
    sample_rate: int


class TTSBackend(abc.ABC):
    """文字转语音后端接口。"""

    name: str = "base"

    @abc.abstractmethod
    def load(self) -> None:
        """加载模型权重。允许重复调用（应内部幂等）。"""

    @abc.abstractmethod
    def synthesize(
        self,
        text: str,
        reference_wav: str | None = None,
        prompt_text: str | None = None,
    ) -> SynthesisResult:
        """把文字合成为语音。

        reference_wav: 目标音色参考片段路径（VoxCPM 零样本克隆需要）。
        prompt_text:   参考片段的文字转录，给了克隆保真度更高。
        """

    @property
    def ready(self) -> bool:
        return getattr(self, "_loaded", False)


class VoiceConverter(abc.ABC):
    """变声层接口：把一段源语音转成目标音色。

    方案 B 的第二级。当前 RVC / seed-vc 均为 stub。
    """

    name: str = "base"

    @abc.abstractmethod
    def load(self) -> None: ...

    @abc.abstractmethod
    def convert(self, wav_bytes: bytes, sample_rate: int) -> SynthesisResult: ...
