"""后端注册表。

TTS 后端: voxcpm (已实现)
变声层:   rvc / seed-vc (stub)

方案 B 管线: TTS 后端产出 wav -> 可选变声层 -> 最终 wav。
当前变声层未实现，convert 阶段被跳过。
"""

from __future__ import annotations

from .base import SynthesisResult, TTSBackend, VoiceConverter
from .rvc_backend import RVCConverter
from .seedvc_backend import SeedVCConverter
from .voxcpm_backend import VoxCPMBackend

_TTS_BACKENDS: dict[str, type[TTSBackend]] = {
    "voxcpm": VoxCPMBackend,
}

_CONVERTERS: dict[str, type[VoiceConverter]] = {
    "rvc": RVCConverter,
    "seed-vc": SeedVCConverter,
}

_tts_cache: dict[str, TTSBackend] = {}


def get_tts(name: str = "voxcpm", **kwargs) -> TTSBackend:
    if name not in _TTS_BACKENDS:
        raise ValueError(f"未知 TTS 后端: {name}. 可选: {list(_TTS_BACKENDS)}")
    if name not in _tts_cache:
        _tts_cache[name] = _TTS_BACKENDS[name](**kwargs)
    return _tts_cache[name]


def get_converter(name: str, **kwargs) -> VoiceConverter:
    if name not in _CONVERTERS:
        raise ValueError(f"未知变声层: {name}. 可选: {list(_CONVERTERS)}")
    return _CONVERTERS[name](**kwargs)


def available() -> dict[str, list[str]]:
    return {
        "tts": list(_TTS_BACKENDS),
        "converters": list(_CONVERTERS),
        "converters_implemented": [],  # 当前均为 stub
    }


__all__ = [
    "SynthesisResult",
    "TTSBackend",
    "VoiceConverter",
    "get_tts",
    "get_converter",
    "available",
]
